# GitHub Actions Secrets and Variables Setup

This document outlines the required secrets and variables that must be configured in your GitHub repository settings for the Terraform CI/CD workflows to function properly.

## Required Configuration

### Repository Variables (Settings → Secrets and variables → Actions → Variables)

These are non-sensitive values that can be viewed in logs:

| Variable Name | Description | Example Value |
|--------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key ID for Terraform | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_REGION` | AWS region for deployment | `us-east-1` |
| `MY_IP` | Your public IP address with CIDR notation for SSH/API access | `175.157.109.19/32` |

**Note:** Get your public IP by running: `curl -4 ifconfig.me`

### Repository Secrets (Settings → Secrets and variables → Actions → Secrets)

These are sensitive values that are encrypted and hidden in logs:

| Secret Name | Description | Example Source |
|------------|-------------|----------------|
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key for Terraform | From AWS IAM Console |
| `SSH_PUBLIC_KEY_CONTENT` | SSH public key content (not file path) | `cat ~/.ssh/kubestock-key.pub` |
| `RDS_PASSWORD` | PostgreSQL RDS master password | Strong random password (min 8 chars) |

## How to Configure

### Adding Variables

1. Go to your repository on GitHub
2. Navigate to: **Settings** → **Secrets and variables** → **Actions** → **Variables** tab
3. Click **"New repository variable"**
4. Add each variable with its name and value
5. Click **"Add variable"**

### Adding Secrets

1. Go to your repository on GitHub
2. Navigate to: **Settings** → **Secrets and variables** → **Actions** → **Secrets** tab
3. Click **"New repository secret"**
4. Add each secret with its name and value
5. Click **"Add secret"**

## Workflow Usage

### PR Checks Workflow (`terraform-pr-checks.yml`)
- **No secrets required** - runs with `-backend=false` for validation only

### Prod Deploy Workflow (`terraform-prod-apply.yml`)
- Generates `terraform.tfvars` from secrets/variables before init
- Uses AWS credentials for init/plan/apply operations
- All three Terraform variables (`my_ip`, `ssh_public_key_content`, `rds_password`) are injected

## Security Notes

- **Never commit** `terraform.tfvars` to version control
- The `.gitignore` should include `*.tfvars` (except `*.tfvars.example`)
- AWS credentials should have minimum required permissions (least privilege)
- Rotate RDS password periodically and update the GitHub secret
- Update `MY_IP` variable if your public IP changes

## Testing

After configuring all secrets and variables:

1. Create a test PR to verify the PR checks workflow runs successfully
2. Merge to main to trigger the prod deploy workflow
3. Monitor the Actions tab to ensure terraform apply completes without errors

## Troubleshooting

If you see errors about missing variables:
- Verify all required secrets and variables are configured
- Check for typos in variable/secret names (case-sensitive)
- Ensure values don't have extra quotes or whitespace
- For SSH key: paste the entire key content including `ssh-rsa` prefix and email suffix
