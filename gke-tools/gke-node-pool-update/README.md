# 🔧 GKE Node Pool Spec Updater (URL Based)

Update an existing GKE node pool Spec **safely** using only the **GKE Console URL**.

---

## ✨ Features

- Accepts GKE Console URL
- Auto-parses project / region / cluster / nodepool
- Shows before → after diff
- Confirmation before execution
- Always generates reusable script

---

## 🚀 Usage

```bash
./gke-node-pool-update.sh "<GKE_NODEPOOL_CONSOLE_URL>"

```

```
Example: ./gke-node-pool-update.sh  "https://console.cloud.google.com/kubernetes/nodepool/<region>/<cluster>/<nodepool>?project=<project>"
```
