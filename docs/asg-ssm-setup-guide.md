# Auto Scaling Group (ASG) with SSM Setup Guide

## Overview

This guide explains how to set up an Auto Scaling Group (ASG) for Kubernetes worker nodes that automatically join the cluster using AWS Systems Manager (SSM) Parameter Store for secure token management.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS VPC                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Private Subnets                         │  │
│  │                                                            │  │
│  │  ┌─────────────┐      ┌─────────────────────────────────┐│  │
│  │  │ Control     │      │  Auto Scaling Group             ││  │
│  │  │ Plane       │◄────►│  ┌─────────┐  ┌─────────┐      ││  │
│  │  │ (master-1)  │      │  │Worker N │  │Worker N+1│ ... ││  │
│  │  └─────────────┘      │  └─────────┘  └─────────┘      ││  │
│  │         ▲             └─────────────────────────────────┘│  │
│  │         │                            │                    │  │
│  └─────────┼────────────────────────────┼────────────────────┘  │
│            │                            │                        │
│  ┌─────────┴────────┐         ┌────────┴─────────┐             │
│  │ SSM Parameter    │         │ Lambda           │             │
│  │ Store            │◄────────│ (Token Refresh)  │             │
│  │ /kubestock/*     │         │                  │             │
│  └──────────────────┘         └──────────────────┘             │
│            ▲                           │                        │
│            │         EventBridge       │                        │
│            └───────── (12h) ───────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **Golden AMI** | Pre-configured Ubuntu 22.04 with Kubernetes binaries (v1.34.1), containerd, join scripts |
| **Launch Template** | Defines instance config, AMI, security groups, user-data |
| **Auto Scaling Group** | Manages worker instances across 2 AZs (ap-south-1b, ap-south-1c) |
| **SSM Parameters** | Stores join-token (SecureString) and ca-cert-hash (String) |
| **Lambda Function** | Refreshes token every 12 hours via SSM Run Command |
| **EventBridge Rule** | Triggers Lambda on schedule |

## Current Configuration

- **AMI**: \`ami-03a1d146e75612e44\` (kubestock-worker-golden-ami-v5 - with provider ID and topology labels)
- **ASG Capacity**: min=1, desired=2, max=8
- **Token Refresh**: Every 12 hours via Lambda
- **Scaling**: Kubernetes Cluster Autoscaler (automated)

## SSM Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| \`/kubestock/join-token\` | SecureString | Kubeadm join token (refreshed every 12h) |
| \`/kubestock/ca-cert-hash\` | String | CA certificate hash (static) |

### View Parameters

\`\`\`bash
# Get current token
aws ssm get-parameter --name /kubestock/join-token --with-decryption --query 'Parameter.Value' --output text

# Get CA hash
aws ssm get-parameter --name /kubestock/ca-cert-hash --query 'Parameter.Value' --output text
\`\`\`

## Token Rotation

Tokens are automatically refreshed by a Lambda function every 12 hours.

### How It Works

1. EventBridge triggers Lambda every 12 hours
2. Lambda finds control plane instance by tag \`Name=kubestock-control-plane\`
3. Lambda executes \`kubeadm token create\` via SSM Run Command
4. Lambda updates \`/kubestock/join-token\` SSM parameter

### Manual Token Refresh

\`\`\`bash
# Invoke Lambda manually
aws lambda invoke \
  --function-name kubestock-refresh-join-token \
  --log-type Tail \
  --query 'LogResult' --output text \
  /tmp/lambda-response.json | base64 -d

# Check response
cat /tmp/lambda-response.json
\`\`\`

### View Lambda Logs

\`\`\`bash
aws logs tail /aws/lambda/kubestock-refresh-join-token --follow
\`\`\`

## Scaling

### Kubernetes Cluster Autoscaler (Automated)

Cluster Autoscaler is deployed via GitOps and automatically manages node scaling. AWS CPU-based scaling policies are **NOT used** because they are unaware of Kubernetes constraints (pending pods, resource requests, etc.).

Cluster Autoscaler provides:
- **Scale Up**: Automatically adds nodes when pods can't be scheduled
- **Scale Down**: Removes underutilized nodes (below 50% utilization for 10+ minutes)
- Respects pod disruption budgets and gracefully drains nodes
- Understands node taints/labels and pod affinity
- Auto-discovers ASGs via tags (\`k8s.io/cluster-autoscaler/enabled\`, \`k8s.io/cluster-autoscaler/kubestock\`)

#### Configuration

- **ASG Discovery**: Automatic via tags
- **Min nodes**: 1
- **Max nodes**: 8
- **Scale-down threshold**: 50% utilization
- **Scale-down delay**: 10 minutes after scale-up
- **Expander strategy**: least-waste

#### Check Status

\`\`\`bash
# View autoscaler pod
kubectl get pods -n cluster-autoscaler

# View logs
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f

# View status ConfigMap
kubectl get cm cluster-autoscaler-status -n cluster-autoscaler -o yaml

# View current nodes
kubectl get nodes
\`\`\`

#### Testing Scale Up

\`\`\`bash
# Deploy resource-intensive workload
kubectl create deployment scale-test --image=nginx --replicas=20
kubectl set resources deployment scale-test --requests=cpu=500m,memory=512Mi

# Watch nodes scale up (usually within 2-3 minutes)
watch kubectl get nodes
\`\`\`

#### Testing Scale Down

\`\`\`bash
# Delete workload
kubectl delete deployment scale-test

# Nodes will scale down after 10+ minutes of being underutilized
watch kubectl get nodes
\`\`\`

### Manual Scaling (Not Recommended)

For emergency situations only. Cluster Autoscaler will override manual changes:

\`\`\`bash
# Scale to 3 workers
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name kubestock-workers-asg \
  --desired-capacity 3

# Watch nodes join
watch kubectl get nodes
\`\`\`

## Node Join Process

When a new ASG instance launches:

1. **User-data** runs with 10s delay for networking
2. **join-cluster.sh --ssm** executes:
   - Configures kubelet with instance IP/ID
   - Fetches token and CA hash from SSM
   - Starts nginx-proxy for API server access
   - Runs \`kubeadm join\`
3. Node registers with cluster as \`worker-<instance-id>\`

### Join Script Logs

\`\`\`bash
# SSH to worker and check logs
ssh -i ~/.ssh/kubestock-key ubuntu@<worker-ip> "cat /var/log/user-data.log"
ssh -i ~/.ssh/kubestock-key ubuntu@<worker-ip> "cat /var/log/k8s-join.log"
\`\`\`

## Troubleshooting

### Node Not Joining

1. **Check SSM parameters exist and are valid**:
   \`\`\`bash
   aws ssm get-parameter --name /kubestock/join-token --with-decryption
   aws ssm get-parameter --name /kubestock/ca-cert-hash
   \`\`\`

2. **Check IAM role has SSM permissions**:
   \`\`\`bash
   # From the worker instance
   aws sts get-caller-identity
   aws ssm get-parameter --name /kubestock/join-token
   \`\`\`

3. **Check user-data execution**:
   \`\`\`bash
   ssh ubuntu@<worker-ip> "cat /var/log/user-data.log"
   ssh ubuntu@<worker-ip> "journalctl -u kubelet"
   \`\`\`

4. **Check nginx-proxy**:
   \`\`\`bash
   ssh ubuntu@<worker-ip> "nerdctl ps | grep nginx-proxy"
   ssh ubuntu@<worker-ip> "curl -sk https://127.0.0.1:6443/version"
   \`\`\`

### Token Expired

If Lambda fails or token expires:

\`\`\`bash
# Manual token creation on control plane
ssh -i ~/.ssh/kubestock-key ubuntu@10.0.10.21 "sudo kubeadm token create"

# Update SSM manually
aws ssm put-parameter --name /kubestock/join-token \
  --value "<new-token>" --type SecureString --overwrite
\`\`\`

### Lambda Failures

\`\`\`bash
# Check Lambda logs
aws logs tail /aws/lambda/kubestock-refresh-join-token --since 1h

# Test Lambda manually
aws lambda invoke --function-name kubestock-refresh-join-token /tmp/out.json
cat /tmp/out.json
\`\`\`

## Manual Node Join (Testing/Debugging)

For testing the AMI or manually joining a node without ASG:

### 1. Get Join Credentials

\`\`\`bash
# Get current token
TOKEN=\$(aws ssm get-parameter --name /kubestock/join-token --with-decryption --query 'Parameter.Value' --output text)

# Get CA hash
CA_HASH=\$(aws ssm get-parameter --name /kubestock/ca-cert-hash --query 'Parameter.Value' --output text)

echo "Token: \$TOKEN"
echo "CA Hash: \$CA_HASH"
\`\`\`

### 2. Run Join Script on Worker

\`\`\`bash
# Using SSM (recommended)
ssh -i ~/.ssh/kubestock-key ubuntu@<worker-ip> \
  "sudo /usr/local/bin/join-cluster.sh --ssm"

# Or with explicit token
ssh -i ~/.ssh/kubestock-key ubuntu@<worker-ip> \
  "sudo /usr/local/bin/join-cluster.sh --token \$TOKEN --ca-cert-hash sha256:\$CA_HASH"
\`\`\`

## Infrastructure Files

| File | Description |
|------|-------------|
| \`terraform/prod/asg.tf\` | ASG and Launch Template configuration |
| \`terraform/prod/lambda.tf\` | Token refresh Lambda function |
| \`terraform/prod/lambda/refresh_token/index.py\` | Lambda Python code |
| \`terraform/prod/cluster-iam.tf\` | IAM roles for nodes and Lambda |
| \`terraform/prod/variables.tf\` | AMI ID and ASG capacity settings |
| \`scripts/ami/join-cluster.sh\` | Node join orchestration script |

## Security Considerations

1. **Token Rotation**: Tokens auto-expire in 24h; Lambda refreshes every 12h
2. **SSM Encryption**: Join token stored as SecureString (KMS encrypted)
3. **IAM Least Privilege**: Nodes only have read access to \`/kubestock/*\` parameters
4. **IMDSv2**: Instance metadata requires token (hop limit = 1)
5. **Private Subnets**: All worker nodes in private subnets

## Cost Optimization

1. **Cluster Autoscaler**: Scale based on actual pod demand
2. **Spot Instances**: Use for non-critical workloads (configure in launch template)
3. **Right-sizing**: Monitor and adjust instance types based on usage
4. **Min Capacity**: Set to 1-2 for non-production environments
