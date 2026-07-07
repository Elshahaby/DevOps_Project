# Project Lifecycle Guide: Destroy & Recreate

> **Purpose:** Save money by destroying AWS resources when not in use, and know exactly how to rebuild everything step-by-step.
>
> **How to use:** Follow the **Destroy** section when you're done working. Follow the **Recreate** section when you want to start again.
>
> **Keeping it updated:** As we complete each new phase, come back to this file and add the new steps under both Destroy and Recreate sections.

---

### ⚠️ Important: URLs CHANGE after every destroy/recreate

Every time you destroy and recreate, AWS assigns **new unique identifiers** to resources:

| Resource | Changes? | What you need to do |
|---|---|---|
| **RDS endpoint** | ✅ New address | Update connection string in K8s Secrets (Phase 5) |
| **Jenkins LoadBalancer URL** | ✅ New URL | Open the new URL in your browser |
| **EKS API endpoint** | ✅ New endpoint | `aws eks update-kubeconfig` sets it automatically |
| **EC2 node names** | ✅ New IPs | Re-label nodes (`kubectl label node ... role=tools`) |
| **DockerHub images** | ❌ Same (permanent) | Nothing — they stay on DockerHub |

> **Bottom line:** After recreating, always run `terraform output` to get the new RDS endpoint, and `kubectl get svc -n jenkins` to get the new Jenkins URL.

---

## Table of Contents

1. [Cost Summary — What you're paying for](#1-cost-summary--what-youre-paying-for)
2. [Destroy Everything](#2-destroy-everything)
3. [Recreate Everything (Current: Phase 3)](#3-recreate-everything-current-phase-3)
   - [Prerequisites](#31-prerequisites)
   - [Phase 1: Terraform — VPC, EKS, RDS](#32-phase-1-terraform--vpc-eks-rds)
   - [Phase 2: Jenkins on Kubernetes](#33-phase-2-jenkins-on-kubernetes)
   - [Phase 3: Docker images on DockerHub](#34-phase-3-docker-images-on-dockerhub)
   - [Final verification](#35-final-verification)
4. [Estimated Time & Cost Tables](#4-estimated-time--cost-tables)
5. [Phase-by-phase checklist (to update as we go)](#5-phase-by-phase-checklist-to-update-as-we-go)

---

## 1. Cost Summary — What you're paying for

These AWS resources are **active 24/7** and incur charges even when nobody is using the application:

| Resource | Config | Est. Monthly Cost | Can I reduce it? |
|---|---|---|---|
| **EKS Control Plane** | 1 cluster × $0.10/hr | **~$73** | ❌ Required for cluster to exist |
| **NAT Gateway** | 1 × $0.045/hr + data | **~$33** | ❌ Required for private subnets |
| **Elastic IP** | 1 × not used | **~$3.60** | ❌ Attached to NAT Gateway |
| **RDS SQL Server Express** | db.t3.small × 20GB × $0.026/hr | **~$19** | ❌ Required for the app |
| **2x EC2 (EKS nodes)** | t3.small × $0.0208/hr | **~$30** | ❌ Required for workloads |
| **Application Load Balancer** | Jenkins ELB × $0.025/hr + LCU | **~$18** | ❌ Required for Jenkins access |
| **EBS volumes** | 2 × 20GB gp2 + Jenkins PV | **~$6** | ❌ Required for storage |
| **TOTAL** | | **~$183/month** | |

> **💡 Tip:** If you're only working 1-2 days per week, destroying and recreating saves ~$150/month.

---

## 2. Destroy Everything

Run these steps **in order**. Some resources depend on others, so the order matters.

### Step 1: Delete all Kubernetes resources — 2-5 min

```powershell
# 1. Delete Jenkins (Phase 2)
kubectl delete -f k8s/jenkins/

# 2. Delete application deployments (Phase 5 — uncomment when Phase 5 is done)
# kubectl delete -f k8s/application/

# 3. Verify nothing is left
kubectl get all -n jenkins        # Should show "No resources found"
kubectl get all --all-namespaces  # Should show only kube-system pods
```

**To add in future phases:**
- **Phase 4:** Pipeline jobs and credentials exist only inside Jenkins. To clean up: delete the pipeline job and credentials via the Jenkins web UI (Manage Jenkins → Credentials → Delete; Dashboard → Delete Pipeline job).
- **Phase 5:** Uncomment line 2 above and add `kubectl delete -f k8s/application/`

> **Why first?** Kubernetes resources (pods, services, PVCs) hold references to AWS resources like Load Balancers and EBS volumes. Terraform can't destroy those AWS resources while K8s is using them.

### Step 2: Delete Kubernetes node group and cluster through Terraform — 15-20 min

```powershell
cd terraform

# Destroy only K8s resources first (cleaner, avoids dependency errors)
terraform destroy -target "aws_eks_node_group.main" -auto-approve
terraform destroy -target "aws_eks_cluster.main" -auto-approve
```

> Wait for these to complete before proceeding.

### Step 3: Clear your local kubectl config — 1 min

```powershell
kubectl config delete-context arn:aws:eks:us-east-1:712481457925:cluster/inventory-mgmt-cluster
kubectl config delete-cluster arn:aws:eks:us-east-1:712481457925:cluster/inventory-mgmt-cluster
```

> **Why?** After destroying the cluster, kubectl will give connection errors. Removing the old context keeps your terminal clean.

### Step 4: Unset the Terraform state lock (if needed) — 1 min

If you get an error about `state lock`, run:
```powershell
terraform force-unlock <LOCK_ID>
```

### Step 5: Destroy ALL remaining infrastructure — 5-10 min

```powershell
terraform destroy -auto-approve
```

> This destroys: VPC, subnets, IGW, NAT Gateway, route tables, security groups, IAM roles, RDS, Elastic IP.

### Step 6: Verify in AWS Console — 2 min

1. Go to https://console.aws.amazon.com/vpc → Your VPCs → Should show only the **default VPC**
2. Go to https://console.aws.amazon.com/eks → Clusters → Should show **no clusters**
3. Go to https://console.aws.amazon.com/rds → Databases → Should show **no databases**
4. Go to https://console.aws.amazon.com/ec2 → Load Balancers → Should show **no load balancers**
5. Go to https://console.aws.amazon.com/ec2 → Elastic IPs → Should show **no Elastic IPs**

### ⚠️ Important reminders:

| Resource | Manual cleanup needed? | Notes |
|---|---|---|
| **DockerHub images** | ✅ Optional | Images stay on DockerHub. Delete repos manually if you want |
| **Local Docker images** | ✅ Optional | `docker image prune -a` to clean up locally |
| **Terraform state files** | ❌ Keep them | They're in your repo (`terraform/terraform.tfstate`). Terraform needs these to track what it created |
| **GitHub repo** | ❌ Keep it | All your code stays on GitHub |

---

## 3. Recreate Everything (Current: Phase 4)

### 3.1 Prerequisites

Before you start, make sure you have:

| Tool | Purpose | Verify with |
|---|---|---|
| **AWS CLI** | Authenticate with AWS | `aws --version` |
| **AWS credentials** | Allow Terraform to act on your behalf | `aws sts get-caller-identity` (should show your account ID: 712481457925) |
| **Terraform** | Create infrastructure | `terraform --version` (needs >= 1.5) |
| **kubectl** | Manage Kubernetes | `kubectl version --client` |
| **Docker Desktop** | Build and push images | `docker --version` |
| **DockerHub account** | Store Docker images | `docker login -u mohamedelshahaby` (use Access Token) |

If `aws sts get-caller-identity` fails, run:
```powershell
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Region: us-east-1
# Output format: json
```

### 3.2 Phase 1: Terraform — VPC, EKS, RDS

**Estimated time: 25-35 minutes**

#### Step 1: Initialize Terraform (ONLY if first time or new machine)

`terraform init` downloads provider plugins to the `.terraform/` folder. This folder **persists** on your machine — you only need to run this once, not every time.

**When to run `terraform init`:**
| Scenario | Run `terraform init`? |
|---|---|
| First time setting up this project | ✅ Yes |
| After `git clone` on a new computer | ✅ Yes |
| Recreating after `terraform destroy` (same machine) | ❌ **No — skip to Step 2** |
| Changed provider versions in `main.tf` | ✅ Yes |
| Deleted the `.terraform/` folder | ✅ Yes |

```powershell
cd terraform
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

#### Step 2: Preview the changes

```powershell
terraform plan -var="rds_master_password=YourSecurePassword123!"
```

Review the plan. It should show: `Plan: 33 to add, 0 to change, 0 to destroy.`

#### Step 3: Apply

```powershell
terraform apply -var="rds_master_password=YourSecurePassword123!"
```

Type `yes` when prompted.

**⏱ What takes long:**
| Resource | Approx. time |
|---|---|
| EKS cluster | ~8-10 minutes |
| EKS node group | ~2-3 minutes |
| RDS SQL Server | ~12-15 minutes |
| Everything else | ~2 minutes |

#### Step 4: Configure kubectl

```powershell
aws eks update-kubeconfig --region us-east-1 --name inventory-mgmt-cluster
```

Verify:
```powershell
kubectl get nodes
# Should show 2 nodes with status "Ready"
```

#### Step 5: Label the nodes

```powershell
# Get node names
kubectl get nodes -o name

# Label one as tools (for Jenkins)
kubectl label node ip-10-0-XX-XX.ec2.internal role=tools

# Label the other as production (for app pods)
kubectl label node ip-10-0-YY-YY.ec2.internal role=production
```

> Use the actual node names from `kubectl get nodes`. Pick **one** for tools, the other for production.

#### Step 6: Create the database in RDS

```powershell
kubectl run create-db --image=mcr.microsoft.com/azure-sql-edge --rm -it --restart=Never -- `
  /opt/mssql-tools/bin/sqlcmd -No -S inventory-mgmt-sqlserver.c2fc20q44515.us-east-1.rds.amazonaws.com,1433 `
  -U admin -P "YourSecurePassword123!" -Q "CREATE DATABASE InventoryManagementDb;"
```

Verify:
```powershell
kubectl run check-db --image=mcr.microsoft.com/azure-sql-edge --rm -it --restart=Never -- `
  /opt/mssql-tools/bin/sqlcmd -No -S inventory-mgmt-sqlserver.c2fc20q44515.us-east-1.rds.amazonaws.com,1433 `
  -U admin -P "YourSecurePassword123!" -Q "SELECT name FROM sys.databases;"
```

You should see `InventoryManagementDb` in the list.

### 3.3 Phase 2: Jenkins on Kubernetes

**Estimated time: 5-10 minutes**

#### Step 1: Apply all Jenkins resources

```powershell
# From the project root
kubectl apply -f k8s/jenkins/
```

This creates:
- `jenkins` namespace
- `jenkins-home` PVC (10GB PV on the tools node)
- `jenkins-sa` ServiceAccount
- `jenkins-cluster-role` ClusterRole
- `jenkins-cluster-role-binding` ClusterRoleBinding
- `jenkins` Deployment (Jenkins + dind sidecar)
- `jenkins-service` LoadBalancer

#### Step 2: Wait for the pod to be ready

Watch the pod status:
```powershell
kubectl get pods -n jenkins -w
```

It should transition: `Pending` → `Init:0/3` → `Init:1/3` → `Init:2/3` → `Init:3/3` → `PodInitializing` → `Running (2/2)`

Total time: ~2-3 minutes.

#### Step 3: Get the Jenkins LoadBalancer URL

```powershell
kubectl get svc -n jenkins
```

Look for the `EXTERNAL-IP` column — it will show a URL like:
```
ac451a57a90144826816070bc9f5c3a5-1527490744.us-east-1.elb.amazonaws.com
```

Open `http://<URL>:8080` in your browser.

#### Step 4: Verify Jenkins works

```powershell
# Get the pod name (first column from `kubectl get pods`)
kubectl get pods -n jenkins
# Copy the pod name (e.g., jenkins-7d9f8c6b4-x5k2h)

# Then run:
kubectl exec -n jenkins <pod-name> -c jenkins -- kubectl get nodes
kubectl exec -n jenkins <pod-name> -c jenkins -- docker ps
```

Both commands should succeed without errors.

### 3.4 Phase 3: Docker images on DockerHub

**Estimated time: 5-10 minutes**

#### Step 1: Login to DockerHub

```powershell
docker login -u mohamedelshahaby
# Use your Access Token, not your password
```

#### Step 2: Build the Docker images

```powershell
# Build Backend
docker build -t inventory_backend:latest ./Backend

# Build Frontend
docker build -t inventory_frontend:latest ./Frontend
```

#### Step 3: Tag and push to DockerHub

```powershell
# Tag
docker tag inventory_frontend:latest mohamedelshahaby/inventory-frontend:latest
docker tag inventory_backend:latest  mohamedelshahaby/inventory-backend:latest

# Push
docker push mohamedelshahaby/inventory-frontend:latest
docker push mohamedelshahaby/inventory-backend:latest
```

#### Step 4: Verify on DockerHub

Open https://hub.docker.com/u/mohamedelshahaby — both repositories should exist.

### 3.5 Phase 4: Jenkins Pipeline — Install plugins, add credentials, create job

**Estimated time: 15-20 minutes**

The Jenkinsfile already exists in the repo. You just need to configure Jenkins to use it.

#### Step 1: Get Jenkins URL

```powershell
kubectl get svc -n jenkins
# Copy the EXTERNAL-IP URL and open http://<URL>:8080
```

#### Step 2: Install required plugins

In the Jenkins web UI:

1. Go to **Manage Jenkins** → **Plugins** → **Available plugins**
2. Search for and install **Docker Pipeline** + **GitHub Integration** plugins
3. Restart Jenkins after installation

#### Step 3: Add DockerHub credentials

> **⚠️ 403 error?** If the form shows `HTTP ERROR 403 No valid crumb was included`, disable CSRF from the Jenkins Script Console (`http://<jenkins-url>:8080/script`):
> ```groovy
> import jenkins.model.Jenkins
> Jenkins.instance.setCrumbIssuer(null)
> ```
> Then refresh and retry.

1. Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. Fill in:

| Field | Value |
|---|---|
| Kind | **Username with password** |
| Username | `mohamedelshahaby` |
| Password | Your DockerHub Access Token (not your password!) |
| ID | `dockerhub-credentials` (**must match the Jenkinsfile**) |
| Description | `DockerHub credentials for pushing images` |

#### Step 4: Add GitHub credentials (only for private repo)

> **ℹ️ For this project:** Our repo is **Public** — **skip this step entirely**. In the Pipeline job (Step 5), set `Credentials` → `- none -`.
>
> The steps below are for reference if you use a private repo later.

If your repo is **private**, create a GitHub Personal Access Token:

1. Go to https://github.com/settings/tokens → **Generate new token** → **Fine-grained token**
2. Name: `jenkins-ci-token`, Expiration: 90 days, Repo access: **Only select repositories** → your repo
3. Permissions → **Contents** → **Read-only**
4. **Copy the token**

Then add it to Jenkins:

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. Fill in:

| Field | Value |
|---|---|
| Kind | **Username with password** |
| Username | Your GitHub username |
| Password | The Personal Access Token |
| ID | `github-credentials` |
| Description | `GitHub credentials for cloning the repo` |

#### Step 5: Create the Pipeline job

1. Click **New Item** → name: `Inventory-App Pipeline` → select **Pipeline** → OK
2. Scroll to the **Pipeline** section
3. Configure:

| Field | Value |
|---|---|
| Definition | **Pipeline script from SCM** |
| SCM | **Git** |
| Repository URL | `https://github.com/YOUR_ORG/inventory-app.git` (replace with actual URL) |
| Credentials | `github-credentials` (if private) or `- none -` (if public) |
| Branch | `*/main` |
| Script Path | `Jenkinsfile` (default) |

4. Click **Save**

#### Step 6: Setup GitHub Webhook (automatic triggers)

1. In Jenkins, go to the pipeline job → **Configure** → **Build Triggers** → check **GitHub hook trigger for GITScm polling** → **Save**
2. In GitHub, go to repo → **Settings** → **Webhooks** → **Add webhook**
3. Fill in:

| Field | Value |
|---|---|
| **Payload URL** | `http://<jenkins-external-ip>:8080/github-webhook/` |
| **Content type** | `application/json` |
| **Events** | **Just the push event** |

4. Click **Add webhook**

#### Step 7: Run the pipeline

1. Open the pipeline job
2. Click **Build Now**
3. Watch the stage view — each stage should turn green

Expected result:
- Checkout ✅
- Build Backend ✅
- Test Backend ✅ (skips — no test project yet)
- Build Frontend ✅
- Test Frontend ✅ (or skips gracefully)
- Build & Push Docker Images ✅
- Deploy to Kubernetes ⚠️ (skips — `k8s/application/` does not exist until Phase 5)

#### Step 8: Verify images on DockerHub

```powershell
Write-Output "Images pushed with build number tag:"
Write-Output "  mohamedelshahaby/inventory-frontend:1"
Write-Output "  mohamedelshahaby/inventory-frontend:latest"
Write-Output "  mohamedelshahaby/inventory-backend:1"
Write-Output "  mohamedelshahaby/inventory-backend:latest"
```

### 3.6 Final verification

Run this checklist to confirm everything is working:

```powershell
# 1. Cluster and nodes
Write-Output "=== CLUSTER ==="
kubectl cluster-info
kubectl get nodes

# 2. Node labels
Write-Output "`n=== NODE LABELS ==="
kubectl get nodes --show-labels | findstr "role"

# 3. Jenkins
Write-Output "`n=== JENKINS ==="
kubectl get all -n jenkins
# Jenkins URL — copy the EXTERNAL-IP from the output above and open http://<EXTERNAL-IP>:8080

# 4. Docker images on DockerHub
Write-Output "`n=== DOCKERHUB ==="
Write-Output "https://hub.docker.com/u/mohamedelshahaby"

# 5. RDS
Write-Output "`n=== RDS ==="
terraform output rds_endpoint
Write-Output "Use SSMS or sqlcmd to connect and verify InventoryManagementDb exists"

# 6. Jenkins Pipeline
Write-Output "`n=== JENKINS PIPELINE ==="
Write-Output "Open http://$JENKINS_URL`:8080/job/Inventory-App%20Pipeline/ and check last build"
Write-Output "Expected: All stages green (Deploy stage skips until Phase 5)"
```

### ⬜ Phase 5 (Coming soon — K8s Application Deployments)

*When Phase 5 is complete, the recreate steps here will include:*
1. Creating Kubernetes Secrets for RDS connection string
2. Deploying Frontend + Backend pods on the `role=production` node
3. Creating a LoadBalancer for the Frontend
4. Verifying the full application works end-to-end

*Check back after Phase 5 is done.*

---

## 4. Estimated Time & Cost Tables

### Destroy time (total: ~25-40 min)

| Step | Time | Notes |
|---|---|---|
| Delete K8s resources | 2-5 min | kubectl delete |
| Destroy EKS node group | 2-3 min | terraform destroy -target |
| Destroy EKS cluster | 5-8 min | terraform destroy -target |
| Destroy all | 5-10 min | terraform destroy |
| Verify in AWS Console | 2 min | Manual check |
| **Total** | **~16-28 min** |  |


### Recreate time (total: ~40-60 min)

| Phase | Time | Notes |
|---|---|---|
| **Prerequisites** | 5 min | Check tools, AWS credentials |
| **Phase 1 (Terraform)** | 25-35 min | Most time is EKS + RDS provisioning |
| **Phase 2 (Jenkins)** | 5-10 min | Apply YAMLs, wait for pod |
| **Phase 3 (Docker)** | 5-10 min | Build, tag, push |
| **Phase 4 (Pipeline)** | 15-20 min | Install plugins, create credentials + pipeline job in Jenkins |
| **Total** | **~55-80 min** | Mostly waiting for AWS |

### Cost savings

| Scenario | Monthly Cost |
|---|---|
| **Always on** (24/7) | ~$183/month |
| **Destroy when idle** (~40 hours/week) | ~$43/month |
| **Savings** | **~$140/month** |

> 💡 **Recommendation:** Destroy on Friday night, recreate on Monday morning. You save ~$140/month.

---

## 5. Phase-by-phase checklist (to update as we go)

As we complete new phases in this project, add the destroy and recreate steps here.

### ✅ Phase 1 (Complete)

| Action | Done? |
|---|---|
| Destroy: Terraform `terraform destroy` | ☐ |
| Recreate: `terraform init && terraform apply` | ☐ |
| Recreate: `aws eks update-kubeconfig` | ☐ |
| Recreate: Label nodes (tools + production) | ☐ |
| Recreate: Create InventoryManagementDb in RDS | ☐ |

### ✅ Phase 2 (Complete)

| Action | Done? |
|---|---|
| Destroy: `kubectl delete -f k8s/jenkins/` | ☐ |
| Recreate: `kubectl apply -f k8s/jenkins/` | ☐ |
| Recreate: Verify Jenkins pod is Running (2/2) | ☐ |
| Recreate: Get Jenkins LoadBalancer URL | ☐ |

### ✅ Phase 3 (Complete)

| Action | Done? |
|---|---|
| Destroy: `docker image prune -a` (optional) | ☐ |
| Destroy: Delete DockerHub repos (manual on website) | ☐ |
| Recreate: `docker build -t inventory_backend:latest ./Backend` | ☐ |
| Recreate: `docker build -t inventory_frontend:latest ./Frontend` | ☐ |
| Recreate: `docker push` both images to DockerHub | ☐ |

### ✅ Phase 4 (Complete)

| Action | Done? |
|---|---|
| Destroy: Delete Jenkins pipeline jobs (manual via Jenkins UI) | ☐ |
| Destroy: Remove DockerHub credentials from Jenkins | ☐ |
| Destroy: Remove GitHub credentials from Jenkins *(only if using private repo)* | ☐ |
| Destroy: Delete GitHub webhook *(only if you set one up)* | ☐ |
| Recreate: Install Docker Pipeline + GitHub Integration plugins in Jenkins | ☐ |
| Recreate: Add DockerHub Access Token as Jenkins credential (ID: `dockerhub-credentials`) | ☐ |
| Recreate: *(Skip — our repo is public)* Create GitHub Personal Access Token and add as Jenkins credential | — |
| Recreate: Create Pipeline job "Inventory-App Pipeline" — repo URL + **Credentials: `- none -`** (public repo) | ☐ |
| Recreate: Enable "GitHub hook trigger" in job config | ☐ |
| Recreate: Add webhook in GitHub repo (Payload: http://\<jenkins-url\>:8080/github-webhook/) | ☐ |
| Recreate: Push a commit to test webhook auto-trigger | ☐ |
| Recreate: Run first pipeline build and verify all stages pass | ☐ |

### ⬜ Phase 5 (Not completed yet)

**Fill these in after Phase 5 is done (K8s App Deployments):**

| Action | Done? |
|---|---|
| Destroy: `kubectl delete -f k8s/application/` | ☐ |
| Recreate: `kubectl apply -f k8s/application/` | ☐ |
| Recreate: Verify frontend and backend pods are Running | ☐ |
| Recreate: Get frontend LoadBalancer URL | ☐ |

> **How to update this file:** After each phase is completed, edit this section and add the specific destroy/recreate actions for that phase. Also update the **Recreate Everything** section to include the new phase's steps.

---

## Quick Reference: Common Commands

### Terraform

```powershell
cd terraform

# Initialize (first time or after pulling new code)
terraform init

# See what would change
terraform plan -var="rds_master_password=YourPassword123!"

# Apply changes
terraform apply -var="rds_master_password=YourPassword123!"

# Destroy all
terraform destroy -auto-approve

# Destroy specific resource
terraform destroy -target "aws_eks_node_group.main" -auto-approve

# See current state
terraform state list
```

### Kubectl

```powershell
# Get nodes
kubectl get nodes

# Get Jenkins resources
kubectl get all -n jenkins
kubectl get pods -n jenkins -w

# Apply Kubernetes manifests
kubectl apply -f k8s/jenkins/

# Delete Kubernetes manifests
kubectl delete -f k8s/jenkins/

# Run command inside Jenkins container
kubectl exec -n jenkins <pod-name> -c jenkins -- <command>

# View logs
kubectl logs -n jenkins <pod-name> -c jenkins
kubectl logs -n jenkins <pod-name> -c dind
```

### Docker

```powershell
# Build images
docker build -t inventory_frontend:latest ./Frontend
docker build -t inventory_backend:latest ./Backend

# Tag for DockerHub
docker tag inventory_frontend:latest mohamedelshahaby/inventory-frontend:latest

# Push to DockerHub
docker push mohamedelshahaby/inventory-frontend:latest

# Clean up unused images
docker image prune -a
```

---

> **Last updated:** Phase 4 complete. Next update when Phase 5 is done.
