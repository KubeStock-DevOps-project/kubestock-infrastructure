# Kubernetes Base Infrastructure Components

This directory contains base Kubernetes manifests that need to be applied **BEFORE** ArgoCD installation.

These are infrastructure-level components that enable core cluster functionality.

## Components

| Component | Purpose | Required For |
|-----------|---------|--------------|
| AWS Cloud Controller Manager | Node providerID, lifecycle management | EBS CSI, Node auto-registration |
| AWS EBS CSI Driver | Dynamic EBS volume provisioning | StatefulSets, PersistentVolumes |
| StorageClass | Default storage class for PVCs | Database StatefulSets |

## Quick Start

```bash
# Run the bootstrap script
./bootstrap-k8s-base.sh
```

## Manual Installation

```bash
# 1. Apply AWS Cloud Controller Manager (sets providerID on nodes)
kubectl apply -f aws-cloud-controller-manager/

# 2. Apply EBS CSI Driver (from official repo)
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"

# 3. Apply StorageClass
kubectl apply -f storage-classes/

# 4. Verify everything is working
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
kubectl get storageclass
```

## Prerequisites

### 1. IAM Permissions (Already in Terraform)
The node IAM role must have EBS permissions. This is already configured in:
- `infrastructure/terraform/prod/modules/kubernetes/main.tf` - `k8s_controllers` policy

### 2. IMDS Hop Limit
Worker nodes must have `http_put_response_hop_limit >= 2` for containers to access EC2 metadata.

**For new nodes (via ASG):** Already configured in Terraform launch template.

**For existing nodes:** Run manually:
```bash
aws ec2 modify-instance-metadata-options --instance-id <INSTANCE_ID> --http-put-response-hop-limit 2
```

### 3. Node Topology Labels
Nodes must have topology labels for volume scheduling:
- `topology.kubernetes.io/zone`
- `topology.kubernetes.io/region`
- `node.kubernetes.io/instance-type`

The AWS Cloud Controller Manager sets these automatically for new nodes.

For existing nodes, add labels manually:
```bash
kubectl label node <NODE_NAME> \
  topology.kubernetes.io/zone=<AZ> \
  topology.kubernetes.io/region=<REGION> \
  node.kubernetes.io/instance-type=<INSTANCE_TYPE>
```

### 4. Node ProviderID
Nodes must have providerID set in format: `aws:///<AZ>/<INSTANCE_ID>`

For existing nodes without providerID:
```bash
kubectl patch node <NODE_NAME> -p '{"spec":{"providerID":"aws:///<AZ>/<INSTANCE_ID>"}}'
```

## Verification

### Check Node Configuration
```bash
# Verify providerID is set
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'

# Verify topology labels
kubectl get nodes --show-labels | grep topology
```

### Check EBS CSI Driver
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
kubectl logs -n kube-system deployment/ebs-csi-controller -c ebs-plugin --tail=20
```

### Test PVC Provisioning
```bash
# Create test namespace
kubectl create namespace storage-test

# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: storage-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 1Gi
EOF

# Check if PVC is bound
kubectl get pvc -n storage-test

# Cleanup
kubectl delete namespace storage-test
```

## Troubleshooting

### EBS CSI Driver CrashLoopBackOff
1. Check if providerID is set on nodes
2. Check if IMDS hop limit is >= 2
3. Check IAM permissions on node instance profile

### PVC Stuck in Pending
1. Check EBS CSI controller logs: `kubectl logs -n kube-system deployment/ebs-csi-controller -c ebs-plugin`
2. Verify StorageClass exists: `kubectl get storageclass`
3. Check node topology labels

### Node Missing ProviderID
```bash
# Get instance ID from AWS
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=private-ip-address,Values=<NODE_IP>" --query 'Reservations[0].Instances[0].InstanceId' --output text)
AZ=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

# Patch node
kubectl patch node <NODE_NAME> -p "{\"spec\":{\"providerID\":\"aws:///$AZ/$INSTANCE_ID\"}}"
```

## Notes

- These manifests are applied manually or via bootstrap script
- They are NOT managed by ArgoCD to avoid chicken-and-egg dependency issues
- For new cluster setup, run these before installing ArgoCD
- EBS volumes are AZ-specific - pods will be scheduled in the same AZ as their volume
