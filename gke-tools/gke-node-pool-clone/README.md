## 📑 Table of Contents
1. [Overview](#overview)
2. [Highlights](#Highlights)
3. [Requirements](#requirements)
4. [Usage](#usage)
5. [Generated Output](#generated-output)

---

## 🔍 Overview
This repository contains compact, powerful scripts for **GKE Node Pool clone automation**.  
The tool, **gke-node-pool-clone.sh**, extracts configuration from an existing GKE node pool and generates a ready-to-run script to recreate or migrate it.

---

## ✨ Highlights
- 🔗 Parses GKE Console URL  
- 📥 Fetches full nodepool config (machine, disk, taints, labels, metadata, autoscaling, upgrade settings)  
- 🧹 Removes auto-generated labels (`goog-gke-*`)  
- 🛠 Normalizes taints (`NO_SCHEDULE → NoSchedule`)  
- 🎯 Uses **cluster version** for safer node-version assignment  
- 🧾 Generates a clean `gcloud node-pools create` script (macOS-safe)  
- ▶️ Optional execution of the generated script  

---

## 🧰 Requirements
- `gcloud` CLI  
- `jq`  
- IAM permissions for GKE cluster & node pools  

---

## 🚀 Usage
Run the clone tool using a GKE Console nodepool URL:

```bash
./gke-node-pool-clone.sh "https://console.cloud.google.com/kubernetes/nodepool/<region>/<cluster>/<nodepool>?project=<project>"
```

## You will be prompted to enter a new nodepool name.  
A script will be generated:
then it will ask if you want to run the cmd. if you give yes it will run the nodepool creation cmd. if you give no it will exit pinting the script file name.

## Run it after changing desired entries:

```bash
bash create-<new-nodepool>.sh
```

## Generated Output (Example) of script
```
gcloud container node-pools create "new-nodepool" \
  --project "prod" \
  --cluster "prod-gke" \
  --location "asia-south1" \
  --machine-type "n2d-standard-8" \
  --disk-size "50" \
  --image-type "COS_CONTAINERD" \
  --node-version "1.30.9-gke.1009000" \
  --node-taints "service=content:NoSchedule" \
  --labels "team=content,service=content-k8s" \
  --pod-ipv4-range "pod-prod" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade "1" \
  --max-unavailable-upgrade "0"
```
