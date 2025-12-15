#!/usr/bin/env bash
# =============================================================================
# KUBESTOCK TERRAFORM BOOTSTRAP SCRIPT
# =============================================================================
# This script sets up the AWS infrastructure required to run Terraform:
#   1. GitHub Actions OIDC Provider
#   2. Terraform Plan/Apply IAM Roles with OIDC trust
#   3. Terraform State S3 Bucket (with backup protection)
#   4. AWS Secrets Manager secrets for Terraform variables
#
# REQUIREMENTS:
#   - AWS CLI v2 configured with admin privileges
#   - jq installed
#   - Logged in to AWS CLI (aws sts get-caller-identity should work)
#
# USAGE:
#   ./bootstrap.sh                    # Dry run (shows what would be done)
#   ./bootstrap.sh --apply            # Actually apply changes
#   ./bootstrap.sh --apply --force    # Force update secrets even if they exist
#
# This script is IDEMPOTENT - safe to run multiple times.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="kubestock"
PROJECT_NAME_TITLE="KubeStock"
AWS_REGION="${AWS_REGION:-ap-south-1}"
STATE_BUCKET_REGION="${STATE_BUCKET_REGION:-us-east-1}"  # State bucket region (can differ)

# GitHub Configuration
GITHUB_ORG="KubeStock-DevOps-project"
GITHUB_REPOS=("kubestock-infrastructure" "kubestock-core")

# S3 Buckets
STATE_BUCKET_NAME="${PROJECT_NAME}-terraform-state"

# Secrets Manager
SECRETS_PREFIX="${PROJECT_NAME}/terraform"

# IAM Names
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
PLAN_ROLE_NAME="${PROJECT_NAME_TITLE}-Terraform-Plan-Role"
APPLY_ROLE_NAME="${PROJECT_NAME_TITLE}-Terraform-Apply-Role"
SECRETS_ROLE_NAME="${PROJECT_NAME_TITLE}-Terraform-Secrets-Role"
PLAN_POLICY_NAME="${PROJECT_NAME_TITLE}-Terraform-Plan-Policy"
APPLY_POLICY_NAME="${PROJECT_NAME_TITLE}-Terraform-Apply-Policy"
SECRETS_POLICY_NAME="${PROJECT_NAME_TITLE}-Terraform-Secrets-Policy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Disable AWS CLI pager to prevent vim/less from opening
export AWS_PAGER=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log_error "Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_info "Using AWS Account: ${ACCOUNT_ID}"
    log_info "Region: ${AWS_REGION}"
}

# =============================================================================
# OIDC PROVIDER
# =============================================================================

create_oidc_provider() {
    log_info "Checking GitHub Actions OIDC Provider..."
    
    local provider_arn="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" &> /dev/null; then
        log_success "OIDC Provider already exists: ${provider_arn}"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Would create OIDC Provider for GitHub Actions"
        return 0
    fi
    
    log_info "Creating OIDC Provider for GitHub Actions..."
    
    # Get GitHub's OIDC thumbprint
    local thumbprint
    thumbprint=$(echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout 2>/dev/null | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    
    # Fallback to known thumbprint if openssl fails
    if [[ -z "${thumbprint}" ]]; then
        thumbprint="6938fd4d98bab03faadb97b34396831e3780aea1"
        log_warn "Using fallback thumbprint: ${thumbprint}"
    fi
    
    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER_URL}" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "${thumbprint}" \
        --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
    
    log_success "OIDC Provider created successfully"
}

# =============================================================================
# S3 STATE BUCKET
# =============================================================================

backup_terraform_state() {
    log_info "Checking for existing Terraform state to backup..."
    
    if ! aws s3api head-bucket --bucket "${STATE_BUCKET_NAME}" 2>/dev/null; then
        log_info "State bucket does not exist yet, no backup needed"
        return 0
    fi
    
    # Check if state file exists
    if ! aws s3api head-object --bucket "${STATE_BUCKET_NAME}" --key "terraform.tfstate" 2>/dev/null; then
        log_info "No terraform.tfstate found in bucket, no backup needed"
        return 0
    fi
    
    local backup_dir="${SCRIPT_DIR}/backups"
    local backup_file="${backup_dir}/terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "${backup_dir}"
    
    log_warn "⚠️  BACKING UP TERRAFORM STATE TO LOCAL FILE"
    log_warn "Backup location: ${backup_file}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Would backup state to: ${backup_file}"
        return 0
    fi
    
    aws s3 cp "s3://${STATE_BUCKET_NAME}/terraform.tfstate" "${backup_file}"
    
    # Also backup any other state files
    aws s3 sync "s3://${STATE_BUCKET_NAME}/" "${backup_dir}/" --exclude "*" --include "*.tfstate*"
    
    log_success "State backup completed: ${backup_file}"
    log_warn "KEEP THIS BACKUP SAFE! You may need it for recovery."
}

create_state_bucket() {
    log_info "Checking Terraform state S3 bucket..."
    
    if aws s3api head-bucket --bucket "${STATE_BUCKET_NAME}" 2>/dev/null; then
        log_success "State bucket already exists: ${STATE_BUCKET_NAME}"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Would create S3 bucket: ${STATE_BUCKET_NAME}"
        return 0
    fi
    
    log_info "Creating S3 bucket for Terraform state..."
    
    # Create bucket (us-east-1 doesn't need LocationConstraint)
    if [[ "${STATE_BUCKET_REGION}" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "${STATE_BUCKET_NAME}" \
            --region "${STATE_BUCKET_REGION}"
    else
        aws s3api create-bucket \
            --bucket "${STATE_BUCKET_NAME}" \
            --region "${STATE_BUCKET_REGION}" \
            --create-bucket-configuration LocationConstraint="${STATE_BUCKET_REGION}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${STATE_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${STATE_BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${STATE_BUCKET_NAME}" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }'
    
    # Add tags
    aws s3api put-bucket-tagging \
        --bucket "${STATE_BUCKET_NAME}" \
        --tagging "TagSet=[{Key=ManagedBy,Value=bootstrap},{Key=Project,Value=${PROJECT_NAME}},{Key=Purpose,Value=terraform-state}]"
    
    log_success "State bucket created with versioning and encryption enabled"
}

# =============================================================================
# IAM POLICIES
# =============================================================================

create_plan_policy() {
    log_info "Checking Terraform Plan policy..."
    
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${PLAN_POLICY_NAME}"
    
    # Read policy from file
    local policy_file="${SCRIPT_DIR}/policies/terraform-plan-policy.json"
    if [[ ! -f "${policy_file}" ]]; then
        log_error "Policy file not found: ${policy_file}"
        exit 1
    fi
    
    local policy_doc
    policy_doc=$(cat "${policy_file}" | jq -c .)
    
    if aws iam get-policy --policy-arn "${policy_arn}" &> /dev/null; then
        log_info "Policy exists, checking if update needed..."
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would update policy: ${PLAN_POLICY_NAME}"
            return 0
        fi
        
        # Delete old non-default versions FIRST to make room for new version
        local old_versions
        old_versions=$(aws iam list-policy-versions --policy-arn "${policy_arn}" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
        
        for v in ${old_versions}; do
            log_info "Deleting old policy version: ${v}"
            aws iam delete-policy-version --policy-arn "${policy_arn}" --version-id "${v}" || true
        done
        
        # Create new version
        aws iam create-policy-version \
            --policy-arn "${policy_arn}" \
            --policy-document "${policy_doc}" \
            --set-as-default
        
        log_success "Plan policy updated"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would create policy: ${PLAN_POLICY_NAME}"
            return 0
        fi
        
        aws iam create-policy \
            --policy-name "${PLAN_POLICY_NAME}" \
            --policy-document "${policy_doc}" \
            --description "Read-only policy for Terraform plan operations" \
            --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
        
        log_success "Plan policy created"
    fi
}

create_apply_policy() {
    log_info "Checking Terraform Apply policy..."
    
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${APPLY_POLICY_NAME}"
    
    local policy_file="${SCRIPT_DIR}/policies/terraform-apply-policy.json"
    if [[ ! -f "${policy_file}" ]]; then
        log_error "Policy file not found: ${policy_file}"
        exit 1
    fi
    
    local policy_doc
    policy_doc=$(cat "${policy_file}" | jq -c .)
    
    if aws iam get-policy --policy-arn "${policy_arn}" &> /dev/null; then
        log_info "Policy exists, checking if update needed..."
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would update policy: ${APPLY_POLICY_NAME}"
            return 0
        fi
        
        # Delete old non-default versions FIRST to make room for new version
        local old_versions
        old_versions=$(aws iam list-policy-versions --policy-arn "${policy_arn}" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
        
        for v in ${old_versions}; do
            log_info "Deleting old policy version: ${v}"
            aws iam delete-policy-version --policy-arn "${policy_arn}" --version-id "${v}" || true
        done
        
        # Create new version
        aws iam create-policy-version \
            --policy-arn "${policy_arn}" \
            --policy-document "${policy_doc}" \
            --set-as-default
        
        log_success "Apply policy updated"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would create policy: ${APPLY_POLICY_NAME}"
            return 0
        fi
        
        aws iam create-policy \
            --policy-name "${APPLY_POLICY_NAME}" \
            --policy-document "${policy_doc}" \
            --description "Full access policy for Terraform apply operations" \
            --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
        
        log_success "Apply policy created"
    fi
}

create_secrets_policy() {
    log_info "Checking Terraform Secrets policy..."
    
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${SECRETS_POLICY_NAME}"
    
    # Create minimal policy for reading bootstrap secrets only
    local policy_doc
    policy_doc=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadBootstrapSecrets",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:${SECRETS_PREFIX}/*"
        },
        {
            "Sid": "ListSecrets",
            "Effect": "Allow",
            "Action": "secretsmanager:ListSecrets",
            "Resource": "*"
        }
    ]
}
EOF
)
    
    if aws iam get-policy --policy-arn "${policy_arn}" &> /dev/null; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would update policy: ${SECRETS_POLICY_NAME}"
            return 0
        fi
        
        aws iam create-policy-version \
            --policy-arn "${policy_arn}" \
            --policy-document "${policy_doc}" \
            --set-as-default || true
        
        log_success "Secrets policy updated"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would create policy: ${SECRETS_POLICY_NAME}"
            return 0
        fi
        
        aws iam create-policy \
            --policy-name "${SECRETS_POLICY_NAME}" \
            --policy-document "${policy_doc}" \
            --description "Least privilege policy for reading Terraform bootstrap secrets" \
            --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
        
        log_success "Secrets policy created"
    fi
}

# =============================================================================
# IAM ROLES
# =============================================================================

generate_trust_policy() {
    local role_type=$1  # "plan" or "apply"
    local provider_arn="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
    
    local conditions=""
    
    if [[ "${role_type}" == "plan" ]]; then
        # Plan role: allow PRs and main branch for all repos
        local sub_conditions=""
        for repo in "${GITHUB_REPOS[@]}"; do
            sub_conditions+="\"repo:${GITHUB_ORG}/${repo}:ref:refs/heads/main\","
            sub_conditions+="\"repo:${GITHUB_ORG}/${repo}:pull_request\","
        done
        sub_conditions="${sub_conditions%,}"  # Remove trailing comma
        
        conditions="\"StringLike\": {
            \"${OIDC_PROVIDER_URL}:sub\": [${sub_conditions}]
        }"
    else
        # Apply role: only main branch and production environment
        local sub_conditions=""
        for repo in "${GITHUB_REPOS[@]}"; do
            sub_conditions+="\"repo:${GITHUB_ORG}/${repo}:ref:refs/heads/main\","
            sub_conditions+="\"repo:${GITHUB_ORG}/${repo}:environment:production\","
        done
        sub_conditions="${sub_conditions%,}"
        
        conditions="\"StringLike\": {
            \"${OIDC_PROVIDER_URL}:sub\": [${sub_conditions}]
        }"
    fi
    
    cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${provider_arn}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER_URL}:aud": "sts.amazonaws.com"
                },
                ${conditions}
            }
        }
    ]
}
EOF
}

create_plan_role() {
    log_info "Checking Terraform Plan role..."
    
    local role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${PLAN_ROLE_NAME}"
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${PLAN_POLICY_NAME}"
    local secrets_policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${SECRETS_POLICY_NAME}"
    local trust_policy
    trust_policy=$(generate_trust_policy "plan")
    
    if aws iam get-role --role-name "${PLAN_ROLE_NAME}" &> /dev/null; then
        log_info "Role exists, updating trust policy..."
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would update role: ${PLAN_ROLE_NAME}"
            return 0
        fi
        
        aws iam update-assume-role-policy \
            --role-name "${PLAN_ROLE_NAME}" \
            --policy-document "${trust_policy}"
        
        log_success "Plan role trust policy updated"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would create role: ${PLAN_ROLE_NAME}"
            return 0
        fi
        
        aws iam create-role \
            --role-name "${PLAN_ROLE_NAME}" \
            --assume-role-policy-document "${trust_policy}" \
            --description "Role for Terraform plan operations via GitHub Actions OIDC" \
            --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
        
        log_success "Plan role created"
    fi
    
    # Attach policies
    if [[ "${DRY_RUN}" != "true" ]]; then
        aws iam attach-role-policy --role-name "${PLAN_ROLE_NAME}" --policy-arn "${policy_arn}" 2>/dev/null || true
        aws iam attach-role-policy --role-name "${PLAN_ROLE_NAME}" --policy-arn "${secrets_policy_arn}" 2>/dev/null || true
        log_success "Policies attached to Plan role"
    fi
}

create_apply_role() {
    log_info "Checking Terraform Apply role..."
    
    local role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${APPLY_ROLE_NAME}"
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${APPLY_POLICY_NAME}"
    local secrets_policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${SECRETS_POLICY_NAME}"
    local trust_policy
    trust_policy=$(generate_trust_policy "apply")
    
    if aws iam get-role --role-name "${APPLY_ROLE_NAME}" &> /dev/null; then
        log_info "Role exists, updating trust policy..."
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would update role: ${APPLY_ROLE_NAME}"
            return 0
        fi
        
        aws iam update-assume-role-policy \
            --role-name "${APPLY_ROLE_NAME}" \
            --policy-document "${trust_policy}"
        
        log_success "Apply role trust policy updated"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_warn "[DRY-RUN] Would create role: ${APPLY_ROLE_NAME}"
            return 0
        fi
        
        aws iam create-role \
            --role-name "${APPLY_ROLE_NAME}" \
            --assume-role-policy-document "${trust_policy}" \
            --description "Role for Terraform apply operations via GitHub Actions OIDC" \
            --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
        
        log_success "Apply role created"
    fi
    
    # Attach policies
    if [[ "${DRY_RUN}" != "true" ]]; then
        aws iam attach-role-policy --role-name "${APPLY_ROLE_NAME}" --policy-arn "${policy_arn}" 2>/dev/null || true
        aws iam attach-role-policy --role-name "${APPLY_ROLE_NAME}" --policy-arn "${secrets_policy_arn}" 2>/dev/null || true
        log_success "Policies attached to Apply role"
    fi
}

# =============================================================================
# SECRETS MANAGER
# =============================================================================

create_secrets() {
    log_info "Setting up AWS Secrets Manager secrets..."
    
    local secrets_file="${SCRIPT_DIR}/secrets.json"
    
    if [[ ! -f "${secrets_file}" ]]; then
        log_warn "secrets.json not found at: ${secrets_file}"
        log_info "Creating template file..."
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            create_secrets_template
            log_warn "Please fill in ${secrets_file} and run this script again."
        else
            log_warn "[DRY-RUN] Would create secrets.json template"
        fi
        return 0
    fi
    
    # Validate JSON
    if ! jq empty "${secrets_file}" 2>/dev/null; then
        log_error "Invalid JSON in secrets.json"
        exit 1
    fi
    
    # Read secrets from file
    local secret_names
    secret_names=$(jq -r 'keys[]' "${secrets_file}")
    
    for secret_key in ${secret_names}; do
        local secret_name="${SECRETS_PREFIX}/${secret_key}"
        local secret_value
        secret_value=$(jq -c ".\"${secret_key}\"" "${secrets_file}")
        
        # Check if it's a placeholder
        if echo "${secret_value}" | grep -q "CHANGE_ME\|your-\|xxx\|placeholder"; then
            log_warn "Skipping ${secret_name} - contains placeholder values"
            continue
        fi
        
        if aws secretsmanager describe-secret --secret-id "${secret_name}" &> /dev/null; then
            if [[ "${FORCE_UPDATE}" == "true" ]]; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_warn "[DRY-RUN] Would update secret: ${secret_name}"
                else
                    aws secretsmanager put-secret-value \
                        --secret-id "${secret_name}" \
                        --secret-string "${secret_value}"
                    log_success "Secret updated: ${secret_name}"
                fi
            else
                log_info "Secret exists (use --force to update): ${secret_name}"
            fi
        else
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_warn "[DRY-RUN] Would create secret: ${secret_name}"
            else
                aws secretsmanager create-secret \
                    --name "${secret_name}" \
                    --description "Terraform bootstrap secret for ${secret_key}" \
                    --secret-string "${secret_value}" \
                    --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=${PROJECT_NAME}
                log_success "Secret created: ${secret_name}"
            fi
        fi
    done
}

create_secrets_template() {
    local secrets_file="${SCRIPT_DIR}/secrets.json"
    
    cat > "${secrets_file}" <<'EOF'
{
    "security": {
        "my_ip": "YOUR_IP_ADDRESS/32",
        "ssh_public_key_content": "ssh-ed25519 AAAA... your-key-comment"
    },
    "database": {
        "password": "CHANGE_ME_STRONG_PASSWORD_16_CHARS_MIN",
        "username": "kubestock_admin"
    },
    "asgardeo": {
        "production": {
            "org_name": "kubestock",
            "base_url": "https://api.asgardeo.io/t/kubestock",
            "scim2_url": "https://api.asgardeo.io/t/kubestock/scim2",
            "token_url": "https://api.asgardeo.io/t/kubestock/oauth2/token",
            "jwks_url": "https://api.asgardeo.io/t/kubestock/oauth2/jwks",
            "issuer": "https://api.asgardeo.io/t/kubestock/oauth2/token",
            "spa_client_id": "your-spa-client-id",
            "m2m_client_id": "your-m2m-client-id",
            "m2m_client_secret": "your-m2m-client-secret",
            "group_id_admin": "00000000-0000-0000-0000-000000000001",
            "group_id_supplier": "00000000-0000-0000-0000-000000000002",
            "group_id_warehouse_staff": "00000000-0000-0000-0000-000000000003"
        },
        "staging": {
            "org_name": "kubestock",
            "base_url": "https://api.asgardeo.io/t/kubestock",
            "scim2_url": "https://api.asgardeo.io/t/kubestock/scim2",
            "token_url": "https://api.asgardeo.io/t/kubestock/oauth2/token",
            "jwks_url": "https://api.asgardeo.io/t/kubestock/oauth2/jwks",
            "issuer": "https://api.asgardeo.io/t/kubestock/oauth2/token",
            "spa_client_id": "your-spa-client-id",
            "m2m_client_id": "your-m2m-client-id",
            "m2m_client_secret": "your-m2m-client-secret",
            "group_id_admin": "00000000-0000-0000-0000-000000000001",
            "group_id_supplier": "00000000-0000-0000-0000-000000000002",
            "group_id_warehouse_staff": "00000000-0000-0000-0000-000000000003"
        }
    },
    "alertmanager_slack": {
        "default_url": "https://hooks.slack.com/services/T00/B00/XXXX",
        "critical_url": "https://hooks.slack.com/services/T00/B00/YYYY",
        "warning_url": "https://hooks.slack.com/services/T00/B00/ZZZZ"
    },
    "test_runner": {
        "client_id": "test-runner-client-id",
        "client_secret": "test-runner-client-secret",
        "username": "testrunner@kubestock.io",
        "password": "TestRunnerPassword123!"
    }
}
EOF
    
    chmod 600 "${secrets_file}"
    log_success "Created secrets template: ${secrets_file}"
    log_warn "⚠️  IMPORTANT: Add secrets.json to .gitignore!"
}

# =============================================================================
# GENERATE OUTPUTS
# =============================================================================

generate_github_vars() {
    log_info "Generating GitHub Actions configuration..."
    
    local output_file="${SCRIPT_DIR}/github-vars.txt"
    
    cat > "${output_file}" <<EOF
# =============================================================================
# GITHUB ACTIONS CONFIGURATION
# =============================================================================
# Add these as Repository Variables (Settings > Secrets and variables > Actions > Variables)
# =============================================================================

AWS_REGION=${AWS_REGION}

# =============================================================================
# Add these as Repository Secrets (Settings > Secrets and variables > Actions > Secrets)
# =============================================================================

# These are the ONLY secrets needed in GitHub:
AWS_PLAN_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${PLAN_ROLE_NAME}
AWS_APPLY_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${APPLY_ROLE_NAME}

# =============================================================================
# NOTES
# =============================================================================
# - All other secrets are now stored in AWS Secrets Manager
# - The workflow will fetch secrets using: aws secretsmanager get-secret-value
# - Secrets path: ${SECRETS_PREFIX}/*
# =============================================================================
EOF
    
    log_success "Generated: ${output_file}"
}

generate_tfvars_config() {
    log_info "Generating committable terraform.tfvars.config..."
    
    local output_file="${SCRIPT_DIR}/../terraform/prod/terraform.tfvars.config"
    
    cat > "${output_file}" <<'EOF'
# =============================================================================
# KUBESTOCK - TERRAFORM CONFIGURATION (COMMITTABLE)
# =============================================================================
# This file contains ONLY non-sensitive configuration values.
# All secrets are managed via AWS Secrets Manager.
#
# This file CAN and SHOULD be committed to version control.
# =============================================================================


# =============================================================================
# AWS Configuration
# =============================================================================
aws_region = "ap-south-1"


# =============================================================================
# RDS Configuration
# =============================================================================
prod_db_instance_class    = "db.t4g.medium"
staging_db_instance_class = "db.t4g.small"
prod_db_multi_az          = false
prod_db_deletion_protection = false


# =============================================================================
# Networking
# =============================================================================
availability_zones   = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
primary_az           = "ap-south-1a"
vpc_cidr             = "10.0.0.0/16"

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]


# =============================================================================
# Compute
# =============================================================================
bastion_instance_type        = "t3.micro"
dev_server_instance_type     = "t3.medium"
control_plane_instance_type  = "t3.medium"
worker_instance_type         = "t3.medium"

control_plane_private_ip = "10.0.10.21"
worker_private_ips       = ["10.0.11.30", "10.0.12.30"]


# =============================================================================
# Auto Scaling Group
# =============================================================================
asg_desired_capacity = 2
asg_min_size         = 1
asg_max_size         = 8


# =============================================================================
# DNS / SSL
# =============================================================================
domain_name        = "kubestock.dpiyumal.me"
create_hosted_zone = true


# =============================================================================
# WAF
# =============================================================================
enable_waf     = true
waf_rate_limit = 2000


# =============================================================================
# Observability
# =============================================================================
observability_log_retention_days     = 90
observability_metrics_retention_days = 365
EOF
    
    log_success "Generated: ${output_file}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo " KubeStock Terraform Bootstrap"
    echo "=========================================="
    echo ""
    
    # Parse arguments
    DRY_RUN="true"
    FORCE_UPDATE="false"
    
    for arg in "$@"; do
        case $arg in
            --apply)
                DRY_RUN="false"
                ;;
            --force)
                FORCE_UPDATE="true"
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --apply    Actually apply changes (default is dry-run)"
                echo "  --force    Force update secrets even if they exist"
                echo "  --help     Show this help message"
                echo ""
                exit 0
                ;;
        esac
    done
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "Running in DRY-RUN mode. Use --apply to make actual changes."
        echo ""
    fi
    
    # Pre-flight checks
    check_aws_cli
    
    echo ""
    log_info "Step 1/7: Backup existing Terraform state"
    backup_terraform_state
    
    echo ""
    log_info "Step 2/7: Create/Verify OIDC Provider"
    create_oidc_provider
    
    echo ""
    log_info "Step 3/7: Create/Update S3 State Bucket"
    create_state_bucket
    
    echo ""
    log_info "Step 4/7: Create/Update IAM Policies"
    create_plan_policy
    create_apply_policy
    create_secrets_policy
    
    echo ""
    log_info "Step 5/7: Create/Update IAM Roles"
    create_plan_role
    create_apply_role
    
    echo ""
    log_info "Step 6/7: Setup Secrets Manager"
    create_secrets
    
    echo ""
    log_info "Step 7/7: Generate Configuration Files"
    generate_github_vars
    generate_tfvars_config
    
    echo ""
    echo "=========================================="
    echo " Bootstrap Complete!"
    echo "=========================================="
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "This was a DRY-RUN. Run with --apply to make actual changes."
    else
        log_success "All resources created/updated successfully!"
        echo ""
        log_info "Next steps:"
        echo "  1. Review and fill in: ${SCRIPT_DIR}/secrets.json"
        echo "  2. Run again with: ./bootstrap.sh --apply"
        echo "  3. Update GitHub repository variables from: ${SCRIPT_DIR}/github-vars.txt"
        echo "  4. Commit: terraform/prod/terraform.tfvars.config"
        echo "  5. Update GitHub Actions workflows to use new secret fetching"
    fi
    echo ""
}

main "$@"
