# ========================================
# TERRAFORM BACKEND CONFIGURATION
# ========================================
# This configures Terraform to store state in S3 for team collaboration
# and state locking with DynamoDB.

terraform {
  backend "s3" {
    bucket = "kubestock-terraform-state" # Placeholder - update with actual bucket name
    key    = "terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }
}
