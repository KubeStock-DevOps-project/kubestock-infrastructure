#!/usr/bin/env bash
# =============================================================================
# GENERATE TERRAFORM TFVARS FROM AWS SECRETS MANAGER
# =============================================================================
# This script fetches secrets from AWS Secrets Manager and generates a
# terraform.tfvars file for use in CI/CD pipelines.
#
# USAGE:
#   ./generate-tfvars.sh                    # Output to stdout
#   ./generate-tfvars.sh --output tfvars    # Write to terraform.tfvars
#
# REQUIREMENTS:
#   - AWS CLI configured with appropriate permissions
#   - jq installed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION="${AWS_REGION:-ap-south-1}"
SECRETS_PREFIX="kubestock/terraform"
OUTPUT_MODE="stdout"
OUTPUT_FILE=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --output)
            OUTPUT_MODE="file"
            ;;
        *)
            if [[ "${OUTPUT_MODE}" == "file" && -z "${OUTPUT_FILE}" ]]; then
                OUTPUT_FILE="$arg"
            fi
            ;;
    esac
done

# Function to get secret
get_secret() {
    local secret_name="$1"
    aws secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --query 'SecretString' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "{}"
}

# Fetch all secrets
SECURITY_SECRET=$(get_secret "${SECRETS_PREFIX}/security")
DATABASE_SECRET=$(get_secret "${SECRETS_PREFIX}/database")
ASGARDEO_SECRET=$(get_secret "${SECRETS_PREFIX}/asgardeo")
SLACK_SECRET=$(get_secret "${SECRETS_PREFIX}/alertmanager_slack")
TEST_RUNNER_SECRET=$(get_secret "${SECRETS_PREFIX}/test_runner")

# Generate tfvars content
generate_tfvars() {
    cat <<EOF
# =============================================================================
# AUTO-GENERATED TERRAFORM VARIABLES
# =============================================================================
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT COMMIT THIS FILE TO VERSION CONTROL
# =============================================================================

# =============================================================================
# Security
# =============================================================================
my_ip = "$(echo "${SECURITY_SECRET}" | jq -r '.my_ip // empty')"
ssh_public_key_content = "$(echo "${SECURITY_SECRET}" | jq -r '.ssh_public_key_content // empty')"

# =============================================================================
# Database
# =============================================================================
db_password = "$(echo "${DATABASE_SECRET}" | jq -r '.password // empty')"
db_username = "$(echo "${DATABASE_SECRET}" | jq -r '.username // "kubestock_admin"')"

# =============================================================================
# Asgardeo Credentials
# =============================================================================
asgardeo_credentials = {
  production = {
    org_name                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.org_name // empty')"
    base_url                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.base_url // empty')"
    scim2_url                = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.scim2_url // empty')"
    token_url                = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.token_url // empty')"
    jwks_url                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.jwks_url // empty')"
    issuer                   = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.issuer // empty')"
    spa_client_id            = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.spa_client_id // empty')"
    m2m_client_id            = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.m2m_client_id // empty')"
    m2m_client_secret        = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.m2m_client_secret // empty')"
    group_id_admin           = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.group_id_admin // empty')"
    group_id_supplier        = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.group_id_supplier // empty')"
    group_id_warehouse_staff = "$(echo "${ASGARDEO_SECRET}" | jq -r '.production.group_id_warehouse_staff // empty')"
  }
  staging = {
    org_name                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.org_name // empty')"
    base_url                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.base_url // empty')"
    scim2_url                = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.scim2_url // empty')"
    token_url                = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.token_url // empty')"
    jwks_url                 = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.jwks_url // empty')"
    issuer                   = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.issuer // empty')"
    spa_client_id            = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.spa_client_id // empty')"
    m2m_client_id            = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.m2m_client_id // empty')"
    m2m_client_secret        = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.m2m_client_secret // empty')"
    group_id_admin           = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.group_id_admin // empty')"
    group_id_supplier        = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.group_id_supplier // empty')"
    group_id_warehouse_staff = "$(echo "${ASGARDEO_SECRET}" | jq -r '.staging.group_id_warehouse_staff // empty')"
  }
}

# =============================================================================
# Alertmanager Slack Webhooks
# =============================================================================
alertmanager_slack_webhooks = {
  default_url  = "$(echo "${SLACK_SECRET}" | jq -r '.default_url // empty')"
  critical_url = "$(echo "${SLACK_SECRET}" | jq -r '.critical_url // empty')"
  warning_url  = "$(echo "${SLACK_SECRET}" | jq -r '.warning_url // empty')"
}

# =============================================================================
# Test Runner Credentials
# =============================================================================
test_runner_credentials = {
  client_id     = "$(echo "${TEST_RUNNER_SECRET}" | jq -r '.client_id // empty')"
  client_secret = "$(echo "${TEST_RUNNER_SECRET}" | jq -r '.client_secret // empty')"
  username      = "$(echo "${TEST_RUNNER_SECRET}" | jq -r '.username // empty')"
  password      = "$(echo "${TEST_RUNNER_SECRET}" | jq -r '.password // empty')"
}
EOF
}

# Output
if [[ "${OUTPUT_MODE}" == "file" && -n "${OUTPUT_FILE}" ]]; then
    generate_tfvars > "${OUTPUT_FILE}"
    chmod 600 "${OUTPUT_FILE}"
    echo "Generated: ${OUTPUT_FILE}"
else
    generate_tfvars
fi
