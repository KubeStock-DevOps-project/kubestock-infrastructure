# KubeStock Terraform Bootstrap

This directory contains scripts to bootstrap the AWS infrastructure required to run Terraform via GitHub Actions.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GitHub Actions Workflow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Assume Role via OIDC ────────────────────────────────────────────────┐  │
│                                                                          │  │
│                              ┌───────────────────────────────────────────▼──┤
│                              │         AWS Account                          │
│                              │  ┌─────────────────────────────────────────┐ │
│  2. Fetch Secrets ──────────►│  │  Secrets Manager                        │ │
│                              │  │  kubestock/terraform/security           │ │
│                              │  │  kubestock/terraform/database           │ │
│                              │  │  kubestock/terraform/asgardeo           │ │
│                              │  │  kubestock/terraform/alertmanager_slack │ │
│                              │  │  kubestock/terraform/test_runner        │ │
│                              │  └─────────────────────────────────────────┘ │
│                              │                                              │
│  3. Generate tfvars ◄────────┤  ┌─────────────────────────────────────────┐ │
│     (in-memory)              │  │  S3 Bucket                              │ │
│                              │  │  kubestock-terraform-state              │ │
│  4. terraform plan/apply ───►│  │  - terraform.tfstate                    │ │
│                              │  └─────────────────────────────────────────┘ │
│                              │                                              │
│  5. Cleanup tfvars           │  ┌─────────────────────────────────────────┐ │
│                              │  │  IAM Roles (via OIDC)                   │ │
│                              │  │  - KubeStock-Terraform-Plan-Role        │ │
│                              │  │  - KubeStock-Terraform-Apply-Role       │ │
│                              │  └─────────────────────────────────────────┘ │
│                              └──────────────────────────────────────────────┤
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| OIDC Provider | token.actions.githubusercontent.com | Trust GitHub Actions |
| IAM Role | KubeStock-Terraform-Plan-Role | Read-only for `terraform plan` |
| IAM Role | KubeStock-Terraform-Apply-Role | Full access for `terraform apply` |
| IAM Policy | KubeStock-Terraform-Plan-Policy | Read permissions |
| IAM Policy | KubeStock-Terraform-Apply-Policy | Write permissions |
| IAM Policy | KubeStock-Terraform-Secrets-Policy | Access to bootstrap secrets |
| S3 Bucket | kubestock-terraform-state | Terraform remote state |
| Secrets | kubestock/terraform/* | Bootstrap secrets |

## Prerequisites

1. **AWS CLI v2** configured with admin privileges
2. **jq** installed
3. Logged in to AWS CLI (`aws sts get-caller-identity` should work)

## Usage

### 1. Initial Setup (Dry Run)

```bash
cd infrastructure/bootstrap
./bootstrap.sh
```

This shows what would be created without making any changes.

### 2. Create secrets.json

Copy the example and fill in your values:

```bash
cp secrets.json.example secrets.json
# Edit secrets.json with your actual secrets
```

### 3. Apply Bootstrap

```bash
./bootstrap.sh --apply
```

### 4. Update GitHub Repository

After running bootstrap, update GitHub repository settings:

**Variables** (Settings → Secrets and variables → Actions → Variables):
- `AWS_REGION`: `ap-south-1`
- `AWS_PLAN_ROLE_ARN`: `arn:aws:iam::ACCOUNT_ID:role/KubeStock-Terraform-Plan-Role`
- `AWS_APPLY_ROLE_ARN`: `arn:aws:iam::ACCOUNT_ID:role/KubeStock-Terraform-Apply-Role`

### 5. Update Existing Secrets

To update secrets after initial creation:

```bash
./bootstrap.sh --apply --force
```

## Files

| File | Purpose | Commit? |
|------|---------|---------|
| `bootstrap.sh` | Main bootstrap script | ✅ Yes |
| `generate-tfvars.sh` | Helper to generate tfvars from secrets | ✅ Yes |
| `secrets.json.example` | Template for secrets | ✅ Yes |
| `secrets.json` | Actual secrets | ❌ **NEVER** |
| `policies/terraform-plan-policy.json` | Plan IAM policy | ✅ Yes |
| `policies/terraform-apply-policy.json` | Apply IAM policy | ✅ Yes |
| `backups/` | Terraform state backups | ❌ No |
| `github-vars.txt` | Generated GitHub config | ❌ No |

## Secrets Structure

The secrets in AWS Secrets Manager are organized as:

```
kubestock/terraform/
├── security          # my_ip, ssh_public_key_content
├── database          # password, username
├── asgardeo          # production/staging OAuth config
├── alertmanager_slack # Slack webhook URLs
└── test_runner       # Test runner credentials
```

## Migration from GitHub Secrets

If you're migrating from the old GitHub Secrets approach:

1. Run the bootstrap script to create Secrets Manager entries
2. Replace the old workflow files with the `-v2` versions
3. Remove the old GitHub Secrets (MY_IP, SSH_PUBLIC_KEY_CONTENT, DB_PASSWORD)
4. Add the new GitHub Variables (AWS_PLAN_ROLE_ARN, AWS_APPLY_ROLE_ARN)

## Security Considerations

- **Least Privilege**: Plan role has read-only access, Apply role has write access
- **No Secrets in GitHub**: Only role ARNs are stored in GitHub Variables
- **State Backup**: Bootstrap always backs up existing state before any changes
- **Idempotent**: Safe to run multiple times
- **Audit Trail**: Secrets Manager provides access logging

## Troubleshooting

### "Access Denied" when fetching secrets

Ensure the role has the `KubeStock-Terraform-Secrets-Policy` attached.

### "OIDC Provider already exists"

This is fine - the script is idempotent and will continue.

### "Policy version limit exceeded"

The script automatically cleans up old policy versions. Run again if you hit limits.
