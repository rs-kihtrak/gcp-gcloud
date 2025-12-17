# 🔐 GKE Workload Identity Binder

Automates **GKE Workload Identity** setup by safely linking a Kubernetes ServiceAccount (KSA) with a Google IAM Service Account (GSA).

Designed for **production use** with:
- Pre-checks
- Dry planning
- Optional execution
- Script generation for auditability

---

## ✨ What this solves

Setting up Workload Identity manually is error-prone:
- Missing namespaces
- KSA/GSA not created
- IAM binding forgotten
- Annotation mismatch

This script **detects, plans, and applies** everything correctly.

---

## 🧠 What the script does

### 🔍 Checks (no changes)
- Project exists
- Namespace exists
- GCP Service Account (GSA)
- Kubernetes Service Account (KSA)
- IAM `roles/iam.workloadIdentityUser` binding
- KSA annotation (`iam.gke.io/gcp-service-account`)

### 🧩 Builds Actions
- Only missing steps are added to **minimal actions**
- Full-force mode rebuilds **everything explicitly**

---

## 🚀 Usage

### Option 1️⃣  Pass values directly
```bash
./gke-workload-identity-bind.sh "PROJECT,NAMESPACE,KSA,GSA"
```

### Option 2️⃣ — Interactive prompts
```bash
./gke-workload-identity-bind.sh
```

---
###./If KSA is omitted, it defaults to the GSA name.

## 🧭 Execution options

### After validation, you choose:

🚀 Proceed? (y=execute | n=create script | f=full-force script)

Option	Behavior
y	Execute only missing actions
n	Generate script with minimal required actions
f	Generate script with all actions (force mode)
