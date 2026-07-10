# Phase 6 — Monitoring with Prometheus & Grafana

> **Target Audience:** Junior DevOps Team (assumes basic Kubernetes knowledge from Phases 1-5, but NO Prometheus, Grafana, or Helm experience)
>
> **Goal:** Monitor the production node's CPU, memory, and pod count using Prometheus and Grafana, all running on the tools node via Helm.

---

## Table of Contents

1. [What is Prometheus, Grafana, and Helm?](#1-what-is-prometheus-grafana-and-helm)
2. [Our Monitoring Architecture](#2-our-monitoring-architecture)
3. [Step 1: Install Helm CLI](#3-step-1-install-helm-cli)
4. [Step 2: Create the monitoring custom values file](#4-step-2-create-the-monitoring-custom-values-file)
5. [Step 3: Add the Prometheus Helm repository](#5-step-3-add-the-prometheus-helm-repository)
6. [Step 4: Install the monitoring stack](#6-step-4-install-the-monitoring-stack)
7. [Step 5: Access Grafana](#7-step-5-access-grafana)
8. [Step 6: View production node metrics](#8-step-6-view-production-node-metrics)
9. [Understanding what you see](#9-understanding-what-you-see)
10. [Destroying the monitoring stack](#10-destroying-the-monitoring-stack)

---

## 1. What is Prometheus, Grafana, and Helm?

### Prometheus

An **open-source monitoring and alerting toolkit**. It scrapes (pulls) metrics from your applications and infrastructure at regular intervals and stores them in a time-series database. Think of it as a **central data collector** — it asks every service "What's your CPU usage? Memory? How many pods are running?" and stores the answers.

### Grafana

A **visualization dashboard** that connects to Prometheus (and other data sources). It creates charts, graphs, and tables so you can see your metrics in a human-readable way instead of raw numbers. Think of it as the **frontend UI** for Prometheus data.

### Helm

A **package manager for Kubernetes**, like `npm` for Node or `apt` for Ubuntu. It bundles complex applications (like Prometheus + Grafana) into reusable packages called **charts**. Instead of writing 20+ YAML files manually, you run:

```powershell
helm install prometheus-stack prometheus-community/kube-prometheus-stack
```

And Helm creates all the deployments, services, configs, and dashboards in one command.

### The components we install

| Component | What it does | Runs on |
|---|---|---|
| **Prometheus** | Collects and stores metrics from the cluster | tools node |
| **Grafana** | Web UI to visualize metrics in dashboards | tools node |
| **node-exporter** | Exposes node-level metrics (CPU, memory, disk per node) | **Every node** (DaemonSet) |
| **kube-state-metrics** | Exposes Kubernetes object metrics (pods, deployments, namespaces) | tools node |

---

## 2. Our Monitoring Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              EKS Cluster                                    │
│                                                                             │
│  Tools Node (role=tools)                      Production Node (role=production)│
│  ┌────────────────────────────────┐          ┌────────────────────────────┐ │
│  │  Jenkins (2/2)                 │          │  Frontend Pod              │ │
│  │  ┌──────────────┐ ┌─────────┐ │          │  Backend Pod (×2)           │ │
│  │  │  Jenkins      │ │ Docker  │ │          │  ┌────────────────────┐   │ │
│  │  │  (8080)       │ │ dind    │ │          │  │ node-exporter      │   │ │
│  │  └──────────────┘ └─────────┘ │          │  │ (CPU, memory data) │   │ │
│  │  ┌────────────────────────┐   │          │  └────────────────────┘   │ │
│  │  │  Prometheus             │────scrapes──┼──► exposed metrics        │ │
│  │  │  Grafana                │   │          │                           │ │
│  │  │  kube-state-metrics     │   │          └───────────────────────────┘ │
│  │  │  node-exporter          │   │                                        │
│  │  └────────────────────────┘   │                                        │
│  └────────────────────────────────┘                                        │
└────────────────────────────────────────────────────────────────────────────┘
```

**Key insight:** Prometheus runs on the **tools** node but scrapes metrics from the **production** node. The `node-exporter` DaemonSet runs on **every node**, so the production node's CPU/memory data is captured regardless of where Prometheus itself lives. This gives your app maximum resources while still getting full visibility.

### Why not put Prometheus on the production node?

| Resource | Current app usage (limits) | Monitoring usage (limits) | `t3.small` max |
|---|---|---|---|
| RAM | 1GB (app) | ~768MB (Prometheus + Grafana) | 2GB |
| CPU | 500m (app) | ~750m (Prometheus + Grafana) | 1 vCPU |

On the **tools** node, Jenkins + Prometheus + Grafana share 2GB — comfortable.
On the **production** node, the app has the full 2GB with zero contention — **safer for traffic spikes**.

---

## 3. Step 1: Install Helm CLI

Helm is needed to install the monitoring stack. This is a **one-time** installation on your local machine.

### Check if Helm is already installed:

```powershell
helm version
```

**Expected output:** `version.BuildInfo{Version: "v4.x.x" ...}`

### If not installed, using winget (Windows):

```powershell
winget install Helm.Helm
```

Then refresh your PATH in the current terminal:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

### Verify:

```powershell
helm version --short
```

**Expected:** `v4.2.3+g43e8b7f` (or similar)

---

## 4. Step 2: Create the monitoring custom values file

Helm charts have default settings, but we need to customize:

1. Pin Prometheus and Grafana to the **tools** node (via `nodeSelector: role: tools`)
2. Limit their CPU/RAM so they fit on a `t3.small`
3. Expose Grafana via LoadBalancer so we can access it

The file is `k8s/monitoring/values.yaml`:

```yaml
# ─────────────────────────────────────────────
# Custom values for kube-prometheus-stack
# ─────────────────────────────────────────────

# Pin Prometheus to the tools node
prometheus:
  prometheusSpec:
    nodeSelector:
      role: tools
    resources:
      requests:
        memory: "256Mi"
        cpu: "200m"
      limits:
        memory: "512Mi"
        cpu: "500m"

# Pin Grafana to the tools node, set admin password, expose via LoadBalancer
grafana:
  nodeSelector:
    role: tools
  adminPassword: "admin"
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "250m"
  service:
    type: LoadBalancer

# node-exporter runs on EVERY node (DaemonSet) — no changes needed
# kube-state-metrics runs on tools node by default — no changes needed
```

**What each section does:**

| Section | Purpose |
|---|---|
| `prometheus.prometheusSpec.nodeSelector` | Tells Prometheus to only run on nodes with `role=tools` |
| `prometheus.prometheusSpec.resources` | Limits Prometheus CPU/Memory so it doesn't starve Jenkins on the tools node |
| `grafana.nodeSelector` | Tells Grafana to only run on nodes with `role=tools` |
| `grafana.adminPassword` | Sets the Grafana admin password to `admin` (change after first login!) |
| `grafana.service.type: LoadBalancer` | Gives Grafana its own LoadBalancer URL so we can access it from a browser |

---

## 5. Step 3: Add the Prometheus Helm repository

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### What this does

| Command | Purpose |
|---|---|
| `helm repo add` | Adds the Prometheus community chart repository as a source — like adding an app store to your phone |
| `helm repo update` | Downloads the latest list of available charts from that repository |

You only need to do this **once** per machine.

**Expected output:**
```
"prometheus-community" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "prometheus-community" chart repository
```

---

## 6. Step 4: Install the monitoring stack

```powershell
# Create the monitoring namespace
kubectl create namespace monitoring

# Install Prometheus + Grafana + node-exporter + kube-state-metrics
helm install prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  -f k8s/monitoring/values.yaml
```

### What this command does

| Part | What it does |
|---|---|
| `helm install prometheus-stack` | Installs the chart with the release name `prometheus-stack` |
| `prometheus-community/kube-prometheus-stack` | The chart name — includes Prometheus, Grafana, node-exporter, and kube-state-metrics |
| `--namespace monitoring` | Creates all resources in the `monitoring` namespace |
| `-f k8s/monitoring/values.yaml` | Applies our customizations (tools node, resource limits, LoadBalancer) |

**Expected output:**
```
NAME: prometheus-stack
LAST DEPLOYED: ...
NAMESPACE: monitoring
STATUS: deployed
...
```

### What gets created in your cluster

```powershell
kubectl get all -n monitoring
```

You'll see:
- `pod/prometheus-stack-kube-prom-prometheus-xxxxx` — Prometheus
- `pod/prometheus-stack-grafana-xxxxx` — Grafana
- `pod/prometheus-stack-kube-state-metrics-xxxxx` — kube-state-metrics
- `daemonset/prometheus-stack-prometheus-node-exporter` — runs on **every node**
- `service/prometheus-stack-grafana` — **LoadBalancer** (public URL)

---

## 7. Step 5: Access Grafana

```powershell
kubectl get svc -n monitoring prometheus-stack-grafana
```

Look for the `EXTERNAL-IP` column. Example output:

```
NAME                            TYPE           EXTERNAL-IP
prometheus-stack-grafana       LoadBalancer    a5b2c3d4e5f6-123456789.us-east-1.elb.amazonaws.com
```

**Open in your browser:** `http://<EXTERNAL-IP>:80`

**Login credentials:**

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `admin` |

---

## 8. Step 6: View production node metrics

The `kube-prometheus-stack` comes with **pre-built dashboards** that show node and pod metrics as percentages automatically — no manual PromQL needed.

### Finding the Dashboards list

1. In Grafana, look at the **left sidebar** — a vertical strip of icons
2. Hover over the **four-squares icon** ( tooltip says "Dashboards" )
3. Click **"Dashboards"** from the popup menu that appears
4. You'll see a search bar with a list of all available dashboards underneath

> **Tip:** If you don't see the left sidebar, click the **top-left hamburger menu** (three horizontal lines) to expand it.

---

### Dashboard 1: Kubernetes / Compute Resources / Node (Pods) — **RECOMMENDED**

This dashboard shows CPU and memory as **% of node capacity** for every pod on a specific node. The y-axis is already percentage — no math needed.

#### Exact click path:
1. In the **Dashboards** search bar (top of the list), type: **`Compute Resources`**
2. From the results, click: **`Kubernetes / Compute Resources / Node (Pods)`**
3. At the top of the dashboard, find the **`Node`** dropdown field
4. Click it and select: **`ip-10-0-20-140.ec2.internal`** (the production node)

#### What you'll see on this dashboard:

| Panel | What it shows | Looks like |
|---|---|---|
| **CPU Usage** | Bar chart — each pod's CPU as a % of total node capacity | Blue bars with a horizontal red line at 100%. Frontend and backend bars should be short (~5-15%) |
| **Memory Usage** | Bar chart — each pod's memory as a % of total node RAM | Green bars with max line. Hover over a bar to see the exact MiB value |
| **Network Bandwidth** | Line chart — bytes received/transmitted over time | Colored area lines. Low and steady is normal |
| **Disk I/O** | Line chart — disk reads/writes | Flat/low during idle |

#### How to read the CPU Usage bar chart:
- Each **bar** = one pod on the production node
- The **Y-axis** = **percentage of total node CPU** (0% to 100%+)
- The **red dashed line** at the top = 100% capacity
- Example: If frontend shows 12%, that pod is using 12% of one CPU core (not 12% of its own limit)
- **Healthy:** All bars well below 80% and no bar close to the red line

#### How to read the Memory Usage bar chart:
- Same layout — each bar = one pod, Y-axis = % of total node RAM
- **Healthy:** Bars below 80%, total of all bars under the max line

---

### Dashboard 2: Kubernetes / Compute Resources / Namespace (Pods)

This dashboard organizes pods by namespace. Use it to see **all production pods** together as a group.

#### Exact click path:
1. In the **Dashboards** search bar, type: **`Compute Resources`**
2. Click: **`Kubernetes / Compute Resources / Namespace (Pods)`**
3. At the top, find the **`Namespace`** dropdown and select: **`production`**

#### What you'll see:
- Same bar chart format as Dashboard 1, but filtered to the production namespace
- Shows only your frontend and backend pods
- The `Node` dropdown here lets you filter to the production node specifically

---

### Dashboard 3: Kubernetes / Compute Resources / Pod

This dashboard shows **one pod at a time** with detailed metrics.

#### Exact click path:
1. Search for **`Compute Resources`** and click **`Kubernetes / Compute Resources / Pod`**
2. Set `Namespace` = `production`
3. Set `Pod` = pick a specific pod (e.g., `frontend-deployment-xxxxx`)

#### What you'll see:
- **CPU Usage:** Line chart showing CPU over time (as a % of pod request/limit)
- **Memory Usage:** Line chart showing memory over time (as a % of pod limit)
- **Network:** Bytes in/out per second
- **Use this when:** You want to investigate one pod that's acting strangely

---

### Dashboard 4: Node Exporter / Nodes (advanced)

If you want **raw node-level** metrics (load average, disk space, network interfaces):

1. Search for **"Node Exporter"** in the Dashboards list
2. Click **"Node Exporter / Nodes"**
3. Set the `node` dropdown to `ip-10-0-20-140.ec2.internal`

**Use this for:** Deeper investigation — e.g., disk space running low, high load average, or network errors.

---

### Summary: Which dashboard when?

| Goal | Dashboard |
|---|---|
| "Quick check — is my production node overloaded?" | **Compute Resources / Node (Pods)** |
| "Are all 4 pods running and healthy?" | **Compute Resources / Node (Pods)** — count the bars |
| "Is a specific pod using too much memory?" | **Compute Resources / Pod** |
| "What's the node's disk space or load average?" | **Node Exporter / Nodes** |
| "Check resources for the whole production namespace" | **Compute Resources / Namespace (Pods)** |

---

## 9. Understanding what you see

### Key metrics explained

| Metric | What it tells you | Healthy range |
|---|---|---|
| **CPU Usage %** | How much of the node's CPU is being used | < 80% |
| **Memory Usage %** | How much of the node's RAM is being used | < 80% |
| **Pod Count** | Number of running pods on the node | Should be 4 (2 frontend + 2 backend) - no pods scheduled on the production node except yours |
| **Restarts** | How many times pods have restarted | Should be 0 if stable |

### The tools node vs production node

In Grafana dashboards, the `Node` dropdown lets you switch which node to inspect:
- `ip-10-0-10-192.ec2.internal` — **tools node** (Jenkins + Prometheus + Grafana + kube-state-metrics + node-exporter)
- `ip-10-0-20-140.ec2.internal` — **production node** (Frontend + Backend + node-exporter)

Use the `Node` dropdown to check metrics on **either** node. The **production node** is the one that matters for your app's health.

---

## 10. Destroying the monitoring stack

### Uninstall (removes all monitoring resources)

```powershell
helm uninstall prometheus-stack --namespace monitoring
kubectl delete namespace monitoring
```

### AWS clean up

The Grafana LoadBalancer is automatically deleted when you delete the namespace. No orphaned resources remain.

### What this affects

| Resource | Gone? |
|---|---|
| Prometheus pod | ✅ |
| Grafana pod + LoadBalancer | ✅ |
| node-exporter (on every node) | ✅ |
| kube-state-metrics | ✅ |
| All metrics data | ✅ (Prometheus storage is ephemeral) |
| Jenkins / Application pods | ❌ **Not affected** |

---

## Phase 6 Checklist

| Step | Done? |
|---|---|
| [ ] Install Helm CLI (`winget install Helm.Helm`) | ☐ |
| [ ] Create `k8s/monitoring/values.yaml` with custom settings | ☐ |
| [ ] `helm repo add prometheus-community ...` | ☐ |
| [ ] `helm repo update` | ☐ |
| [ ] `kubectl create namespace monitoring` | ☐ |
| [ ] `helm install prometheus-stack ... -f k8s/monitoring/values.yaml` | ☐ |
| [ ] Verify pods are running: `kubectl get pods -n monitoring -w` | ☐ |
| [ ] Get Grafana URL: `kubectl get svc -n monitoring prometheus-stack-grafana` | ☐ |
| [ ] Login to Grafana (`admin` / `admin`) | ☐ |
| [ ] Open "Kubernetes / Compute Resources / Node (Pods)" dashboard | ☐ |
| [ ] In the `Node` dropdown, select the production node (`ip-10-0-20-140`) | ☐ |
| [ ] Verify CPU bar chart shows each pod as % of node capacity | ☐ |
| [ ] Verify Memory bar chart shows each pod as % of node RAM | ☐ |
| [ ] Open "Kubernetes / Compute Resources / Namespace (Pods)" and filter by `production` | ☐ |

---

## Common Issues

### Issue 1: Helm not found after installing

```powershell
# Refresh PATH in current terminal
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

### Issue 2: Grafana LoadBalancer pending (stays `<pending>`)

The LoadBalancer takes 1-2 minutes to provision. If it stays pending longer:

```powershell
kubectl describe svc -n monitoring prometheus-stack-grafana
```

Check for events indicating a quota or subnet issue.

### Issue 3: Dashboard shows no data

Ensure the production node label is correct in the Grafana filter dropdown:
- Node name should match `kubectl get nodes` output (e.g., `ip-10-0-20-140.ec2.internal`)
- The `node-exporter` DaemonSet must be running on that node: `kubectl get pods -n monitoring -o wide | findstr node-exporter`

### Issue 4: Prometheus or Grafana pod stuck in Pending

```powershell
kubectl describe pod -n monitoring <pod-name>
```

Check the `Events` section. Likely causes:
- No node with `role=tools` label (run `kubectl label node ... role=tools`)
- Insufficient resources on the tools node

---

**Related files:** [`values.yaml`](k8s/monitoring/values.yaml) | [`LIFECYCLE_GUIDE.md`](../LIFECYCLE_GUIDE.md)
