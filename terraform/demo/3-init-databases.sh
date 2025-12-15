#!/bin/bash
# ========================================
# SCRIPT 3: Initialize Databases
# ========================================
# Run from DEV SERVER after running script 2

set -euo pipefail

AWS_REGION="ap-south-1"
DB_USER="kubestock_admin"
PROD_DB_NAME="kubestock_prod"
STAGING_DB_NAME="kubestock_staging"

echo "=========================================="
echo "Demo Script 3: Initialize Databases"
echo "=========================================="

# Get database endpoints from AWS RDS
echo ""
echo "📋 Step 1/4: Fetching database endpoints from AWS..."
PROD_DB_HOST=$(aws rds describe-db-instances \
    --db-instance-identifier kubestock-demo-prod-db \
    --region $AWS_REGION \
    --query 'DBInstances[0].Endpoint.Address' --output text)
echo "   Production DB: $PROD_DB_HOST"

STAGING_DB_HOST=$(aws rds describe-db-instances \
    --db-instance-identifier kubestock-demo-staging-db \
    --region $AWS_REGION \
    --query 'DBInstances[0].Endpoint.Address' --output text)
echo "   Staging DB: $STAGING_DB_HOST"

# Get password from AWS Secrets Manager
echo ""
echo "🔑 Step 2/4: Fetching database password from AWS Secrets Manager..."
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "kubestock-demo/production/db" \
    --region $AWS_REGION \
    --query 'SecretString' --output text | jq -r '.DB_PASSWORD')
echo "   Password retrieved ✓"

# Path to init.sql
INIT_SQL="$HOME/kubestock-core/database/init.sql"

if [ ! -f "$INIT_SQL" ]; then
    echo "❌ init.sql not found at $INIT_SQL"
    exit 1
fi

echo "   Using init.sql: $INIT_SQL"

# Install PostgreSQL client if not present
echo ""
echo "📦 Step 3/4: Installing PostgreSQL client..."
sudo apt install -y postgresql-client jq

# Initialize Production Database
echo ""
echo "🗄️  Step 4/4: Initializing databases..."
echo ""
echo "   Initializing PRODUCTION database..."
echo "   Host: $PROD_DB_HOST"
echo "   Database: $PROD_DB_NAME"
PGPASSWORD="$DB_PASSWORD" psql -h "$PROD_DB_HOST" -U "$DB_USER" -d "$PROD_DB_NAME" -f "$INIT_SQL"
echo "   ✅ Production database initialized!"

# Initialize Staging Database
echo ""
echo "   Initializing STAGING database..."
echo "   Host: $STAGING_DB_HOST"
echo "   Database: $STAGING_DB_NAME"
PGPASSWORD="$DB_PASSWORD" psql -h "$STAGING_DB_HOST" -U "$DB_USER" -d "$STAGING_DB_NAME" -f "$INIT_SQL"
echo "   ✅ Staging database initialized!"

echo ""
echo "=========================================="
echo "✅ All databases initialized successfully!"
echo "=========================================="
echo ""
echo "Database endpoints:"
echo "  Production: $PROD_DB_HOST:5432/$PROD_DB_NAME"
echo "  Staging:    $STAGING_DB_HOST:5432/$STAGING_DB_NAME"
echo ""
echo "Next: Deploy ArgoCD and applications"
echo ""
