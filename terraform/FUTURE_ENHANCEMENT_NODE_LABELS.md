# Future Enhancement — Split Single Node Group into Two Labeled Node Groups

> **Why:** Currently, after every `terraform apply`, you must manually run `kubectl label node` to assign `role=tools` and `role=production` to the two nodes. This enhancement eliminates that manual step by baking the labels into the node group definitions themselves.

---

## Current Setup (Manual Labeling)

### eks.tf (lines 82-113) — Single node group

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  version         = aws_eks_cluster.main.version

  subnet_ids = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.small"]

  launch_template {
    name    = aws_launch_template.eks_nodes.name
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project_name}-node-group"
  }
  ...
}
```

**The problem:** This creates 2 nodes but neither has labels. You run:
```powershell
kubectl label node ip-10-0-XX-XX.ec2.internal role=tools
kubectl label node ip-10-0-YY-YY.ec2.internal role=production
```

If you `terraform destroy` + `terraform apply`, the labels are lost and you must redo them.

---

## Proposed Setup (Baked Labels)

### Replace the single node group with two (delete lines 82-113, add this):

```hcl
# ─────────────────────────────────────────────
# EKS Managed Node Group — Tools (for Jenkins)
# ─────────────────────────────────────────────
resource "aws_eks_node_group" "tools" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-tools"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  version         = aws_eks_cluster.main.version
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = ["t3.small"]

  # 🔑 This is the key line — EKS labels the node automatically
  labels = {
    role = "tools"
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  launch_template {
    name    = aws_launch_template.eks_nodes.name
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project_name}-tools-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry
  ]
}

# ─────────────────────────────────────────────
# EKS Managed Node Group — Production (for App)
# ─────────────────────────────────────────────
resource "aws_eks_node_group" "production" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-production"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  version         = aws_eks_cluster.main.version
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = ["t3.small"]

  # 🔑 Same approach, different label
  labels = {
    role = "production"
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2   # allows app to scale if needed
  }

  launch_template {
    name    = aws_launch_template.eks_nodes.name
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project_name}-production-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry
  ]
}
```

---

## What Gets Deleted vs Added

| Change | Resource | Status |
|---|---|---|
| ❌ **Delete** | `aws_eks_node_group.main` (lines 82-113) | Single group with 2 nodes, no labels |
| ✅ **Add** | `aws_eks_node_group.tools` | 1 node with baked-in `role=tools` |
| ✅ **Add** | `aws_eks_node_group.production` | 1 node with baked-in `role=production` |

### The launch template stays unchanged (lines 116-127):

```hcl
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.project_name}-node-template-"
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]
  tag_specifications { ... }
}
```

Both node groups share the **same launch template** — only the labels differ.

---

## Why This Form

**EKS managed node groups support a built-in `labels` field.** When you set:

```hcl
labels = { role = "tools" }
```

EKS automatically applies `role=tools` to every node in that group at boot time. This is the **native, supported way** to label nodes — no `kubectl label` needed, no scripts, no custom `user_data`.

### Why two separate groups instead of one group with two labels

A single node group can only have **one set of labels** applied to **all** nodes in that group. If you wrote:

```hcl
labels = { role = "tools", role = "production" }
```

That's invalid — a label key can only have one value. You'd get an error.

With **two groups**, each node gets exactly one `role` value. The `nodeSelector` in your deployments then pins pods to the correct group:

| YAML file | `nodeSelector` | Matches which node group |
|---|---|---|
| `k8s/jenkins/deployment.yaml` | `role: tools` | ✅ `tools` group |
| `k8s/jenkins/pvc.yaml` | `role: tools` | ✅ `tools` group |
| `k8s/application/backend-deployment.yaml` | `role: production` | ✅ `production` group |
| `k8s/application/frontend-deployment.yaml` | `role: production` | ✅ `production` group |

---

## How This Affects Current Resources

### During `terraform apply`

1. **Existing nodes are replaced.** Terraform sees the old single node group is gone and two new groups must be created. It will:
   - Delete the old node group → terminates both existing nodes
   - Create the `tools` node group → launches 1 new node
   - Create the `production` node group → launches 1 new node

2. **Pods will be temporarily unavailable.** During the transition:
   - Old nodes are drained and terminated
   - New nodes join the cluster (5-10 min)
   - You must re-run `kubectl apply -f k8s/application/` and `kubectl apply -f k8s/jenkins/` after the new nodes are `Ready`

3. **No `kubectl label node` needed** — ever again. After `terraform apply`, the new nodes already have their labels:
   ```
   kubectl get nodes -L role
   NAME                          ROLE
   ip-10-0-XX-XX.ec2.internal    tools
   ip-10-0-YY-YY.ec2.internal    production
   ```

### No other files need to change

All existing K8s YAML files (`backend-deployment.yaml`, `frontend-deployment.yaml`, `deployment.yaml`, `pvc.yaml`) already use `nodeSelector: role: production` or `nodeSelector: role: tools`. The label values are the same — only now EKS applies them instead of you typing `kubectl label ...`.

---

## Migration Steps (when ready)

```powershell
# 1. Edit eks.tf — delete the old node group, add the two new ones
# 2. Apply
cd terraform
terraform apply -var="rds_master_password=YourSecurePassword123!" -auto-approve

# 3. Wait for new nodes (5-10 min)
aws eks update-kubeconfig --region us-east-1 --name inventory-mgmt-cluster
kubectl get nodes -w

# 4. Verify labels are already applied (no manual labeling needed!)
kubectl get nodes -L role

# 5. Deploy the apps
kubectl apply -f k8s/application/
kubectl apply -f k8s/jenkins/
```
