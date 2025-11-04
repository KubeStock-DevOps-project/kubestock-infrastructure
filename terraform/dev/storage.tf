# ========================================
# STORAGE RESOURCES
# ========================================
# This file is intentionally empty.
# S3 buckets can be created on-demand when needed for the application.
# For the lean KubeStock infrastructure, we avoid creating unused resources.
# Storage needs can be addressed through:
# - EBS volumes (handled by EBS CSI driver in Kubernetes)
# - Object storage (S3 buckets created separately when required)
