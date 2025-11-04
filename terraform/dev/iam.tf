# ========================================
# IAM ROLE FOR KUBERNETES NODES
# ========================================

resource "aws_iam_role" "k8s_nodes" {
  name = "kubestock-dev-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "kubestock-dev-node-role"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# IAM POLICY FOR KUBERNETES CONTROLLERS
# ========================================

resource "aws_iam_policy" "k8s_controllers" {
  name        = "kubestock-dev-k8s-controllers-policy"
  description = "Permissions for Kubernetes AWS controllers (Cluster Autoscaler, EBS CSI, AWS LB Controller)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Cluster Autoscaler - EC2 permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      # Cluster Autoscaler - AutoScaling permissions
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      },
      # EBS CSI Driver permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      # AWS Load Balancer Controller permissions
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeInternetGateways",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "wafv2:*",
          "shield:*",
          "acm:DescribeCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      # IAM permissions for service accounts
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "elasticloadbalancing.amazonaws.com"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "kubestock-dev-k8s-controllers-policy"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# ATTACH POLICY TO ROLE
# ========================================

resource "aws_iam_role_policy_attachment" "k8s_controllers" {
  role       = aws_iam_role.k8s_nodes.name
  policy_arn = aws_iam_policy.k8s_controllers.arn
}

# Optional: SSM for remote access (useful for debugging)
resource "aws_iam_role_policy_attachment" "k8s_nodes_ssm" {
  role       = aws_iam_role.k8s_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ========================================
# IAM INSTANCE PROFILE
# ========================================

resource "aws_iam_instance_profile" "k8s_nodes" {
  name = "kubestock-dev-node-profile"
  role = aws_iam_role.k8s_nodes.name

  tags = {
    Name        = "kubestock-dev-node-profile"
    Project     = "KubeStock"
    Environment = "dev"
  }
}
