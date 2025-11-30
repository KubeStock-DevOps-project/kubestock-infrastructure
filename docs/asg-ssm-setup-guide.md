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

- **AMI**: \`ami-03507841d11a30bc0\` (kubestock-worker-golden-ami-v4)
- **ASG Capacity**: min=1, desired=2, max=5
- **Token Refresh**: Every 12 hours via Lambda
- **Scaling**: Manual or via Kubernetes Cluster Autoscaler (recommended)

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

### Manual Scaling

\`\`\`bash
# Scale to 3 workers
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name kubestock-workers-asg \
  --desired-capacity 3

# Watch nodes join
watch kubectl get nodes
\`\`\`

### Kubernetes Cluster Autoscaler (Recommended)

AWS CPU-based scaling policies are **NOT used** because they are unaware of Kubernetes constraints (pending pods, resource requests, etc.).

For production, deploy Kubernetes Cluster Autoscaler which:
- Scales based on pending pods
- Respects pod disruption budgets
- Understands node taints/labels
- Performs graceful node draining

\`\`\`yaml
# Deploy cluster-autoscaler (example)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
      - name: cluster-autoscaler
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
        command:
        - ./cluster-autoscaler
        - --cloud-provider=aws
        - --nodes=1:5:kubestock-workers-asg
        - --skip-nodes-with-local-storage=false
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
