# GCP IAM Role Automation Script

This script automates the process of applying IAM roles to multiple GCP projects for service accounts, users, or groups.

## Files

1. **iam_roles_apply.sh** - Main automation script
2. **roles.txt** - File containing list of roles to apply (must be in same directory)
3. **projects.txt** - File containing list of project IDs (must be in same directory)

## Prerequisites

- `gcloud` CLI installed and configured
- Authenticated with proper permissions to modify IAM policies
- Permission to run: `gcloud projects add-iam-policy-binding`

## Setup

1. Place all files in the same directory:
   - `iam_roles_apply.sh`
   - `roles.txt`
   - `projects.txt`

2. Make the script executable:
```bash
chmod +x iam_roles_apply.sh
```

3. Authenticate with gcloud:
```bash
gcloud auth login
gcloud auth application-default login
```

## File Formats

### roles.txt
One role per line. Lines starting with `#` are treated as comments.

```
# Monitoring roles
roles/compute.viewer
roles/monitoring.metricWriter
roles/logging.logWriter

# Storage roles
roles/storage.objectViewer
```

### projects.txt
One project ID per line. Lines starting with `#` are treated as comments.

```
# Development projects
project-dev-123456

# Production projects
project-prod-789012
```

## Usage

The script automatically uses `roles.txt` and `projects.txt` from the same directory.

### For Service Account:
```bash
./iam_roles_apply.sh serviceAccount:prometheus-sa@monitoring-project.iam.gserviceaccount.com
```

### For User:
```bash
./iam_roles_apply.sh user:jane@example.com
```

### For Group:
```bash
./iam_roles_apply.sh group:devops-team@example.com
```

## Command Syntax

```bash
./iam_roles_apply.sh <member>
```

**Parameters:**
- `member` - Member in format `type:identifier`
  - Types: `serviceAccount`, `user`, or `group`
  - Examples:
    - `user:jane@example.com`
    - `serviceAccount:sa@project.iam.gserviceaccount.com`
    - `group:team@example.com`

**Note:** The script will automatically look for `roles.txt` and `projects.txt` in the same directory as the script.

## Features

✅ Batch processing of multiple roles and projects
✅ Support for service accounts, users, and groups
✅ Detailed logging with timestamps
✅ Color-coded output for easy reading
✅ Error handling and validation
✅ Progress tracking
✅ Success/failure summary
✅ Confirmation prompt before execution
✅ Comments support in input files

## Output

The script will:
1. Display a summary of what will be applied
2. Ask for confirmation
3. Process each role for each project
4. Show real-time progress with color coding:
   - 🟢 **GREEN** = Success
   - 🔴 **RED** = Failed
   - 🟡 **YELLOW** = Info/headers
5. Create a detailed log file: `iam_binding_YYYYMMDD_HHMMSS.log`
6. Display final summary with counts

## Example Output

```
======================================
IAM Role Binding Automation
======================================
Roles file: roles.txt
Projects file: projects.txt
Member: serviceAccount:prometheus-sa@monitoring-project.iam.gserviceaccount.com
======================================

Found 4 roles to apply
Found 3 projects

Logging to: iam_binding_20250202_143022.log

Do you want to proceed? (yes/no): yes

Starting IAM policy binding...
Timestamp: Mon Feb  2 14:30:25 UTC 2026

Processing project: project-dev-123456
  Applying role: roles/compute.viewer ... SUCCESS
  Applying role: roles/monitoring.metricWriter ... SUCCESS
  Applying role: roles/logging.logWriter ... SUCCESS
  Applying role: roles/storage.objectViewer ... SUCCESS

Processing project: project-staging-789012
  Applying role: roles/compute.viewer ... SUCCESS
  Applying role: roles/monitoring.metricWriter ... SUCCESS
  Applying role: roles/logging.logWriter ... SUCCESS
  Applying role: roles/storage.objectViewer ... SUCCESS

======================================
Summary
======================================
Total operations: 12
Successful: 12
Failed: 0
======================================
```

## Common Roles

Here are some commonly used GCP IAM roles:

**Compute:**
- `roles/compute.viewer`
- `roles/compute.admin`
- `roles/compute.instanceAdmin`

**Monitoring:**
- `roles/monitoring.metricWriter`
- `roles/monitoring.viewer`

**Logging:**
- `roles/logging.logWriter`
- `roles/logging.viewer`

**Storage:**
- `roles/storage.objectViewer`
- `roles/storage.objectCreator`
- `roles/storage.admin`

**BigQuery:**
- `roles/bigquery.dataViewer`
- `roles/bigquery.dataEditor`
- `roles/bigquery.jobUser`

## Troubleshooting

### Permission Denied
- Ensure you have `resourcemanager.projects.setIamPolicy` permission
- You typically need `Project IAM Admin` or `Owner` role

### Project Not Found
- Verify project IDs are correct
- Check you have access to the projects
- Use `gcloud projects list` to verify

### Service Account Not Found
- Ensure the service account exists
- Verify the full email format: `name@project-id.iam.gserviceaccount.com`

### Dry Run (Optional Enhancement)
To test without making changes, you can modify the script to add `--dry-run` flag or comment out the actual gcloud command and just echo it.

## Best Practices

1. **Test First**: Start with a single project and role to test
2. **Use Comments**: Document why roles are being assigned in your input files
3. **Review Logs**: Always check the log file for any failures
4. **Least Privilege**: Only grant necessary roles
5. **Backup**: Document current IAM policies before making changes
6. **Version Control**: Keep roles.txt and projects.txt in version control

## Security Considerations

⚠️ **Important:**
- This script grants IAM permissions - use with caution
- Review all roles and projects before execution
- Keep log files secure as they may contain sensitive project information
- Use service accounts with minimum required permissions
- Regularly audit IAM policies

## License

Free to use and modify as needed.
