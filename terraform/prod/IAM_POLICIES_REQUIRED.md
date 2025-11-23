# AWS IAM Policies Required for Terraform Operations

This document outlines the AWS IAM policies required for running Terraform operations on the KubeStock infrastructure project.

## Summary

- **Terraform Plan**: Read-only permissions to validate and preview infrastructure changes
- **Terraform Apply**: Read + Write permissions to create, modify, and delete AWS resources

---

## 1. Policies for `terraform plan` (Read-Only)

These permissions allow Terraform to read existing infrastructure state and validate the configuration without making any changes.

### Required AWS Managed Policies:
- None (use custom policy below)

### Custom Policy: `KubeStock-Terraform-Plan-Policy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2ReadOnly",
            "Effect": "Allow",
            "Action": [
                "ec2:Describe*",
                "ec2:Get*",
                "ec2:List*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VPCReadOnly",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeRouteTables",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeNatGateways",
                "ec2:DescribeAddresses",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSecurityGroupRules",
                "ec2:DescribeNetworkAcls",
                "ec2:DescribeNetworkInterfaces"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ELBReadOnly",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:Describe*",
                "elasticloadbalancing:Get*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAMReadOnly",
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:GetRolePolicy",
                "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "iam:GetInstanceProfile",
                "iam:ListAttachedRolePolicies",
                "iam:ListRolePolicies",
                "iam:ListInstanceProfiles",
                "iam:ListInstanceProfilesForRole",
                "iam:ListPolicyVersions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AutoScalingReadOnly",
            "Effect": "Allow",
            "Action": [
                "autoscaling:Describe*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3BackendAccess",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::kubestock-terraform-state",
                "arn:aws:s3:::kubestock-terraform-state/*"
            ]
        },
        {
            "Sid": "DynamoDBStateLock",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:DescribeTable"
            ],
            "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
        }
    ]
}
```

---

## 2. Policies for `terraform apply` (Read + Write)

These permissions allow Terraform to create, modify, and delete AWS resources.

### Required AWS Managed Policies:
- None (use custom policy below for better security)

### Custom Policy: `KubeStock-Terraform-Apply-Policy`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2FullAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:Get*",
        "ec2:List*",
        "ec2:RunInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:RebootInstances",
        "ec2:ModifyInstanceAttribute",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:CreateKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:ImportKeyPair",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPCFullAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:ReplaceRouteTableAssociation",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:ModifySecurityGroupRules",
        "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
        "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:DetachNetworkInterface"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ELBFullAccess",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags"
      ],
      "Resource": [
        "arn:aws:iam::*:role/kubestock-*"
      ]
    },
    {
      "Sid": "IAMPolicyManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:ListPolicyVersions",
        "iam:SetDefaultPolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": [
        "arn:aws:iam::*:policy/kubestock-*"
      ]
    },
    {
      "Sid": "IAMInstanceProfileManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:ListInstanceProfilesForRole",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::*:instance-profile/kubestock-*"
      ]
    },
    {
      "Sid": "IAMServiceLinkedRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": [
            "elasticloadbalancing.amazonaws.com",
            "autoscaling.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/kubestock-*"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AutoScalingFullAccess",
      "Effect": "Allow",
      "Action": [
        "autoscaling:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3BackendFullAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion"
      ],
      "Resource": [
        "arn:aws:s3:::kubestock-terraform-state",
        "arn:aws:s3:::kubestock-terraform-state/*"
      ]
    },
    {
      "Sid": "SSMParameterStore",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/kubestock/*"
    }
  ]
}
```

---

## 3. Additional Recommendations

### Create Separate IAM Users/Roles

1. **For Planning/Review**: Create a role with only the Plan policy for CI/CD pipelines or junior team members
2. **For Deployment**: Create a role with Apply policy for senior engineers or automated deployment systems

### Using with AWS CLI

```bash
# Configure AWS profile with appropriate credentials
aws configure --profile kubestock-terraform

# Export profile for Terraform usage
export AWS_PROFILE=kubestock-terraform

# Run Terraform commands
terraform plan
terraform apply
```

### Using with IAM Roles (Recommended for CI/CD)

```bash
# Assume the role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/KubeStock-Terraform-Role \
  --role-session-name terraform-session

# Use the temporary credentials
export AWS_ACCESS_KEY_ID=<access-key>
export AWS_SECRET_ACCESS_KEY=<secret-key>
export AWS_SESSION_TOKEN=<session-token>
```

---

## 4. S3 Backend Setup (One-Time)

Before running Terraform, ensure the S3 backend is configured:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket kubestock-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket kubestock-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket kubestock-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket kubestock-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

---

## 5. Resources Created by This Terraform Configuration

- **VPC**: 1 VPC with DNS support
- **Subnets**: 3 public + 3 private subnets across 3 AZs
- **Internet Gateway**: 1 IGW for public internet access
- **NAT Gateway**: 1 NAT Gateway with Elastic IP
- **Route Tables**: 1 public + 3 private route tables
- **Security Groups**: 6 security groups (bastion, dev-server, k8s-common, control-plane, workers, nlb-api)
- **EC2 Instances**: 
  - 1 Bastion host (t3.micro)
  - 1 Dev server (t3.medium)
  - 1 Control plane (t3.medium)
  - 2 Worker nodes (t3.medium)
- **Elastic IPs**: 2 (bastion + NAT Gateway)
- **Key Pair**: 1 SSH key pair
- **Network Load Balancer**: 1 internal NLB for K8s API
- **Target Group**: 1 target group for K8s API (port 6443)
- **IAM Role**: 1 role for K8s nodes
- **IAM Policy**: 1 custom policy for K8s controllers
- **IAM Instance Profile**: 1 instance profile for K8s nodes

---

## 6. Cost Estimate

Monthly costs (based on us-east-1 pricing):

- EC2 instances (always on): ~$150-200/month
- NAT Gateway: ~$45/month
- EBS volumes: ~$10-20/month
- Data transfer: Variable
- **Total**: ~$200-270/month (excluding data transfer)

**Note**: The dev server can be stopped when not in use to save ~$30-40/month.
