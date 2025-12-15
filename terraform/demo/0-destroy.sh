#!/bin/bash
# ========================================
# SCRIPT 0: Terraform Destroy (Clean Slate)
# ========================================
# Run from LOCAL machine in infrastructure/terraform/demo directory
# This resets everything for a fresh demo

set -euo pipefail

echo "=========================================="
echo "Demo Script 0: Destroy All Infrastructure"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will destroy ALL demo infrastructure!"
echo "   - VPC, Subnets, NAT Gateway"
echo "   - Dev Server, Bastion, K8s nodes"
echo "   - RDS databases (Production & Staging)"
echo "   - ALB, NLB, Security Groups"
echo "   - Secrets Manager secrets"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "🗑️  Running terraform destroy..."
terraform destroy -auto-approve

echo ""
echo "=========================================="
echo "✅ Infrastructure destroyed successfully!"
echo "=========================================="
echo ""
echo "To recreate everything, run:"
echo "  ./1-setup-dev-server.sh"
echo ""
