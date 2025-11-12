# Terraform Backend Setup

Creates S3 bucket for storing Terraform state with native S3 locking (no DynamoDB needed).

## Quick Start

```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit with your AWS credentials

# 2. Deploy backend
terraform init
terraform apply

# 3. Note the bucket name for dev/main.tf
terraform output state_bucket_name
```

## What Gets Created

- S3 bucket with versioning enabled
- Encryption enabled (AES256)
- Public access blocked
- Native S3 state locking (Terraform 1.5+ feature)

## Setup

1. Edit `terraform.tfvars` with your AWS credentials
2. Run `terraform init && terraform apply`
3. Use the bucket name in `dev/main.tf` backend configuration

## Note

- Bucket name must be globally unique
- Run this ONCE before deploying dev infrastructure
- Uses native S3 locking (Terraform 1.5+, no DynamoDB needed)
