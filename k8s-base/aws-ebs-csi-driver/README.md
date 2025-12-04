# AWS EBS CSI Driver

This directory contains instructions for deploying the AWS EBS CSI Driver.

## Installation

The EBS CSI Driver is installed using the official Kubernetes SIG kustomize overlay:

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"
```

## Prerequisites

1. **AWS Cloud Controller Manager** must be deployed first (sets providerID on nodes)
2. **IAM permissions** for EBS operations (already configured in Terraform - `k8s-controllers-policy`)

## Verification

```bash
# Check CSI driver pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check CSIDriver registration
kubectl get csidriver ebs.csi.aws.com
```

## Notes

- This is NOT a manifest file, installation is done via kustomize from upstream
- Version is pinned to release-1.25 for stability
- Update the ref tag to upgrade the driver
