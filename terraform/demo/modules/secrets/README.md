# Secrets Manager Module

This module creates and populates all AWS Secrets Manager secrets for the KubeStock project.

## Architecture

```
GitHub Secrets → terraform.tfvars → Terraform → AWS Secrets Manager → External Secrets Operator → Kubernetes Secrets
```

## Managed Secrets

| Secret Path | Environment | Description |
|-------------|-------------|-------------|
| `kubestock/production/db` | Production | Database credentials (from RDS) |
| `kubestock/staging/db` | Staging | Database credentials (from RDS) |
| `kubestock/production/asgardeo` | Production | Asgardeo OAuth configuration |
| `kubestock/staging/asgardeo` | Staging | Asgardeo OAuth configuration |
| `kubestock/production/alertmanager/slack` | Production | Slack webhook URLs |
| `kubestock/shared/test-runner` | Shared | Test runner OAuth credentials |

## IAM User

This module creates an IAM user `kubestock-external-secrets` for the External Secrets Operator with:
- Read-only access to `kubestock/*` secrets
- ECR authorization token generation
- ECR image pull access for `kubestock/*` repositories

## Usage

```hcl
module "secrets" {
  source = "./modules/secrets"

  project_name   = "kubestock"
  environments   = ["production", "staging"]
  aws_region     = "ap-south-1"
  aws_account_id = "123456789012"

  # Database credentials - host/name from RDS module
  db_credentials = {
    production = {
      host     = module.rds.prod_db_address
      user     = "kubestock"
      password = var.db_password
      name     = module.rds.prod_db_name
    }
    staging = {
      host     = module.rds.staging_db_address
      user     = "kubestock"
      password = var.db_password
      name     = module.rds.staging_db_name
    }
  }

  asgardeo_credentials        = var.asgardeo_credentials
  alertmanager_slack_webhooks = var.alertmanager_slack_webhooks
  test_runner_credentials     = var.test_runner_credentials
}
```

## Bootstrap Procedure

After running `terraform apply`:

1. Create access key for the ESO IAM user:
   ```bash
   aws iam create-access-key --user-name kubestock-external-secrets
   ```

2. Create Kubernetes secret:
   ```bash
   kubectl create secret generic aws-external-secrets-creds \
     --from-literal=access-key-id=AKIAXXXXXXXX \
     --from-literal=secret-access-key=XXXXXXXX \
     --namespace=external-secrets
   ```

3. Apply ClusterSecretStore:
   ```bash
   kubectl apply -f gitops/base/external-secrets/cluster-secret-store.yaml
   ```

4. Verify:
   ```bash
   kubectl get clustersecretstore aws-secretsmanager
   kubectl get externalsecrets -A
   ```

## Outputs

| Output | Description |
|--------|-------------|
| `db_secret_arns` | Map of environment to database secret ARNs |
| `asgardeo_secret_arns` | Map of environment to Asgardeo secret ARNs |
| `alertmanager_slack_secret_arn` | ARN of production Alertmanager Slack secret |
| `test_runner_secret_arn` | ARN of shared test runner secret |
| `external_secrets_user_arn` | ARN of the ESO IAM user |
| `external_secrets_user_name` | Name of the ESO IAM user |
