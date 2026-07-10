# Troubleshooting Log — Problems Faced & Solutions

> Every issue encountered during the DevOps lifecycle, root cause, and how we fixed it.

---

## Table of Contents

1. [Frontend can't reach backend in production (CORS)](#1-frontend-cant-reach-backend-in-production-cors)
2. [Terraform partial apply left dangling resources](#2-terraform-partial-apply-left-dangling-resources)
3. [Terraform destroy partially failed — orphaned resources](#3-terraform-destroy-partially-failed--orphaned-resources)
4. [Can Jenkins BUILD_NUMBER survive destroy/recreate?](#4-can-jenkins-build_number-survive-destroyrecreate)
5. [Backend can't connect to RDS — "server not found"](#5-backend-cant-connect-to-rds--server-not-found)
6. [EKS Node Group update stuck in Failed state](#6-eks-node-group-update-stuck-in-failed-state)
7. [New nodes can't register with EKS cluster API](#7-new-nodes-cant-register-with-eks-cluster-api)
8. [Backend pods crash-looping — liveness probe 404](#8-backend-pods-crash-looping--liveness-probe-404)
9. [Node labels lost after terraform destroy/apply](#9-node-labels-lost-after-terraform-destroyapply)
10. [tfplan accidentally committed to git](#10-tfplan-accidentally-committed-to-git)

---

## 1. Frontend can't reach backend in production (CORS)

### Problem

The Angular interceptor hardcoded `http://localhost:5097` as the API base URL. In development (`ng serve`), the backend runs on `localhost:5097` — works fine. In production (Kubernetes), the backend pod has a private IP inside the cluster that the browser can't reach.

**Error:** Network Error — API calls fail in production.

**Relevant code (`Frontend/src/app/core/interceptors/api-url.interceptor.ts`):**
```typescript
const apiBaseUrl = 'http://localhost:5097';
```

### Root Cause

- The browser loaded Angular from the LoadBalancer URL (e.g., `http://a5b2c3d4...elb.amazonaws.com`)
- The interceptor rewrote `/api/products` to `http://localhost:5097/api/products`
- `localhost:5097` means the **user's own machine** — nothing is running there
- Even if the backend was exposed publicly, the different origin would trigger a **CORS error**

### Solution

Three changes across files:

**a) Angular interceptor — use `isDevMode()` to switch URLs:**

```typescript
const apiBaseUrl = isDevMode()
  ? 'http://localhost:5097'           // dev: direct to backend
  : window.location.origin;           // prod: same origin (Nginx proxy)
```

**b) Nginx reverse proxy (`Frontend/nginx.conf`):**

```nginx
location /api/ {
    proxy_pass http://backend-service.production.svc.cluster.local:5097;
}
```

Nginx runs in the **same pod** as the Angular static files. When the browser calls `http://<lb-url>/api/products`, Nginx intercepts it and forwards to the backend inside the cluster — all from the **same origin**, bypassing CORS entirely.

**c) Backend CORS config (`Backend/InventoryManagement.API/Program.cs`):**

```csharp
var corsOrigins = builder.Configuration["Cors:AllowedOrigins"] ?? "http://localhost:4200";
```

Made the CORS origins configurable via the `Cors__AllowedOrigins` environment variable, so it supports both development (`localhost:4200`) and future production URLs.

**d) K8s env var (`k8s/application/backend-deployment.yaml`):**

```yaml
- name: Cors__AllowedOrigins
  value: "http://localhost:4200"
```

### Related files

- `Frontend/src/app/core/interceptors/api-url.interceptor.ts`
- `Frontend/nginx.conf`
- `Backend/InventoryManagement.API/Program.cs`
- `k8s/application/backend-deployment.yaml`
- `Frontend/NGINX_EXPLANATION.md` (full line-by-line Nginx explanation)

---

## 2. Terraform partial apply left dangling resources

### Problem

A previous `terraform apply` timed out after 1+ hours. It had **actually created** some resources (EKS cluster, RDS, NAT Gateway) but the state file didn't record them properly. The next `terraform apply` failed with:

```
Error: creating EKS Cluster: ResourceInUseException: Cluster already exists
Error: creating RDS DB Instance: DBInstanceAlreadyExists: DB instance already exists
Error: waiting for NAT Gateway create: unexpected state 'failed'
```

### Root Cause

The resources existed in AWS but Terraform's state file didn't track them. Terraform tried to create them again, which AWS rejected.

### Solution

Option A was to `terraform import` each existing resource. We chose Option B instead — manual cleanup:

```powershell
# Delete RDS (holds ENIs that block VPC deletion)
aws rds delete-db-instance --db-instance-identifier inventory-mgmt-sqlserver --skip-final-snapshot

# Delete EKS cluster (holds ENIs that block VPC deletion)
aws eks delete-cluster --name inventory-mgmt-cluster

# Wait for both to finish, then retry terraform destroy
terraform destroy -auto-approve -var="rds_master_password=YourPass123"
```

### Lesson

Always verify `terraform apply` completed successfully before moving on. Use `terraform state list` to confirm resources are tracked.

---

## 3. Terraform destroy partially failed — orphaned resources

### Problem

`terraform destroy` deleted IAM roles, launch template, NAT gateway, and route tables, but **failed** on the VPC, subnets, security groups, and internet gateway with errors like:

```
Error: deleting EC2 Internet Gateway: DependencyViolation
Error: deleting Security Group: DependencyViolation
Error: deleting EC2 Subnet: DependencyViolation
```

### Root Cause

EKS cluster and RDS were **not tracked in Terraform state** (from the partial apply), so `terraform destroy` never attempted to delete them. Their ENIs (Elastic Network Interfaces) were still attached to the VPC, blocking VPC/Subnet/SG/IGW deletion.

### Solution

1. Manually deleted RDS and EKS cluster via AWS CLI
2. Once those were gone, their ENIs were released
3. Re-ran `terraform destroy` — it successfully removed everything else

### Verification commands

```powershell
aws rds describe-db-instances               # Should return []
aws eks list-clusters                        # Should return []
aws ec2 describe-instances                   # Should return []
aws ec2 describe-addresses                   # Should return []
aws ec2 describe-nat-gateways                # Should return []
```

### Related file

- `AWS_AUDIT_GUIDE.md` (complete resource audit checklist)

---

## 4. Can Jenkins BUILD_NUMBER survive destroy/recreate?

### Problem

The user asked: if we `terraform destroy` (which deletes EKS + nodes), then `terraform apply` again, does Jenkins know the last BUILD_NUMBER and increment it?

### Root Cause

Jenkins stores its data (build records, BUILD_NUMBER counter, jobs, credentials) in `/var/jenkins_home`. The Jenkins deployment mounts a PVC (`k8s/jenkins/pvc.yaml`) that uses `hostPath` — meaning data is stored on the **node's local disk**.

### Analysis

| Scenario | BUILD_NUMBER persists? |
|---|---|
| Pod restarts (same node) | ✅ Yes — data at `/data/jenkins-home` on the node |
| Terraform destroy (node terminated) | ❌ No — node disk is wiped |
| Terraform apply (new node) | ❌ No — fresh node with empty disk |

### Current situation

The `hostPath` PVC works **perfectly for the user's goal** — they WANT a clean slate after destroy/recreate so BUILD_NUMBER resets to 1. No fix needed.

If persistent Jenkins data were desired later, the PVC would need an **EBS-backed PersistentVolume** instead of `hostPath`.

### Related file

- `k8s/jenkins/pvc.yaml` (lines 1-33 — uses `hostPath`)

---

## 5. Backend can't connect to RDS — "server not found"

### Problem

After `terraform apply`, the backend pods started but immediately crashed with:

```
Microsoft.Data.SqlClient.SqlException:
A network-related or instance-specific error occurred while establishing
a connection to SQL Server. The server was not found or was not accessible.
```

The backend has a retry loop (10 attempts, 5 seconds apart), but all 10 attempts failed.

### Initial suspect check

**RDS status:** ✅ `"available"`
**RDS endpoint:** ✅ Correct DNS name
**Connection string in secret:** ✅ Correct password
**RDS SG ingress rule (port 1433 from node SG):** ✅ Found and correct

### Root Cause

The EKS launch template had **no `vpc_security_group_ids`** specified (line 116-127 in `eks.tf`). When no SGs are specified, EKS creates an **automatic SG** for the nodes. The RDS ingress rule referenced our custom `inventory-mgmt-eks-nodes-sg` — but the nodes were in the **EKS-managed SG**, not our custom SG.

### Solution

Added the node SG to the launch template:

```hcl
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.project_name}-node-template-"
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]   # ← ADDED
  ...
}
```

This ensures every new node gets both the EKS-managed SG (for cluster communication) and our custom node SG (for RDS access).

### Result after fix

Backend logs showed: `"Database seeding completed successfully."`

### Related files

- `terraform/eks.tf` (lines 116-127)
- `terraform/security-groups.tf` (lines 72-79 — RDS ingress rule)

---

## 6. EKS Node Group update stuck in Failed state

### Problem

After adding the node SG to the launch template, `terraform apply` tried to update the existing node group to use the new launch template version. The update failed because the **new nodes couldn't join the cluster** (due to issue #7 below). The node group entered a `Failed` state.

### Root Cause

The node group was in `UPDATING` status but the new nodes never became `Ready`. Each subsequent `terraform apply` failed with:

```
Error: updating EKS Node Group: ResourceInUseException:
Nodegroup cannot be updated as it is currently not in Active State
```

### Solution

Tainted the resource to force recreation:

```powershell
cd terraform
terraform taint aws_eks_node_group.main
terraform apply -var="rds_master_password=YourSecurePassword123!" -auto-approve
```

Terraform:
1. Destroyed the old (failed) node group (took ~9 min — draining nodes)
2. Created a brand new node group (took ~2 min — new nodes launched)

---

## 7. New nodes can't register with EKS cluster API

### Problem

After adding `vpc_security_group_ids` to the launch template, the new nodes launched but never joined the cluster. The node group creation timed out with:

```
NodeCreationFailure: Couldn't proceed with upgrade process as new nodes
are not joining node group
```

### Root Cause

The EKS **cluster security group** didn't allow inbound traffic from the **node security group** on **port 443** (kubelet → API server registration). We had these rules:

| Rule | Exists? |
|---|---|
| Cluster SG → Node SG (port 0-65535) | ✅ Egress |
| Node SG ← Cluster SG (port 0-65535) | ✅ Ingress |
| Node SG ← Node SG (all protocols) | ✅ Ingress |
| Cluster SG ← Node SG (port 443) | ❌ **Missing** |

The new nodes tried to register with the EKS API server on port 443 but the cluster SG blocked the connection.

### Solution

Added the missing ingress rule to `security-groups.tf`:

```hcl
resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
```

### Related file

- `terraform/security-groups.tf` (lines 60-66 — added after `nodes_to_nodes`)

---

## 8. Backend pods crash-looping — liveness probe 404

### Problem

After RDS connection was fixed, the backend pods kept restarting. After ~30 seconds they would crash and restart. `kubectl logs` showed the app started successfully and seeded the database:

```
info: Program[0]
      Database seeding completed successfully.
info: Microsoft.Hosting.Lifetime[0]
      Now listening on: http://[::]:5097
```

But then the pod restarted.

### Root Cause

The liveness probe checked `/health` and the readiness probe checked `/ready`:

```yaml
livenessProbe:
  httpGet:
    path: /health     # ❌ No such endpoint in the backend
    port: 5097
readinessProbe:
  httpGet:
    path: /ready      # ❌ No such endpoint in the backend
    port: 5097
```

Neither endpoint existed in the backend code. The probe returned **404** → Kubernetes thought the app was unhealthy → killed the pod → crash-loop.

### Solution

Added health endpoints to `Backend/InventoryManagement.API/Program.cs`, placed **before** `UseAuthentication()` so no JWT token is required:

```csharp
app.UseCors("AllowAll");
app.MapGet("/health", () => Results.Ok("healthy"));   // ← ADDED
app.MapGet("/ready", () => Results.Ok("ready"));       // ← ADDED
app.UseAuthentication();
```

Then rebuilt and pushed the Docker image:

```powershell
docker build -f Backend/Dockerfile -t mohamedelshahaby/inventory-backend:latest Backend
docker push mohamedelshahaby/inventory-backend:latest
kubectl rollout restart deployment -n production backend
```

### Result after fix

```
NAME                       READY   STATUS    RESTARTS   AGE
backend-xxx                1/1     Running   0          3m4s    ← Stable!
```

### Related files

- `Backend/InventoryManagement.API/Program.cs` (lines 166-167)
- `k8s/application/backend-deployment.yaml` (lines 57-68)

---

## 9. Node labels lost after terraform destroy/apply

### Problem

After every `terraform destroy` + `terraform apply`, the EKS worker nodes come up without the `role=tools` and `role=production` labels. The user must manually run:

```powershell
kubectl label node $(kubectl get nodes -o name | Select-Object -First 1) role=tools
kubectl label node $(kubectl get nodes -o name | Select-Object -Last 1) role=production
```

Without these labels, `nodeSelector` in the K8s manifests doesn't match any node, and pods stay `Pending`.

### Root Cause

The current launch template (and node group) doesn't set any labels. EKS managed node groups support a `labels` field, but our single node group doesn't use it.

### Current Approach (Manual)

Keep running the two `kubectl label` commands after each `terraform apply`. It's simple and works.

### Future Enhancement

Split the single node group into two, each with baked-in labels:

```hcl
resource "aws_eks_node_group" "tools" {
  labels = { role = "tools" }
  scaling_config { desired_size = 1 }
}

resource "aws_eks_node_group" "production" {
  labels = { role = "production" }
  scaling_config { desired_size = 1 }
}
```

### Related file

- `terraform/FUTURE_ENHANCEMENT_NODE_LABELS.md` (full migration plan)

---

## 10. tfplan accidentally committed to git

### Problem

After running `terraform plan -out=tfplan`, the binary `tfplan` file appeared as an untracked file in `git status`. Binary plan files should never be committed.

### Root Cause

The `.gitignore` had entries for `*.tfstate` and `*.tfvars` but not for plan files.

### Solution

Added to `.gitignore`:

```
# Terraform plan files
*plan
*.plan
```

This matches both `tfplan` (no extension) and `production.tfplan` (with extension).

### Related file

- `.gitignore` (lines 106-107 — under Terraform section)

---

## Summary of Root Causes

| # | Problem | Root Cause Category | Fix Type |
|---|---|---|---|
| 1 | CORS in production | Application architecture | Code change + Nginx config |
| 2 | Dangling resources after partial apply | Terraform state management | Manual cleanup |
| 3 | Terraform destroy partially failed | Resource dependency ordering | Manual cleanup |
| 4 | BUILD_NUMBER persistence | Jenkins storage (hostPath) | No fix needed (desired behavior) |
| 5 | Backend can't reach RDS | Missing node SG in launch template | Terraform config change |
| 6 | Node group update stuck Failed | Cascading failure from #7 | `terraform taint` + recreate |
| 7 | New nodes can't register with API | Missing SG rule (port 443) | Terraform config change |
| 8 | Backend crash-looping | Missing health endpoints | Backend code change + image rebuild |
| 9 | Node labels lost after recreate | Node group doesn't set labels | Manual (current) / Split groups (future) |
| 10 | tfplan in git | Missing gitignore rule | `.gitignore` change |
