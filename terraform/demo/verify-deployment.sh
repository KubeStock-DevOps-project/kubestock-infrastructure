#!/bin/bash
# KubeStock Infrastructure - Deployment Verification Script
# Run this after terraform apply completes

set -e

echo "=========================================="
echo "KubeStock Infrastructure - Deployment Verification"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if terraform outputs exist
if ! terraform output > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: Terraform outputs not found. Have you run 'terraform apply'?${NC}"
    exit 1
fi

echo "Checking Terraform outputs..."
echo ""

# Function to check output
check_output() {
    local output_name=$1
    local display_name=$2
    
    if terraform output $output_name > /dev/null 2>&1; then
        local value=$(terraform output -raw $output_name 2>/dev/null || terraform output $output_name)
        echo -e "${GREEN}✓${NC} $display_name: $value"
        return 0
    else
        echo -e "${RED}✗${NC} $display_name: Not found"
        return 1
    fi
}

# Check all critical outputs
echo "=== Network Components ==="
check_output "vpc_id" "VPC ID"
check_output "public_subnet_ids" "Public Subnets"
check_output "private_subnet_ids" "Private Subnets"
check_output "nat_gateway_public_ip" "NAT Gateway IP"
echo ""

echo "=== Compute Components ==="
check_output "bastion_public_ip" "Bastion Public IP"
check_output "control_plane_private_ip" "Control Plane Private IP"
check_output "worker_asg_name" "Worker ASG Name"
echo ""

echo "=== Load Balancer ==="
check_output "nlb_dns_name" "NLB DNS Name"
check_output "k8s_api_endpoint" "K8s API Endpoint"
echo ""

echo "=== Database ==="
check_output "rds_endpoint" "RDS Endpoint"
check_output "rds_username" "RDS Username"
echo ""

echo "=== Cognito ==="
check_output "cognito_user_pool_id" "Cognito User Pool ID"
check_output "cognito_client_id" "Cognito Client ID"
echo ""

# Test connectivity
echo "=========================================="
echo "Testing Connectivity"
echo "=========================================="
echo ""

BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null)

if [ -n "$BASTION_IP" ]; then
    echo "Testing SSH to bastion ($BASTION_IP)..."
    if timeout 5 ssh -i ~/.ssh/kubestock-key -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$BASTION_IP "echo 'Connected'" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Bastion SSH: Accessible"
    else
        echo -e "${YELLOW}⚠${NC} Bastion SSH: Cannot connect (may need to wait for instance to boot)"
    fi
else
    echo -e "${RED}✗${NC} Bastion IP not found"
fi

echo ""

# Check RDS connectivity
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null | cut -d: -f1)
if [ -n "$RDS_ENDPOINT" ]; then
    echo "Testing RDS connectivity ($RDS_ENDPOINT:5432)..."
    if timeout 5 nc -zv $RDS_ENDPOINT 5432 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} RDS: Network accessible"
    else
        echo -e "${YELLOW}⚠${NC} RDS: Not accessible from this machine (expected - RDS is in private subnet)"
    fi
fi

echo ""

# Check NLB
NLB_DNS=$(terraform output -raw nlb_dns_name 2>/dev/null)
if [ -n "$NLB_DNS" ]; then
    echo "Testing NLB connectivity ($NLB_DNS:6443)..."
    if timeout 5 nc -zv $NLB_DNS 6443 > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} NLB Port 6443: Accessible (expected to fail until K8s is installed)"
    else
        echo -e "${YELLOW}⚠${NC} NLB Port 6443: Not accessible (expected - K8s not installed yet)"
    fi
fi

echo ""

# Summary
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""

cat << EOF
Next Steps:

1. SSH to Bastion:
   $(terraform output bastion_ssh_command 2>/dev/null)

2. SSH to Control Plane:
   $(terraform output control_plane_ssh_via_bastion 2>/dev/null)

3. Port Forward to RDS:
   $(terraform output rds_port_forward_command 2>/dev/null)

4. Install Kubernetes on Control Plane
   - Install kubeadm, kubelet, kubectl
   - Initialize cluster with: kubeadm init

5. Configure kubectl locally
   - Copy kubeconfig from control plane
   - Test with: kubectl get nodes

6. Install K8s addons:
   - AWS Load Balancer Controller
   - EBS CSI Driver
   - Cluster Autoscaler

EOF

echo ""
echo -e "${GREEN}Verification complete!${NC}"
echo ""
