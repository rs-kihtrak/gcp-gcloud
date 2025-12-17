# ☁️ GCP & gcloud Utilities  
A collection of practical scripts and tools for automating tasks across Google Cloud Platform (GCP):  
GKE, Compute Engine, Storage, IAM, Networking, and more.

---

## 📑 Table of Contents

### 🧩 gke-tools
- [`gke-node-pool-clone`](gke-tools/gke-node-pool-clone/) – Clone or recreate a GKE Node Pool by parsing configuration from the GCP Console URL.
- [`gke-node-pool-update`](gke-tools/gke-node-pool-update/) –   Update GKE Node Pool Spec by parsing configuration from the GCP Console URL.
- [`gke-workload-identity-bind`](gke-tools/gke-workload-identity-bind/) – Safely configure GKE Workload Identity between Kubernetes and Google Cloud IAM.
---

## 🧩 gke-tools

### ▶️ `gke-node-pool-clone`
A script that:
- Parses a GKE Console node pool URL  
- Fetches the full configuration using `gcloud`  
- Extracts machine type, disk, taints, labels, autoscaling, pod ranges, upgrade settings, metadata  
- Generates a ready-to-run **node pool recreation script**  
- Supports macOS Bash & Linux  
- Ideal for nodepool migration, upgrade, or rotation

### ▶️ `gke-node-pool-update`
- Parses a GKE Console node pool URL
- Auto-parses project / region / cluster / nodepool
- Shows before → after diff
- Generates a ready-to-run **node pool Update Script***
- Always generates reusable script

### ▶️ `gke-workload-identity-bind`
- 🔗 Accepts inputs via **prompt or single argument** (`PROJECT,NAMESPACE,KSA,GSA`)
- 🧭 Validates existence of **Namespace, KSA, and GSA**
- 🔍 Detects missing pieces:
- 🧾 Builds an **action plan** before making changes
- 🛠️ Supports three modes:
  - Execute only missing actions
  - Generate minimal script
  - Generate full-force script (idempotent)

