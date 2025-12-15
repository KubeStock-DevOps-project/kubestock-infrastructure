#!/usr/bin/env bash
# =============================================================================
# KUBESTOCK TERRAFORM BOOTSTRAP SCRIPT (SIMPLIFIED)
# =============================================================================
# This script sets up the AWS infrastructure required to run Terraform:
#   1. GitHub Actions OIDC Provider (if not exists)
#   2. Terraform Plan/Apply IAM Roles with OIDC trust
#   3. Terraform State S3 Bucket (with backup protection)
#
# NOTE: Secrets are now managed entirely by Terraform using lifecycle ignore_changes.
#       No secrets need to be pre-created by this bootstrap script.
#
# REQUIREMENTS:
#   - AWS CLI v2 configured with admin privileges
#   - jq installed
#
# USAGE:
#   ./bootstrap.sh                    # Dry run (shows what would be done)
#   ./bootstrap.sh --apply            # Actually apply changes
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
STATE_BUCKET_REGION="${STATE_BUCKET_REGION:-us-east-1}"

# GitHub Configuration
GITHUB_ORG="KubeStock-DevOps-project"
GITHUB_REPOS=("kubestock-infrastructure" "kubestock-core")

# S3 Buckets
STATE_BUCKET_NAME="${PROJECT_NAME}-terraform-state"

# IAM Names
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
PLAN_ROLE_NAME="${PROJECT_NAME_TITLE}-Terraform-Plan-Role"
APPLY_ROLE_NAME="${PROJECT_NAME_TITLE}-Terraform-Apply-Role"
PLAN_POLICY_NAME="${PROJECT_NAME_TITLE}-Terraform-Plan-Policy"
APPLY_POLICY_NAME="${PROJECT_NAME_TITLE}-Terraform-Apply-Policy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Disable AWS CLI pager
export AWS_PAGER=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
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
    log_info "Checking OIDC provider for GitHub Actions..."
    
    OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &> /dev/null; then
        log_success "OIDC provider already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create OIDC provider for ${OIDC_PROVIDER_URL}"
        return 0
    fi
    
    log_info "Creating OIDC provider..."
    THUMBPRINT=$(echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout 2>/dev/null | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    
    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER_URL}" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$THUMBPRINT"
    
    log_success "OIDC provider created"
}

# =============================================================================
# S3 STATE BUCKET
# =============================================================================

create_state_bucket() {
    log_info "Checking S3 state bucket..."
    
    if aws s3api head-bucket --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION" 2>/dev/null; then
        log_success "State bucket already exists: ${STATE_BUCKET_NAME}"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: ${STATE_BUCKET_NAME}"
        return 0
    fi
    
    log_info "Creating state bucket: ${STATE_BUCKET_NAME}"
    
    if [[ "$STATE_BUCKET_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION"
    else
        aws s3api create-bucket --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION" \
            --create-bucket-configuration LocationConstraint="$STATE_BUCKET_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION" \
        --server-side-encryption-configuration '{
            "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
        }'
    
    # Block public access
    aws s3api put-public-access-block --bucket "$STATE_BUCKET_NAME" --region "$STATE_BUCKET_REGION" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }'
    
    log_success "State bucket created and configured"
}

# =============================================================================
# IAM POLICIES
# =============================================================================

create_plan_policy() {
    log_info "Creating/updating Plan policy..."
    
    POLICY_DOC=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "TerraformStateRead",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${STATE_BUCKET_NAME}",
                "arn:aws:s3:::${STATE_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "TerraformStateLock",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "arn:aws:dynamodb:*:${ACCOUNT_ID}:table/terraform-*"
        },
        {
            "Sid": "ReadAllAWSResources",
            "Effect": "Allow",
            "Action": [
                "acm:Describe*",
                "acm:Get*",
                "acm:List*",
                "autoscaling:Describe*",
                "cloudwatch:Describe*",
                "cloudwatch:Get*",
                "cloudwatch:List*",
                "ec2:Describe*",
                "ecr:Describe*",
                "ecr:Get*",
                "ecr:List*",
                "elasticloadbalancing:Describe*",
                "events:Describe*",
                "events:List*",
                "iam:Get*",
                "iam:List*",
                "kms:Describe*",
                "kms:Get*",
                "kms:List*",
                "lambda:Get*",
                "lambda:List*",
                "logs:Describe*",
                "logs:Get*",
                "logs:List*",
                "rds:Describe*",
                "rds:List*",
                "route53:Get*",
                "route53:List*",
                "s3:Get*",
                "s3:List*",
                "secretsmanager:Describe*",
                "secretsmanager:Get*",
                "secretsmanager:List*",
                "sns:Get*",
                "sns:List*",
                "sqs:Get*",
                "sqs:List*",
                "wafv2:Get*",
                "wafv2:List*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    upsert_policy "$PLAN_POLICY_NAME" "$POLICY_DOC"
}

create_apply_policy() {
    log_info "Creating/updating Apply policy..."
    
    POLICY_DOC=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "TerraformStateFullAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${STATE_BUCKET_NAME}",
                "arn:aws:s3:::${STATE_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "TerraformStateLock",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "arn:aws:dynamodb:*:${ACCOUNT_ID}:table/terraform-*"
        },
        {
            "Sid": "FullAWSAccess",
            "Effect": "Allow",
            "Action": [
                "acm:*",
                "autoscaling:*",
                "cloudwatch:*",
                "ec2:*",
                "ecr:*",
                "elasticloadbalancing:*",
                "events:*",
                "iam:*",
                "kms:*",
                "lambda:*",
                "logs:*",
                "rds:*",
                "route53:*",
                "s3:*",
                "secretsmanager:*",
                "sns:*",
                "sqs:*",
                "wafv2:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    upsert_policy "$APPLY_POLICY_NAME" "$POLICY_DOC"
}

upsert_policy() {
    local policy_name="$1"
    local policy_doc="$2"
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create/update policy: ${policy_name}"
        return 0
    fi
    
    if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
        # Delete old versions first (keep only default)
        VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
        for VERSION in $VERSIONS; do
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" 2>/dev/null || true
        done
        
        # Create new version
        aws iam create-policy-version \
            --policy-arn "$POLICY_ARN" \
            --policy-document "$policy_doc" \
            --set-as-default
        log_success "Policy updated: ${policy_name}"
    else
        aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "$policy_doc"
        log_success "Policy created: ${policy_name}"
    fi
}

# =============================================================================
# IAM ROLES
# =============================================================================

create_role() {
    local role_name="$1"
    local policy_name="$2"
    
    log_info "Creating/updating role: ${role_name}"
    
    # Build trust policy with all repos
    local conditions=""
    for i in "${!GITHUB_REPOS[@]}"; do
        if [[ $i -gt 0 ]]; then
            conditions+=","
        fi
        conditions+="\"repo:${GITHUB_ORG}/${GITHUB_REPOS[$i]}:*\""
    done
    
    TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER_URL}:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "${OIDC_PROVIDER_URL}:sub": [${conditions}]
                }
            }
        }
    ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create/update role: ${role_name}"
        return 0
    fi
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        aws iam update-assume-role-policy --role-name "$role_name" --policy-document "$TRUST_POLICY"
        log_success "Role trust policy updated: ${role_name}"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --description "Terraform ${policy_name} role for GitHub Actions OIDC"
        log_success "Role created: ${role_name}"
    fi
    
    # Attach policy
    aws iam attach-role-policy --role-name "$role_name" --policy-arn "$POLICY_ARN" 2>/dev/null || true
    log_success "Policy attached to role: ${role_name}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo " KUBESTOCK TERRAFORM BOOTSTRAP"
    echo "=============================================="
    echo ""
    
    DRY_RUN="true"
    
    for arg in "$@"; do
        case $arg in
            --apply)
                DRY_RUN="false"
                log_warn "APPLY MODE - Changes will be made!"
                ;;
        esac
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        log_info "Run with --apply to make actual changes"
        echo ""
    fi
    
    check_dependencies
    
    echo ""
    log_info "Step 1: OIDC Provider"
    create_oidc_provider
    
    echo ""
    log_info "Step 2: S3 State Bucket"
    create_state_bucket
    
    echo ""
    log_info "Step 3: IAM Policies"
    create_plan_policy
    create_apply_policy
    
    echo ""
    log_info "Step 4: IAM Roles"
    create_role "$PLAN_ROLE_NAME" "$PLAN_POLICY_NAME"
    create_role "$APPLY_ROLE_NAME" "$APPLY_POLICY_NAME"
    
    echo ""
    echo "=============================================="
    log_success "Bootstrap complete!"
    echo "=============================================="
    echo ""
    log_info "Role ARNs for GitHub Actions:"
    echo "  Plan Role:  arn:aws:iam::${ACCOUNT_ID}:role/${PLAN_ROLE_NAME}"
    echo "  Apply Role: arn:aws:iam::${ACCOUNT_ID}:role/${APPLY_ROLE_NAME}"
    echo ""
    log_info "Add these as GitHub repository variables:"
    echo "  AWS_PLAN_ROLE_ARN"
    echo "  AWS_APPLY_ROLE_ARN"
    echo ""
    log_info "Secrets are now managed by Terraform with lifecycle { ignore_changes }"
    log_info "After 'terraform apply', update secret values via AWS Console."
    echo ""
}

main "$@"
