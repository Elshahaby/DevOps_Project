# Phase 2 — Jenkins on Kubernetes: Complete Code Explanation

> **Target Audience:** Junior DevOps Team (assumes basic terminal knowledge, but NO Kubernetes, Jenkins, or AWS experience)
>
> **Goal:** Understand what each Kubernetes YAML file does, why it exists, what every single line means — so you can explain it to instructors and understand the CI/CD architecture.

## What's covered:

1. **Kubernetes from absolute zero** — what a cluster, node, pod, deployment, service, namespace, volume are (with warehouse worker analogies)
2. J**enkins from scratch** — what it is, why we need it, how the master + dind architecture works
3. **Every file line-by-line:**
    - namespace.yaml — the folder concept
    - rbac.yaml — employee badge analogy (ServiceAccount = who, ClusterRole = what doors, ClusterRoleBinding = handing the badge)
    - pvc.yaml — PV vs PVC explained as "external hard drive that follows the tools node"
    - deployment.yaml — init containers (why 3? kubectl copy, docker copy, permission fix), Jenkins container + dind sidecar, resource requests/limits, nodeSelector
    - service.yaml — LoadBalancer type creates AWS ELB, traffic flow from browser to pod
4. **Full architecture diagram** — how every piece connects
5. **Troubleshooting table** — common problems and fixes
6. **12 review questions for instructor discussions**

---

## Table of Contents

1. [What is Kubernetes and what are we building?](#1-what-is-kubernetes-and-what-are-we-building)
2. [What is Jenkins and why do we need it?](#2-what-is-jenkins-and-why-do-we-need-it)
3. [File-by-file breakdown](#3-file-by-file-breakdown)
   - [namespace.yaml](#31-namespaceyaml---creating-a-workspace)
   - [rbac.yaml](#32-rbacyaml---permissions-for-jenkins)
   - [pvc.yaml](#33-pvcyaml---persistent-storage)
   - [deployment.yaml](#34-deploymentyaml---the-jenkins-pod)
   - [service.yaml](#35-serviceyaml---exposing-jenkins-to-the-internet)
4. [How everything connects](#4-how-everything-connects)
5. [How to interact with Phase 2 resources](#5-how-to-interact-with-phase-2-resources)

---

## 1. What is Kubernetes and what are we building?

### The problem Kubernetes solves

Imagine you have a web application that 1,000 people use at the same time. You run it on one server. What happens when:
- 10,000 people show up? → The server crashes (too many requests).
- The server's hard drive dies? → The application goes offline.
- You need to update the app? → You have downtime.

**Kubernetes (K8s)** solves these problems by treating your servers as a **"cluster"** — a pool of resources (CPU, memory, disk) that it manages automatically. You tell Kubernetes: "I want 3 copies of my app running." If one copy crashes, Kubernetes starts a new one. If traffic increases, Kubernetes creates more copies.

### Key Kubernetes concepts you MUST understand

| Concept | What it is | Real-world analogy |
|---|---|---|
| **Cluster** | A group of servers (nodes) that K8s manages | A warehouse with many workers |
| **Node** | A single server (EC2 instance) | One worker in the warehouse |
| **Pod** | The smallest thing in K8s — runs one or more containers | A worker's workstation |
| **Deployment** | Tells K8s: "Keep this many copies of a Pod running" | A supervisor saying "keep 5 workstations active" |
| **Service** | Gives a stable address to reach a Pod (even if the Pod moves) | A reception desk that knows where each worker is |
| **Namespace** | A way to group resources together (like a folder) | A section of the warehouse labeled "Jenkins" |
| **Volume** | Storage that survives Pod restarts | A filing cabinet that stays even if the desk is moved |

### What we are building in Phase 2

We are deploying **Jenkins** (a tool that runs our CI/CD pipelines) onto our Kubernetes cluster. Jenkins will:
1. Be reachable from the internet (so GitHub can send webhooks to it)
2. Have permissions to run `kubectl apply` commands (so it can deploy our app)
3. Have Docker installed (so it can build container images)
4. Run on a specific node (the "tools" node), leaving the other node for our application

---

## 2. What is Jenkins and why do we need it?

### The problem Jenkins solves

When you write code, you need to:
1. **Test it** — does it still work after your changes?
2. **Build it** — compile the code, create a Docker image
3. **Package it** — push the image to DockerHub
4. **Deploy it** — update the application on Kubernetes

Doing all of this manually every time you change code is:
- Slow (takes 15 minutes of clicking around)
- Error-prone (you might forget a step)
- Unrepeatable (did you do the same thing last time?)

**Jenkins** automates this process. You write a **pipeline** (a script with all the steps), and Jenkins runs it automatically every time you push code to GitHub.

### Jenkins' architecture in our setup

```
┌─────────────────────────────────────────┐
│         Jenkins Pod                      │
│  ┌─────────────────┐  ┌──────────────┐  │
│  │  Jenkins Master  │  │  Docker dind │  │
│  │  (Java process)  │  │  (Docker     │  │
│  │  - runs pipeline │  │   daemon)    │  │
│  │  - kubectl apply │  │  - builds    │  │
│  │  - triggers jobs │  │   images     │  │
│  └────────┬─────────┘  └──────┬───────┘  │
│           │                   │          │
│           │   localhost:2375  │          │
│           └───────────────────┘          │
└─────────────────────────────────────────┘
```

- **Jenkins Master**: The brain. Reads the pipeline script, decides what to do, runs shell commands.
- **Docker-in-Docker (dind) sidecar**: A helper container that runs a Docker daemon. Jenkins calls it when it needs to build Docker images.
- **All in one Pod**: Everything runs on the same node, sharing storage and network.

---

## 3. File-by-file breakdown

### 3.1 `namespace.yaml` — Creating a workspace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins
```

#### What is a Namespace?

A **Namespace** is like a labeled folder in Kubernetes. Without namespaces, all resources (pods, services, volumes) would be in one big pile. Namespaces let us organize them.

In our project:
- `jenkins` namespace → All Jenkins-related resources
- (Later) `default` or `production` namespace → Our application pods

This prevents conflicts — you could have a pod named "frontend" in both namespaces and they wouldn't interfere with each other.

#### Line-by-line:

| Line | What it does |
|---|---|
| `apiVersion: v1` | Tells Kubernetes: "This file uses the core API version 1" (different resource types have different API versions) |
| `kind: Namespace` | Declares: "I want to create a Namespace" |
| `metadata:` | Information about the resource (like a label on a folder) |
| `name: jenkins` | The namespace's name. All resources we create with `namespace: jenkins` will go in this folder |

#### How to see it:

```bash
kubectl get namespaces
# Returns: default, jenkins, kube-system, etc.
```

`kube-system` is where Kubernetes itself runs. `default` is where you put things if you don't specify a namespace. We created `jenkins` to keep things clean.

---

### 3.2 `rbac.yaml` — Permissions for Jenkins

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-sa
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-cluster-role
rules:
  - resources: ["*"]
    apiGroups: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-cluster-role-binding
subjects:
  - kind: ServiceAccount
    name: jenkins-sa
    namespace: jenkins
roleRef:
  kind: ClusterRole
  name: jenkins-cluster-role
  apiGroup: rbac.authorization.k8s.io
```

#### What is RBAC?

**RBAC** = Role-Based Access Control. It answers the question: **"Who is allowed to do what?"**

Think of it like a company building:
- **ServiceAccount** = An employee badge (identifies WHO)
- **ClusterRole** = A list of doors the badge can open (WHAT they can do)
- **ClusterRoleBinding** = The act of handing the badge to the employee (connecting WHO to WHAT)

#### Why does Jenkins need this?

Jenkins needs to run `kubectl apply -f deployment.yaml` to deploy your application. Without RBAC, Jenkins would get an error: "User 'jenkins-sa' cannot create deployments." The RBAC file gives Jenkins permission to do anything (`verbs: ["*"]`) on any resource (`resources: ["*"]`).

> **Security note:** In production, you would limit Jenkins to only specific resources (like deployments, services) and specific namespaces. For learning, we give full access.

#### The three parts explained:

##### Part 1: ServiceAccount (`---` line separates YAML documents)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-sa
  namespace: jenkins
```

| Line | What it does |
|---|---|
| `kind: ServiceAccount` | Creates an identity that the Jenkins pod will use |
| `name: jenkins-sa` | The name we'll reference in the deployment (`serviceAccountName: jenkins-sa`) |
| `namespace: jenkins` | This identity lives in the jenkins namespace |

##### Part 2: ClusterRole (The permissions)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-cluster-role
rules:
  - resources: ["*"]
    apiGroups: ["*"]
    verbs: ["*"]
```

| Line | What it does |
|---|---|
| `kind: ClusterRole` | A role that applies to the ENTIRE cluster (not just one namespace) |
| `rules:` | The actual permissions |
| `resources: ["*"]` | "All resource types" — pods, deployments, services, secrets, everything |
| `apiGroups: ["*"]` | "All API groups" — some resources belong to different API groups (apps, networking, etc.) |
| `verbs: ["*"]` | "All actions" — get, list, create, update, delete, patch, watch |

Put together: **"Jenkins can do ANYTHING to ANY resource in the cluster."**

##### Part 3: ClusterRoleBinding (The connection)

```yaml
subjects:
  - kind: ServiceAccount
    name: jenkins-sa
    namespace: jenkins
roleRef:
  kind: ClusterRole
  name: jenkins-cluster-role
  apiGroup: rbac.authorization.k8s.io
```

| Line | What it does |
|---|---|
| `subjects:` | "Who gets the permissions" |
| `kind: ServiceAccount` | We're giving it to a ServiceAccount (not a user or group) |
| `name: jenkins-sa` | The specific ServiceAccount name |
| `namespace: jenkins` | Where to find that ServiceAccount |
| `roleRef:` | "Which role to give them" |
| `kind: ClusterRole` | We're referencing a ClusterRole |
| `name: jenkins-cluster-role` | The specific role name |
| `apiGroup: rbac.authorization.k8s.io` | The API group that manages RBAC |

**The three files together mean:** "Take the ServiceAccount 'jenkins-sa', give it the ClusterRole 'jenkins-cluster-role' (which allows everything), and whenever a pod uses that ServiceAccount, it gets those permissions."

---

### 3.3 `pvc.yaml` — Persistent Storage

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-home-pv
spec:
  storageClassName: manual
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/jenkins-home"
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: role
              operator: In
              values:
                - tools
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-home
  namespace: jenkins
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

#### Why does Jenkins need persistent storage?

Jenkins keeps all its data in `/var/jenkins_home/`:
- Job configurations (pipeline scripts)
- Build logs
- Plugin installations
- Credentials (encrypted)

If the Jenkins pod restarts (crashes, node reboots, etc.), **all of this data would be lost** without persistent storage. That would mean reconfiguring Jenkins from scratch every time.

#### What is a PersistentVolume (PV)?

A **PV** is a piece of storage in the cluster that exists independently of any pod. Think of it as an external hard drive — even if you replace your computer (pod), the hard drive still has your files.

#### What is a PersistentVolumeClaim (PVC)?

A **PVC** is a "request" for storage. The pod says: "I need 10GB of disk space" (the PVC), and Kubernetes finds a PV that can satisfy that request.

#### PV line-by-line:

```yaml
kind: PersistentVolume
metadata:
  name: jenkins-home-pv
```

Creates a PV resource named `jenkins-home-pv`.

```yaml
spec:
  storageClassName: manual
```

**StorageClass** is a type of storage. `manual` is a custom name we invented — it tells Kubernetes: "Don't use AWS automatic provisioning, we're defining this volume manually."

```yaml
  capacity:
    storage: 10Gi
```

The volume has **10 Gibibytes** of space (10 GiB ≈ 10.7 GB). This is enough for Jenkins job histories and build artifacts for a learning project.

```yaml
  accessModes:
    - ReadWriteOnce
```

| Mode | Meaning |
|---|---|
| `ReadWriteOnce` | One pod can read and write to it at a time |
| `ReadOnlyMany` | Many pods can read it, but not write |
| `ReadWriteMany` | Many pods can read and write at the same time |

Jenkins only needs one pod to access it, so `ReadWriteOnce` is sufficient.

```yaml
  hostPath:
    path: "/data/jenkins-home"
```

**`hostPath`** means: "Use a directory on the actual node's hard drive." The directory `/data/jenkins-home` will be created on the tools node's disk.

> **Comparison to cloud storage:**
> - `hostPath` = using your laptop's internal hard drive
> - AWS EBS volume = using an external USB drive that can move between laptops
> 
> `hostPath` is simpler for learning. The trade-off is: if the tools node dies, the data is lost. For production, you'd use EBS volumes.

```yaml
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: role
              operator: In
              values:
                - tools
```

**Node Affinity** tells Kubernetes: "This PV can ONLY be used on a node with the label `role=tools`." This is important because `hostPath` storage lives on a specific node — if a pod tries to use this PV on a different node, the directory wouldn't exist there.

#### PVC line-by-line:

```yaml
kind: PersistentVolumeClaim
metadata:
  name: jenkins-home
  namespace: jenkins
```

Creates a PVC named `jenkins-home` in the `jenkins` namespace.

```yaml
spec:
  storageClassName: manual
```

Must match the PV's `storageClassName` — this is how Kubernetes matches claims to volumes.

```yaml
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

"I want a ReadWriteOnce volume with at least 10Gi of space." Kubernetes sees this, finds the PV that matches, and **binds** them together.

#### How PV and PVC work together:

```
User creates PVC (request) ──→ Kubernetes looks for PV that matches ──→ Binds them
                                    │
                              Our PV matches:
                              - Same storage class (manual)
                              - Same access mode (ReadWriteOnce)
                              - Enough capacity (10Gi)
                              - Compatible node affinity
```

After binding, the pod can use the PVC by referencing its name (`claimName: jenkins-home`), and data flows: **Pod → PVC → PV → `/data/jenkins-home` on the tools node**.

---

### 3.4 `deployment.yaml` — The Jenkins Pod

This is the most complex file. Let's understand it piece by piece.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      serviceAccountName: jenkins-sa
      nodeSelector:
        role: tools
```

#### What is a Deployment?

A **Deployment** tells Kubernetes: "I want exactly N copies of this Pod running at all times." It handles:
- Creating pods
- Restarting pods that crash
- Rolling updates (changing the pod's configuration without downtime)

#### Top-level fields:

| Line | What it does |
|---|---|
| `apiVersion: apps/v1` | Deployments live in the `apps/v1` API group (not core `v1`) |
| `kind: Deployment` | This is a Deployment resource |
| `name: jenkins` | The deployment's name |
| `namespace: jenkins` | It lives in the jenkins namespace |
| `replicas: 1` | Run exactly 1 copy of the Jenkins pod. We only need one because Jenkins has its own job queuing |
| `selector:` | Tells Kubernetes which pods belong to this deployment |
| `matchLabels: app: jenkins` | "Only manage pods that have the label `app=jenkins`" |

#### The Pod Template (`template:`):

```yaml
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      serviceAccountName: jenkins-sa
      nodeSelector:
        role: tools
```

| Line | What it does |
|---|---|
| `template.metadata.labels` | Every pod created by this deployment gets the label `app=jenkins`. The Service uses this label to find the pod |
| `serviceAccountName: jenkins-sa` | This pod will use the ServiceAccount we created in rbac.yaml. This is how the pod gets permissions to run `kubectl` commands |
| `nodeSelector:` | "Only schedule this pod on a node with this label" |
| `role: tools` | Pin the pod to the node labeled `role=tools`. This ensures Jenkins runs on Node 1, leaving Node 2 for our application |

#### 💡 Key learning point: nodeSelector

Without `nodeSelector`, Kubernetes would randomly place the pod on any available node. With 2 nodes (tools + production), we need to ensure:
- Jenkins → always on the tools node
- Application pods → always on the production node

`nodeSelector` is the simplest way to do this. 
<br>
<br>
The node was labeled earlier with:

```bash
kubectl label node ip-10-0-10-35.ec2.internal role=tools
kubectl label node ip-10-0-20-138.ec2.internal role=production
```

#### ⚠️ Important: Labels are ephemeral (temporary)

The `kubectl label` command is applied **at runtime** — it's not saved anywhere permanent. If the nodes are ever **replaced** (e.g., scaling the node group, upgrading AMI, node failure), the labels are **lost** and must be re-applied.

You can verify labels with:
```bash
kubectl get nodes --show-labels | findstr "role"
```

In **Phase 5**, we'll make these labels permanent by adding them directly to the EC2 launch template in `terraform/eks.tf` — this way, whenever a new node joins the cluster, it automatically gets the correct label without manual intervention.

---

#### The Containers:

##### Container 1: Jenkins Master

```yaml
      containers:
        - name: jenkins
          image: jenkins/jenkins:lts-jdk17
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 50000
              name: jnlp
```

| Line | What it does |
|---|---|
| `name: jenkins` | The container's name (used in logs: `kubectl logs -c jenkins`) |
| `image: jenkins/jenkins:lts-jdk17` | The Docker image to use. `jenkins/jenkins` is the official image, `lts-jdk17` means "Long Term Support release with Java 17" |
| `containerPort: 8080` | Jenkins' web UI listens on port 8080 inside the container |
| `name: http` | A human-readable name for this port |
| `containerPort: 50000` | Jenkins uses this port for agents (when you connect build slaves). We expose it for future use |
| `name: jnlp` | Java Network Launch Protocol — the protocol Jenkins agents use to connect |

##### Environment Variables

```yaml
          env:
            - name: JAVA_OPTS
              value: "-Djenkins.install.runSetupWizard=false"
            - name: DOCKER_HOST
              value: "tcp://localhost:2375"
```

| Environment Variable | Value | What it does |
|---|---|---|
| `JAVA_OPTS` | `-Djenkins.install.runSetupWizard=false` | Skips the Jenkins setup wizard. Normally, the first time you access Jenkins, it asks you to paste an admin password and install plugins. This flag skips that step and starts Jenkins with no security (admin user has full access without password). **For learning only — never do this in production** |
| `DOCKER_HOST` | `tcp://localhost:2375` | Tells Jenkins' Docker CLI where to find the Docker daemon. Since our Docker daemon runs in another container (dind) in the same pod, they can communicate via `localhost` (the pod's internal network). Port `2375` is Docker's default TCP port |

##### `Production Setup (when you're ready to secure Jenkins)`

For a real production deployment, you would **remove** the `JAVA_OPTS` environment variable (or set it to empty) so the setup wizard runs normally:

**Step 1:** Change the deployment.yaml environment variable from:
```yaml
- name: JAVA_OPTS
  value: "-Djenkins.install.runSetupWizard=false"
```
to:
```yaml
- name: JAVA_OPTS
  value: ""
```

**Step 2:** Apply the change and wait for the new pod:
```bash
kubectl apply -f k8s/jenkins/deployment.yaml
kubectl delete pod -n jenkins --all
kubectl get pods -n jenkins -w
```

**Step 3:** Retrieve the auto-generated admin password:
```bash
kubectl logs -n jenkins <pod-name> -c jenkins | findstr "Admin password"
```
Or directly from the pod's filesystem:
```bash
kubectl exec -n jenkins <pod-name> -c jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

**Step 4:** Open Jenkins in your browser at the LoadBalancer URL:
```
http://<loadbalancer-hostname>:8080
```

The setup wizard will guide you through:
1. Pasting the admin password (from Step 3)
2. Installing suggested plugins
3. Creating your admin user (username, password, name, email)
4. Configuring the Jenkins URL

After this, Jenkins has proper authentication — no one can access it without logging in.

---

##### Volume Mounts

```yaml
          volumeMounts:
            - name: jenkins-home
              mountPath: /var/jenkins_home
            - name: docker-socket
              mountPath: /var/run
            - name: tools
              mountPath: /usr/local/bin/kubectl
              subPath: kubectl
            - name: tools
              mountPath: /usr/local/bin/docker
              subPath: docker
```

| Volume mount | Path in container | Why |
|---|---|---|
| `jenkins-home` | `/var/jenkins_home` | Jenkins' data directory (configs, jobs, logs). Needs to be persistent so data survives restarts |
| `docker-socket` | `/var/run` | The Docker socket directory. The dind container creates `/var/run/docker.sock` here, and Jenkins needs to see it to communicate with Docker |
| `tools` (kubectl) | `/usr/local/bin/kubectl` | The kubectl binary (copied by an init container). Mounted as a file at `/usr/local/bin/kubectl` so Jenkins can run `kubectl` commands |
| `tools` (docker) | `/usr/local/bin/docker` | The Docker CLI binary. Mounted as a file at `/usr/local/bin/docker` so Jenkins can run `docker` commands |

**Why use `subPath`?** A single volume (`tools`) contains multiple files (kubectl, docker). `subPath: kubectl` means "only mount the file named `kubectl` from this volume to this path." This allows one volume to serve multiple file mounts.

##### Resource Limits

```yaml
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "1Gi"
              cpu: "1"
```

| Setting | Value | Meaning |
|---|---|---|
| `requests.memory` | `512Mi` | "Guarantee at least 512 Megabytes of RAM to Jenkins" |
| `requests.cpu` | `500m` | "Guarantee at least 0.5 CPU cores" (500 millicores) |
| `limits.memory` | `1Gi` | "Never let Jenkins use more than 1 Gigabyte of RAM" |
| `limits.cpu` | `1` | "Never let Jenkins use more than 1 full CPU core" |

**Why use both requests and limits?** 
- **Requests** = The minimum the container needs. Kubernetes uses this to decide which node to place the pod on (it checks: "does this node have at least 512Mi free?")
- **Limits** = The maximum the container is allowed. If Jenkins tries to use more than 1GB RAM, Kubernetes throttles it (or kills it if it keeps growing).

This is called a **Burstable QoS** — the container can burst up to its limits when extra resources are available.

---

##### Container 2: Docker-in-Docker (dind)

```yaml
        - name: dind
          image: docker:dind
          securityContext:
            privileged: true
          env:
            - name: DOCKER_TLS_CERTDIR
              value: ""
          volumeMounts:
            - name: jenkins-home
              mountPath: /var/jenkins_home
            - name: docker-storage
              mountPath: /var/lib/docker
            - name: docker-socket
              mountPath: /var/run
```

#### Why do we need Docker-in-Docker?

Jenkins needs to build Docker images (e.g., `docker build -t myapp:latest .`). To build images, you need a **Docker daemon** running. Normally, Docker runs directly on your machine. But inside a container, there's no Docker daemon.

Two solutions:

| Approach | How it works | Our choice? |
|---|---|---|
| **Docker-out-of-Docker** | Mount the host's Docker socket (`/var/run/docker.sock`) from the EC2 node. Jenkins uses the node's Docker daemon | ❌ Doesn't work on EKS (EKS uses containerd, not Docker) |
| **Docker-in-Docker (dind)** | Run a second container with Docker daemon inside it. Jenkins talks to it via localhost | ✅ Works everywhere, fully self-contained |

#### dind line-by-line:

| Line | What it does |
|---|---|
| `image: docker:dind` | The official Docker-in-Docker image. It contains everything needed to run a Docker daemon |
| `securityContext.privileged: true` | Grants this container elevated permissions. Docker needs this to create network interfaces, mount filesystems, etc. **Important security note:** The dind container has root access on the node |
| `DOCKER_TLS_CERTDIR: ""` | Disables TLS encryption for Docker's TCP connection. Sets it to empty string so Docker listens on plain TCP port 2375 without requiring certificates. Simpler for learning |
| `mountPath: /var/jenkins_home` | Same volume as Jenkins — when Jenkins builds Docker images, the build context needs to be accessible to the Docker daemon |
| `mountPath: /var/lib/docker` | Docker's data directory (images, containers, volumes). Uses a separate `emptyDir` so it doesn't fill up Jenkins' persistent storage |
| `mountPath: /var/run` | The Docker socket directory. Docker creates `/var/run/docker.sock` here, which Jenkins accesses via the shared volume |

---

#### Init Containers

```yaml
      initContainers:
        - name: install-kubectl
          image: bitnami/kubectl:latest
          command:
            - sh
            - -c
            - |
              cp /opt/bitnami/kubectl/bin/kubectl /tools/kubectl
          volumeMounts:
            - name: tools
              mountPath: /tools
        - name: install-docker-cli
          image: docker:cli
          command:
            - sh
            - -c
            - |
              cp /usr/local/bin/docker /tools/docker
          volumeMounts:
            - name: tools
              mountPath: /tools
        - name: fix-permissions
          image: alpine:latest
          command:
            - sh
            - -c
            - |
              chown 1000:1000 /var/jenkins_home
          volumeMounts:
            - name: jenkins-home
              mountPath: /var/jenkins_home
```

#### What is an Init Container?

An **init container** runs to completion BEFORE the main containers start. Use cases:
1. **Prepare files** — copy binaries, generate configs
2. **Wait for dependencies** — check if a database is ready
3. **Fix permissions** — change ownership of volumes

Once all init containers finish successfully, the main containers (jenkins, dind) start.

#### Init 1: install-kubectl

| Line | What it does |
|---|---|
| `image: bitnami/kubectl:latest` | Uses Bitnami's kubectl image (which contains the kubectl binary) |
| `cp /opt/bitnami/kubectl/bin/kubectl /tools/kubectl` | Copies the kubectl binary from the container's filesystem to the shared `tools` volume. The Jenkins container will mount this as `/usr/local/bin/kubectl` |

#### Init 2: install-docker-cli

Same concept — uses the Docker CLI image to copy the `docker` binary to the shared tools volume:
| `cp /usr/local/bin/docker /tools/docker` | Copies the docker binary so Jenkins can run `docker` commands |

#### Init 3: fix-permissions

```yaml
          command:
            - sh
            - -c
            - |
              chown 1000:1000 /var/jenkins_home
```

| Line | What it does |
|---|---|
| `image: alpine:latest` | A tiny Linux distribution (5MB) — perfect for running a single command |
| `chown 1000:1000 /var/jenkins_home` | Changes ownership of the `/var/jenkins_home` directory to user ID 1000, group ID 1000. Why? The Jenkins container runs as user `jenkins` (UID 1000). The hostPath volume is created as root (UID 0). Jenkins can't write to a root-owned directory. This init container fixes that before Jenkins starts |

#### The Three Init Containers Flow:

```
1. install-kubectl    ──→  copies kubectl binary to /tools/kubectl
2. install-docker-cli ──→  copies docker binary to /tools/docker
3. fix-permissions    ──→  chown /var/jenkins_home to jenkins user
                              ↓
                    Main containers start:
                    jenkins + dind
```

---

#### Volumes Section

```yaml
      volumes:
        - name: jenkins-home
          persistentVolumeClaim:
            claimName: jenkins-home
        - name: docker-socket
          emptyDir: {}
        - name: docker-storage
          emptyDir: {}
        - name: tools
          emptyDir: {}
```

| Volume name | Type | Purpose |
|---|---|---|
| `jenkins-home` | `persistentVolumeClaim` | Persistent storage for Jenkins data (jobs, configs, logs). Uses the PVC we created in pvc.yaml |
| `docker-socket` | `emptyDir` | A temporary directory shared between Jenkins and dind. Jenkins reads the Docker socket from here, dind writes it here |
| `docker-storage` | `emptyDir` | Temporary storage for Docker images and containers. This keeps Docker's data separate from Jenkins' data |
| `tools` | `emptyDir` | Temporary storage for the kubectl and docker binaries. Init containers write here, main containers read from here |

#### What is `emptyDir`?

An **emptyDir** is a temporary directory that:
- Starts empty when the pod is created
- Is shared between ALL containers in the pod
- Is deleted when the pod is destroyed
- Is stored on the node's local disk (or in memory if you set `medium: Memory`)

It's perfect for sharing files between containers in the same pod (like the Docker socket or tool binaries).

---

### 3.5 `service.yaml` — Exposing Jenkins to the Internet

```yaml
apiVersion: v1
kind: Service
metadata:
  name: jenkins-service
  namespace: jenkins
spec:
  type: LoadBalancer
  selector:
    app: jenkins
  ports:
    - port: 8080
      targetPort: 8080
      name: http
    - port: 50000
      targetPort: 50000
      name: jnlp
```

#### What is a Service?

A pod has an internal IP address (like `10.0.10.114`), but:
1. Pods are **temporary** — when a pod restarts, it gets a new IP
2. Pod IPs are **internal** — you can't reach them from your browser

A **Service** solves both problems:
- **Stable address** — the Service has a fixed name (`jenkins-service`) that doesn't change
- **External access** — with `type: LoadBalancer`, AWS creates a real load balancer with a public URL

#### Line-by-line:

| Line | What it does |
|---|---|
| `type: LoadBalancer` | Tells AWS: "Create an Elastic Load Balancer (ELB) and give it a public DNS name" |
| `selector: app: jenkins` | "Send traffic to any pod with the label `app=jenkins`" |
| `port: 8080` | The port the Service listens on (the external port) |
| `targetPort: 8080` | The port on the pod to send traffic to (Jenkins listens on 8080) |
| `name: http` | A friendly name for this port mapping |

#### How the Service routes traffic:

```
Your browser                       Kubernetes Service              Jenkins Pod
  │                                       │                           │
  │  http://jenkins-service:8080          │                           │
  │ ─────────────────────────────────────>│                           │
  │                            │                                      │
  │                     Find pod with                                 │
  │                     label app=jenkins                             │
  │                            │                                      │
  │                            └──>  Forward to port 8080 ──────────> │
  │                                                                   │
  │ <─────────────────────────────────────────────────────────────────│
  │                        Jenkins UI response                        │
```

#### What actually happens with `type: LoadBalancer`:

1. Kubernetes sees a Service with `type: LoadBalancer`
2. It talks to AWS and says: "Please create a Load Balancer"
3. AWS creates an **ELB** (Elastic Load Balancer) — a managed, highly-available traffic router
4. The ELB gets a public DNS name like: `ac451a57a90144...us-east-1.elb.amazonaws.com`
5. AWS configures the ELB to forward traffic from port 8080 to any node in the cluster
6. On each node, a special service (`kube-proxy`) routes the traffic to the actual Jenkins pod

This is why you can access Jenkins from your browser — even though Jenkins runs on a private EC2 node with no public IP.

#### The two ports:

| Port | Purpose |
|---|---|
| `8080` (http) | Jenkins web UI — you access this in your browser |
| `50000` (jnlp) | Jenkins agent connection — used when you want to add build agents/slaves to Jenkins. Not needed for our basic setup |

---

## 4. How everything connects

### The complete data flow for a Jenkins deployment:

```
User runs: kubectl apply -f k8s/jenkins/
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                            │
│                                                                   │
│  ┌────────────────── jenkins namespace ─────────────────────────┐ │
│  │                                                              │ │
│  │  ┌──────────────────┐  ┌────────────────┐  ┌──────────────┐  │ │
│  │  │  ServiceAccount  │  │       PVC      │  │   Service    │  │ │
│  │  │   jenkins-sa     │  │  jenkins-home  │  │  LoadBalancer│  │ │
│  │  └────────┬─────────┘  └───────┬────────┘  └──────┬───────┘  │ │
│  │           │                    │                  │          │ │
│  │           └────────────┬───────┘──────────────────┘          │ │
│  │                        ▼                                     │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                     Jenkins Pod                         │ │ │
│  │  │                                                         │ │ │
│  │  │  ┌──── initContainers ───────────────────────────────┐  │ │ │
│  │  │  │  1. install-kubectl ────> /tools/kubectl          │  │ │ │
│  │  │  │  2. install-docker-cli ─> /tools/docker           │  │ │ │
│  │  │  │  3. fix-permissions ────> chown /var/jenkins_home │  │ │ │
│  │  │  └───────────────────────────────────────────────────┘  │ │ │
│  │  │                                                         │ │ │
│  │  │  ┌────────── containers ───────────────────────────┐    │ │ │
│  │  │  │                                                 │    │ │ │
│  │  │  │  ┌────────────────────┐  ┌────────────────────┐ │    │ │ │
│  │  │  │  │   Jenkins Master   │  │  Docker dind       │ │    │ │ │
│  │  │  │  │   (port 8080)      │  │  (port 2375)       │ │    │ │ │
│  │  │  │  │                    │  │                    │ │    │ │ │
│  │  │  │  │  Runs pipeline     │  │  Builds images     │ │    │ │ │
│  │  │  │  │  kubectl apply     │  │  docker:dind image │ │    │ │ │
│  │  │  │  │  docker build      │  │                    │ │    │ │ │
│  │  │  │  └────────┬───────────┘  └─────────┬──────────┘ │    │ │ │
│  │  │  │           │                        │            │    │ │ │
│  │  │  │           └──── localhost:2375 ────┘            │    │ │ │
│  │  │  └─────────────────────────────────────────────────┘    │ │ │
│  │  │                                                         │ │ │
│  │  │  Volumes:                                               │ │ │
│  │  │    /var/jenkins_home ──> PVC ──> /data/jenkins-home     │ │ │
│  │  │    /var/run          ──> emptyDir (docker socket)       │ │ │
│  │  │    /var/lib/docker   ──> emptyDir (images)              │ │ │
│  │  │    /tools             ──> emptyDir (kubectl + docker)   │ │ │
│  │  │                                                         │ │ │
|  |  └─────────────────────────────────────────────────────────┘ | |
│  └──────────────────────────────────────────────────────────────┘ │                    
│                                                                   │
│  Nodes (cluster-wide — not inside any namespace):                 │
│    ┌─────────────────────────────────────┐                        │
│    │ Node 1: ip-10-0-10-35.ec2.internal  │                        │
│    │         role=tools                  │                        │
│    │         Runs: Jenkins Pod           │                        │
│    └─────────────────────────────────────┘                        │
│    ┌─────────────────────────────────────┐                        │
│    │ Node 2: ip-10-0-20-138.ec2.internal │                        │
│    │         role=production             │                        │
│    │         Runs: App pods (Phase 5)    │                        │
│    └─────────────────────────────────────┘                        │
│                                                                   │
│  AWS Resources (behind the scenes):                               │
│    LoadBalancer ──> Routes traffic to Jenkins pod on port 8080    │
│    EBS Volume    ──> Backs the hostPath at /data/jenkins-home     │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### The decision chain — why each component exists:

| Question | Answer | Implemented by |
|---|---|---|
| How do we organize Jenkins stuff? | A namespace | `namespace.yaml` |
| How does Jenkins get permissions? | A ServiceAccount with a ClusterRole | `rbac.yaml` |
| Where does Jenkins store data? | A PersistentVolume + Claim | `pvc.yaml` |
| How do we run Jenkins? | A Deployment with containers | `deployment.yaml` |
| How does Jenkins build Docker images? | A dind sidecar container | `deployment.yaml` |
| How do we ensure Jenkins runs on the tools node? | `nodeSelector: role=tools` | `deployment.yaml` |
| How does Jenkins get kubectl? | Init container copies the binary | `deployment.yaml` |
| How do we access Jenkins from our browser? | A LoadBalancer Service | `service.yaml` |

---

## 5. How to interact with Phase 2 resources

### Useful commands:

| Command | What it does |
|---|---|
| `kubectl get namespaces` | List all namespaces (including `jenkins`) |
| `kubectl get all -n jenkins` | Show all resources in the jenkins namespace |
| `kubectl get pods -n jenkins -o wide` | Show pods with node IP and assigned node |
| `kubectl logs -n jenkins <pod-name> -c jenkins` | See Jenkins startup logs |
| `kubectl logs -n jenkins <pod-name> -c dind` | See Docker daemon logs |
| `kubectl exec -n jenkins <pod-name> -c jenkins -- kubectl get nodes` | Run kubectl from INSIDE the Jenkins container |
| `kubectl describe pod -n jenkins <pod-name>` | Detailed pod info (events, conditions, etc.) |
| `kubectl get svc -n jenkins` | Get the LoadBalancer URL for Jenkins |
| `kubectl delete -f k8s/jenkins/` | Delete all Jenkins resources |
| `kubectl apply -f k8s/jenkins/` | Create/update all Jenkins resources |

### Accessing Jenkins:

1. Get the URL: `kubectl get svc -n jenkins`
2. Look for the `EXTERNAL-IP` column — it shows a long AWS domain name
3. Open `http://<EXTERNAL-IP>:8080` in your browser
4. Since we used `-Djenkins.install.runSetupWizard=false`, Jenkins starts without asking for credentials

### Troubleshooting:

| Problem | Likely cause | Fix |
|---|---|---|
| Pod stuck in `Pending` | Node doesn't match `nodeSelector` | Check node labels: `kubectl get nodes --show-labels \| findstr role` |
| Pod stuck in `Pending` (PVC) | PVC not bound | Check PVC: `kubectl get pvc -n jenkins` |
| Jenkins can't write to `/var/jenkins_home` | Permission issue | Check init container logs: `kubectl logs -n jenkins <pod-name> -c fix-permissions` |
| `docker: not found` | Docker CLI not installed | Check init container: `kubectl logs -n jenkins <pod-name> -c install-docker-cli` |
| Can't connect to Jenkins (browser timeout) | Security group rules | AWS ELB security group may need to allow inbound on port 8080. Wait 2-3 minutes for the ELB to provision |
| Pod crashes with `CrashLoopBackOff` | Container exits immediately | Check logs: `kubectl logs -n jenkins <pod-name> --all-containers` |

---

## Summary of Phase 2 Learning Objectives

After studying this file, you should be able to answer:

1. **What is a Kubernetes Namespace and why use it?** (Organization and isolation)
2. **What is RBAC and what are its three components?** (ServiceAccount, ClusterRole, ClusterRoleBinding)
3. **What is the difference between a PV and a PVC?** (PV = the actual storage, PVC = a request for storage)
4. **What is a hostPath volume and what is its limitation?** (Uses node's disk; data lost if node dies)
5. **What does `nodeSelector` do?** (Pins a pod to nodes with specific labels)
6. **Why do we need a Docker-in-Docker sidecar?** (EKS uses containerd, not Docker — dind provides a self-contained Docker daemon)
7. **What is an init container?** (A container that runs before main containers to prepare files or fix permissions)
8. **What does `subPath` do in a volume mount?** (Mounts a single file from a volume instead of the whole volume)
9. **What is the difference between a Deployment and a Service?** (Deployment manages pods; Service provides stable networking)
10. **What does `type: LoadBalancer` do?** (Creates a real AWS ELB with a public DNS name)
11. **Why did the Jenkins pod initially crash?** (hostPath directory was owned by root, but Jenkins runs as UID 1000)
12. **How does Jenkins get permission to run kubectl?** (ServiceAccount `jenkins-sa` is attached to the pod, and RBAC binds it to a ClusterRole with full permissions)

---

**Next phase:** Phase 3 — Dockerfiles for Frontend (Angular) and Backend (.NET 8) with multi-stage builds
