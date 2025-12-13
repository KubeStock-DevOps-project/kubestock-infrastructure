# Secrets Module

Creates AWS Secrets Manager secrets for the KubeStock project.

## Secrets Created

- `kubestock/{env}/db` - Database credentials (per environment)
- `kubestock/{env}/asgardeo` - Asgardeo OAuth credentials (per environment)
- `kubestock/{env}/alertmanager/slack` - Slack webhook URLs (per environment)
- `kubestock/shared/test-user` - Test user credentials (shared)

## Populate Secrets

```bash
# Test user (shared)
aws secretsmanager put-secret-value \
  --secret-id kubestock/shared/test-user \
  --secret-string '{"username":"test_runner@yopmail.com","password":"Test_runner123"}' \
  --region us-east-1

# Database (per environment)
aws secretsmanager put-secret-value \
  --secret-id kubestock/staging/db \
  --secret-string '{"username":"admin","password":"xxx","host":"db.example.com","port":"5432","database":"kubestock"}' \
  --region us-east-1
```

## Kubernetes Integration

Deploy ExternalSecret: `kubectl apply -f k8s-externalsecret-test-user.yaml`
