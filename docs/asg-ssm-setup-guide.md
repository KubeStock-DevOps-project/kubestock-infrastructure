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
│  │ SSM Parameter    │         │ EC2 Instance     │             │
│  │ Store            │◄────────│ Metadata         │             │
│  │ /kubestock/*     │         │                  │             │
│  └──────────────────┘         └──────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. Golden AMI created (see `golden-ami-build-guide.md`)
2. IAM role for worker nodes with SSM read permissions
3. VPC and subnets configured
4. Control plane running and accessible

## Step 1: Create SSM Parameters

Store the cluster join information securely in SSM Parameter Store:

```bash
# Get the CA certificate hash (this is static, doesn't expire)
CERT_HASH=$(ssh -i ~/.ssh/kubestock-key ubuntu@10.0.10.21 \
  "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
   openssl rsa -pubin -outform der 2>/dev/null | \
   openssl dgst -sha256 -hex | sed 's/^.* //'")

# Create SSM parameter for CA hash (String, no encryption needed)
aws ssm put-parameter \
  --name "/kubestock/ca-cert-hash" \
  --value "$CERT_HASH" \
  --type "String" \
  --description "Kubernetes cluster CA certificate hash" \
  --overwrite

# The join token needs to be refreshed periodically (tokens expire in 24h)
# Create initial token
JOIN_TOKEN=$(ssh -i ~/.ssh/kubestock-key ubuntu@10.0.10.21 \
  "sudo kubeadm token create")

# Create SSM parameter for token (SecureString for security)
aws ssm put-parameter \
  --name "/kubestock/join-token" \
  --value "$JOIN_TOKEN" \
  --type "SecureString" \
  --description "Kubernetes cluster join token (expires in 24h)" \
  --overwrite
```

## Step 2: Create IAM Role for ASG Nodes

Add SSM permissions to the existing k8s-nodes IAM role:

```hcl
# terraform/prod/iam.tf - Add to existing policy

# SSM Parameter Store read access for join tokens
resource "aws_iam_role_policy" "k8s_nodes_ssm" {
  name = "k8s-nodes-ssm-policy"
  role = aws_iam_role.k8s_nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/kubestock/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}
```

## Step 3: Create Launch Template

```hcl
# terraform/prod/asg.tf

resource "aws_launch_template" "k8s_worker" {
  name_prefix   = "kubestock-worker-"
  image_id      = "ami-09d8ae7c9b76bc3ee"  # Golden AMI
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_nodes.name
  }

  key_name = aws_key_pair.kubestock.key_name

  vpc_security_group_ids = [
    aws_security_group.workers.id,
    aws_security_group.k8s_common.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    
    # Log everything
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "Starting worker node initialization at $(date)"
    
    # Wait for cloud-init to complete
    cloud-init status --wait
    
    # Run the cluster join script
    /usr/local/bin/join-cluster.sh
    
    echo "Worker node initialization complete at $(date)"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                              = "kubestock-worker-asg"
      Role                              = "worker"
      "kubernetes.io/cluster/kubestock" = "owned"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

## Step 4: Create Auto Scaling Group

```hcl
# terraform/prod/asg.tf (continued)

resource "aws_autoscaling_group" "k8s_workers" {
  name                = "kubestock-workers-asg"
  desired_capacity    = 2
  min_size            = 1
  max_size            = 10
  vpc_zone_identifier = [aws_subnet.private[1].id, aws_subnet.private[2].id]
  
  launch_template {
    id      = aws_launch_template.k8s_worker.id
    version = "$Latest"
  }

  # Health checks
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "kubestock-worker-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/kubestock"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

## Step 5: Token Refresh Automation

Since kubeadm tokens expire after 24 hours, automate token refresh:

### Option A: Lambda Function

```hcl
# terraform/prod/lambda.tf

resource "aws_lambda_function" "refresh_k8s_token" {
  filename         = "lambda/refresh_token.zip"
  function_name    = "kubestock-refresh-join-token"
  role            = aws_iam_role.lambda_token_refresh.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      CONTROL_PLANE_IP = "10.0.10.21"
      SSM_PARAM_NAME   = "/kubestock/join-token"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private[0].id]
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_cloudwatch_event_rule" "token_refresh_schedule" {
  name                = "kubestock-token-refresh"
  description         = "Refresh K8s join token every 12 hours"
  schedule_expression = "rate(12 hours)"
}

resource "aws_cloudwatch_event_target" "token_refresh" {
  rule      = aws_cloudwatch_event_rule.token_refresh_schedule.name
  target_id = "RefreshToken"
  arn       = aws_lambda_function.refresh_k8s_token.arn
}
```

### Option B: SSM Run Command (Simpler)

Run on control plane periodically via cron or SSM:

```bash
#!/bin/bash
# /usr/local/bin/refresh-join-token.sh (on control plane)

TOKEN=$(kubeadm token create)
aws ssm put-parameter \
  --name "/kubestock/join-token" \
  --value "$TOKEN" \
  --type "SecureString" \
  --overwrite

echo "Token refreshed at $(date)"
```

Add to crontab on control plane:
```bash
# Refresh token every 12 hours
0 */12 * * * /usr/local/bin/refresh-join-token.sh >> /var/log/token-refresh.log 2>&1
```

## Step 6: Scaling Policies (Optional)

### CPU-Based Scaling

```hcl
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "kubestock-scale-up"
  autoscaling_group_name = aws_autoscaling_group.k8s_workers.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown              = 300
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "kubestock-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.k8s_workers.name
  }
}
```

### Kubernetes Cluster Autoscaler (Recommended)

For better integration, use the Kubernetes Cluster Autoscaler:

```yaml
# Deploy cluster-autoscaler in the cluster
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
      containers:
      - name: cluster-autoscaler
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
        command:
        - ./cluster-autoscaler
        - --v=4
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --nodes=1:10:kubestock-workers-asg
```

## Verification

### Test ASG Launch

1. Set ASG desired capacity to trigger new instance:
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name kubestock-workers-asg \
  --desired-capacity 3
```

2. Watch for new node:
```bash
watch kubectl get nodes
```

3. Check user-data logs on new instance:
```bash
ssh ubuntu@<new-instance-ip> "cat /var/log/user-data.log"
```

### Verify Node Health

```bash
# Check node status
kubectl get nodes -o wide

# Check pods on new node
kubectl get pods -A --field-selector spec.nodeName=<new-node-name>

# Describe node
kubectl describe node <new-node-name>
```

## Node Draining on Scale-Down

ASG will terminate instances directly. For graceful shutdown:

### Option A: ASG Lifecycle Hooks

```hcl
resource "aws_autoscaling_lifecycle_hook" "drain_nodes" {
  name                   = "kubestock-drain-node"
  autoscaling_group_name = aws_autoscaling_group.k8s_workers.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}
```

Then use Lambda/SSM to drain nodes before termination.

### Option B: Node Problem Detector + Descheduler

Deploy these components to proactively move pods off unhealthy nodes.

## Troubleshooting

### Node not joining

1. Check SSM parameters exist:
```bash
aws ssm get-parameter --name /kubestock/join-token --with-decryption
aws ssm get-parameter --name /kubestock/ca-cert-hash
```

2. Check IAM role has SSM permissions:
```bash
aws sts get-caller-identity  # From the instance
aws ssm get-parameter --name /kubestock/join-token  # Should work
```

3. Check user-data execution:
```bash
cat /var/log/user-data.log
cat /var/log/k8s-join.log
journalctl -u kubelet
```

### Token expired

```bash
# On control plane, create new token
sudo kubeadm token create

# Update SSM
aws ssm put-parameter --name /kubestock/join-token \
  --value "<new-token>" --type SecureString --overwrite
```

### API server unreachable

```bash
# Check nginx-proxy
nerdctl ps | grep nginx-proxy
curl -sk https://127.0.0.1:6443/version

# Check security groups allow 6443 from workers to control plane
```

## Security Considerations

1. **Token Rotation**: Tokens expire in 24h; automate refresh
2. **SSM Encryption**: Use SecureString for tokens
3. **IAM Least Privilege**: Only grant SSM read access for specific parameters
4. **Network Security**: Control plane port 6443 only accessible from private subnets
5. **IMDSv2**: Use instance metadata v2 for better security

## Cost Optimization

1. Use Spot Instances for worker ASG (with appropriate pod disruption budgets)
2. Right-size instances based on workload
3. Use cluster autoscaler for demand-based scaling
4. Set minimum capacity to 1-2 for non-production environments
