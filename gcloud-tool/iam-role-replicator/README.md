# GCP IAM Role Replicator

A bash utility to replicate IAM roles from one principal to another principal or project in Google Cloud Platform.

## 📋 Overview

This tool simplifies IAM role management by allowing you to:
- Copy all IAM roles from one user/group/service account to another
- Replicate IAM roles across different GCP projects
- Preview changes with dry-run mode before applying
- Save commands to a script for review and later execution

## ✨ Features

- **Flexible Replication**: Copy roles to different principals or projects
- **Dry-Run Mode**: Preview changes without making actual modifications
- **Save to Script**: Generate executable scripts for review and audit trails
- **Interactive**: User-friendly prompts guide you through the process
- **Safe & Idempotent**: Safe to re-run multiple times
- **Multiple Principal Types**: Supports users, groups, and service accounts

## 🚀 Quick Start

### Prerequisites

- `gcloud` CLI installed and configured
- Authenticated with appropriate GCP permissions
- Access to source and target projects

### Required Permissions

**On Source Project:**
- `roles/viewer` (to read IAM policies)

**On Target Project:**
- `roles/resourcemanager.projectIamAdmin` (to modify IAM policies)


# Make the script executable
chmod +x iam-role-replicator.sh
```

## 📖 Usage

### Basic Syntax

```bash
./iam-role-replicator.sh [OPTIONS] <SOURCE_PROJECT> <SOURCE_PRINCIPAL>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `SOURCE_PROJECT` | GCP project ID where roles are read from |
| `SOURCE_PRINCIPAL` | IAM principal whose roles will be replicated |

### Principal Formats

- `user:email@example.com`
- `group:team@example.com`
- `serviceAccount:sa@project.iam.gserviceaccount.com`

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview changes without executing them |
| `--help` | Show help message and exit |

## 💡 Examples

### Example 1: Replicate User Roles to Another User (Same Project)

```bash
./iam-role-replicator.sh my-project user:john@example.com

# Interactive prompts:
# Choose: 1 (another principal, same project)
# Enter target: user:jane@example.com
# Choose: 1 (run now)
```

### Example 2: Replicate Service Account Roles to Another Project

```bash
./iam-role-replicator.sh prod-project serviceAccount:app@prod.iam.gserviceaccount.com

# Interactive prompts:
# Choose: 2 (same principal, another project)
# Enter target project: staging-project
# Choose: 1 (run now)
```

### Example 3: Dry Run to Preview Changes

```bash
./iam-role-replicator.sh --dry-run my-project group:devops@example.com

# Interactive prompts:
# Choose: 1 (another principal, same project)
# Enter target: group:sre@example.com
# Choose: 1 (run now)
```

### Example 4: Save Commands to Script for Review

```bash
./iam-role-replicator.sh my-project user:admin@example.com

# Interactive prompts:
# Choose: 1 (another principal, same project)
# Enter target: user:backup-admin@example.com
# Choose: 2 (save to script)

# Output: Commands saved to: apply-iam-20250122-143045.sh
# Review and execute:
./apply-iam-20250122-143045.sh
```

## 🔄 Workflow

1. **Fetch Roles**: Script reads all IAM roles assigned to source principal
2. **Choose Mode**: Select replication mode (different principal or different project)
3. **Choose Execution**: Run immediately or save to script
4. **Apply Changes**: Roles are replicated to target

## 📝 Sample Output

```bash
$ ./iam-role-replicator.sh my-project user:john@example.com

🔍 Fetching IAM roles
   Project   : my-project
   Principal : user:john@example.com

✅ Roles found:
roles/compute.admin
roles/storage.admin
roles/viewer

Choose replication option:
1) Replicate to another principal (same project)
2) Replicate to same principal (another project)
Enter choice [1/2]: 1
Enter TARGET principal (user:/group:/serviceAccount:): user:jane@example.com

Choose execution mode:
1) Run commands now
2) Save commands to script and exit
Enter choice [1/2]: 1

🚀 Processing roles...

▶ Applying roles/compute.admin
▶ Applying roles/storage.admin
▶ Applying roles/viewer

✅ IAM role replication completed successfully
```

## ⚠️ Important Notes

- **Project-level IAM only**: This tool operates on project-level IAM bindings
- **Conditional bindings NOT supported**: Conditional IAM bindings are not replicated
- **Idempotent**: Safe to run multiple times; existing bindings won't be duplicated
- **No role removal**: This tool only adds roles, it does not remove existing ones

## 🛡️ Security Considerations

1. **Review before applying**: Use `--dry-run` or save-to-script mode for critical changes
2. **Least privilege**: Only grant necessary permissions to the script executor
3. **Audit trail**: Save commands to scripts for compliance and audit purposes
4. **Test first**: Test in non-production environments before production use

## 🐛 Troubleshooting

### "No roles found" Error

```bash
❌ No roles found
```

**Solution**: Verify that:
- Source project ID is correct
- Principal format is correct (user:/group:/serviceAccount:)
- Principal has at least one role assigned
- You have permission to view IAM policies

### Permission Denied

```bash
ERROR: (gcloud.projects.get-iam-policy) User does not have permission
```

**Solution**: Ensure you have:
- `roles/viewer` on source project
- `roles/resourcemanager.projectIamAdmin` on target project


## 🙏 Acknowledgments

- Built for the GCP DevOps community
- Inspired by common IAM management challenges in multi-project environments

---

