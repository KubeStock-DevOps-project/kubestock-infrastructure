# ========================================
# TERRAFORM BACKEND CONFIGURATION
# ========================================
# This configures Terraform to store state in S3 for team collaboration
# and state locking with DynamoDB.

terraform {
  backend "s3" {
    bucket = "kubestock-terraform-state-prod" # Placeholder - update with actual bucket name
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
    # Optional: Uncomment below if using DynamoDB for state locking
    # dynamodb_table = "kubestock-terraform-locks-prod"
    # encrypt        = true
  }
}
