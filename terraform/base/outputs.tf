output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "backend_config" {
  description = "Backend configuration to use in main infrastructure"
  value = <<-EOT
Add this to your terraform/dev/main.tf:

terraform {
  backend "s3" {
    bucket       = "${aws_s3_bucket.terraform_state.id}"
    key          = "dev/terraform.tfstate"
    region       = "${var.aws_region}"
    use_lockfile = true
    encrypt      = true
  }
}
  EOT
}
