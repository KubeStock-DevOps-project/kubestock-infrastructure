# Kubernetes Cluster Autoscaler Setup Guide

## Overview

This guide explains how to deploy and manage the Kubernetes Cluster Autoscaler for automatic node scaling in the KubeStock cluster.

## What is Cluster Autoscaler?

Cluster Autoscaler automatically adjusts the number of nodes in your cluster based on pod resource demands. Unlike AWS Auto Scaling policies that scale based on CPU/memory metrics, Cluster Autoscaler is Kubernetes-aware and makes intelligent decisions based on:

- **Pending pods** that can't be scheduled
- **Node utilization** and resource availability
- **Pod Disruption Budgets** and pod affinity rules
- **Node taints and labels**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Control Plane Node                                 │    │
│  │  ┌──────────────────────────────────────────────┐  │    │
│  │  │  Cluster Autoscaler Pod                      │  │    │
│  │  │  - Monitors pending pods                     │  │    │
│  │  │  - Checks node utilization                   │  │    │
│  │  │  - Makes scaling decisions                   │  │    │
│  │  └──────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────┘    │
│            │                              │                  │
│            │ Scale Up                     │ Scale Down      │
│            ▼                              ▼                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              AWS Auto Scaling Group                  │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  (1-8)     │   │
│  │  │Worker-1 │  │Worker-2 │  │Worker-N │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Deployment

### Prerequisites

1. **Terraform ASG Configuration** (Already configured):
   - ASG with tags: `k8s.io/cluster-autoscaler/enabled=true`, `k8s.io/cluster-autoscaler/kubestock=owned`
   - IAM role with Cluster Autoscaler permissions
   - Max capacity: 8 nodes

2. **ArgoCD** installed and configured

### Deploy via GitOps

The Cluster Autoscaler is deployed automatically via ArgoCD:

```bash
# Apply the ArgoCD application
kubectl apply -f gitops/apps/cluster-autoscaler.yaml

# Verify deployment
kubectl get application -n argocd cluster-autoscaler

# Check the autoscaler pod
kubectl get pods -n cluster-autoscaler
```

## Configuration

### Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Min nodes** | 1 | Minimum worker nodes |
| **Max nodes** | 8 | Maximum worker nodes |
| **Scale-down enabled** | true | Allow removing nodes |
| **Scale-down unneeded time** | 10m | Idle time before scale-down |
| **Scale-down threshold** | 0.5 | 50% utilization threshold |
| **Scale-down delay after add** | 10m | Prevents thrashing after scale-up |
| **Scale-down delay after failure** | 3m | Delay after failed scale-down |
| **Max node provision time** | 15m | Timeout for new nodes |
| **Expander** | least-waste | Choose ASG with least waste |

### Modifying Configuration

To adjust scaling parameters, edit [gitops/base/cluster-autoscaler/deployment.yaml](../gitops/base/cluster-autoscaler/deployment.yaml):

```yaml
command:
  - ./cluster-autoscaler
  - --scale-down-unneeded-time=10m      # Change idle time
  - --scale-down-utilization-threshold=0.5  # Change threshold
  - --scale-down-delay-after-add=10m    # Change delay
```

Commit and push changes - ArgoCD will automatically sync.

## Operations

### Check Status

```bash
# View autoscaler pod status
kubectl get pods -n cluster-autoscaler

# View logs (real-time)
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f

# View status ConfigMap
kubectl get cm cluster-autoscaler-status -n cluster-autoscaler -o yaml

# Check current nodes
kubectl get nodes
```

### Monitoring

Prometheus metrics are exposed on port 8085:

```bash
# Port-forward to view metrics
kubectl port-forward -n cluster-autoscaler svc/cluster-autoscaler 8085:8085

# Access metrics
curl http://localhost:8085/metrics
```

**Key Metrics:**
- `cluster_autoscaler_nodes_count` - Current node count by state
- `cluster_autoscaler_unschedulable_pods_count` - Pods waiting for resources
- `cluster_autoscaler_scaled_up_nodes_total` - Total scale-up events
- `cluster_autoscaler_scaled_down_nodes_total` - Total scale-down events
- `cluster_autoscaler_failed_scale_ups_total` - Failed scale attempts

### Testing

#### Test Scale-Up

Create a workload that requires more resources:

```bash
# Deploy resource-intensive pods
kubectl create deployment scale-test --image=nginx --replicas=20
kubectl set resources deployment scale-test --requests=cpu=500m,memory=512Mi

# Watch autoscaler logs
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f

# Watch nodes appear (usually 2-3 minutes)
watch kubectl get nodes
```

Expected behavior:
1. Pods enter `Pending` state (insufficient resources)
2. Autoscaler detects unschedulable pods
3. ASG desired capacity increases
4. New nodes join the cluster
5. Pods get scheduled

#### Test Scale-Down

Remove the test workload:

```bash
# Delete workload
kubectl delete deployment scale-test

# Watch autoscaler logs
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f

# Nodes will be removed after 10+ minutes of idle time
watch kubectl get nodes
```

Expected behavior:
1. Node utilization drops below 50%
2. After 10 minutes, autoscaler marks node as "unneeded"
3. Node is cordoned and drained gracefully
4. ASG desired capacity decreases
5. Node is terminated

## Troubleshooting

### Scale-Up Not Working

**Symptoms**: Pods remain in `Pending` state, nodes don't increase

**Check:**

1. **Verify max capacity not reached:**
   ```bash
   kubectl get nodes | wc -l
   # Should be less than 8 (max capacity)
   ```

2. **Check autoscaler logs:**
   ```bash
   kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f
   # Look for errors or "scale_up" events
   ```

3. **Verify IAM permissions:**
   ```bash
   # SSH to control plane and check
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names kubestock-workers-asg
   ```

4. **Check ASG tags:**
   ```bash
   aws autoscaling describe-tags \
     --filters "Name=auto-scaling-group,Values=kubestock-workers-asg"
   # Should include k8s.io/cluster-autoscaler/enabled=true
   ```

5. **Verify pod resource requests:**
   ```bash
   kubectl describe pod <pending-pod-name>
   # Ensure resources.requests are defined
   ```

### Scale-Down Not Working

**Symptoms**: Idle nodes remain in the cluster

**Check:**

1. **Check node utilization:**
   ```bash
   kubectl top nodes
   # Should show nodes below 50% utilization
   ```

2. **Check autoscaler logs:**
   ```bash
   kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler -f
   # Look for "scale_down" events or reasons for blocking
   ```

3. **Check for blocking pods:**
   ```bash
   # Pods with local storage or no controller
   kubectl get pods --all-namespaces -o wide
   ```

4. **Check PodDisruptionBudgets:**
   ```bash
   kubectl get pdb --all-namespaces
   # PDBs can block draining
   ```

5. **Verify scale-down is enabled:**
   ```bash
   kubectl get deployment -n cluster-autoscaler cluster-autoscaler -o yaml | grep scale-down-enabled
   ```

### Thrashing (Rapid Scale Up/Down)

**Symptoms**: Nodes constantly being added and removed

**Solutions:**

1. **Increase scale-down delay:**
   ```yaml
   - --scale-down-delay-after-add=20m  # Increase from 10m
   ```

2. **Increase unneeded time:**
   ```yaml
   - --scale-down-unneeded-time=15m  # Increase from 10m
   ```

3. **Adjust utilization threshold:**
   ```yaml
   - --scale-down-utilization-threshold=0.3  # Lower from 0.5
   ```

4. **Review pod resource requests:**
   - Ensure they match actual usage
   - Avoid over-requesting resources

### Node Fails to Join After Scale-Up

**Symptoms**: ASG instance created but node doesn't appear in cluster

**Check:**

1. **Verify SSM parameters:**
   ```bash
   aws ssm get-parameter --name /kubestock/join-token --with-decryption
   aws ssm get-parameter --name /kubestock/ca-cert-hash
   ```

2. **Check instance user-data logs:**
   ```bash
   # Get instance ID from AWS console
   aws ssm start-session --target <instance-id>
   sudo cat /var/log/user-data.log
   sudo cat /var/log/k8s-join.log
   ```

3. **Check kubelet status:**
   ```bash
   sudo systemctl status kubelet
   sudo journalctl -u kubelet -f
   ```

See [asg-ssm-setup-guide.md](asg-ssm-setup-guide.md#troubleshooting) for more details.

## Best Practices

### Resource Requests

Always define resource requests for your pods:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

Without requests, autoscaler can't make informed decisions.

### PodDisruptionBudgets

Protect critical services during scale-down:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

### Node Affinity/Anti-Affinity

Use pod affinity to influence scheduling and scaling:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: my-app
        topologyKey: kubernetes.io/hostname
```

### Prevent Specific Nodes from Scale-Down

Add annotation to nodes:

```bash
kubectl annotate node <node-name> \
  cluster-autoscaler.kubernetes.io/scale-down-disabled=true
```

## Security

### RBAC Permissions

Cluster Autoscaler requires specific permissions:
- Read pods, nodes, deployments, statefulsets, daemonsets
- Evict pods
- Update nodes (cordon/uncordon)
- Create/update configmaps for status

See [gitops/base/cluster-autoscaler/rbac.yaml](../gitops/base/cluster-autoscaler/rbac.yaml)

### IAM Permissions

Node IAM role requires:
- `autoscaling:SetDesiredCapacity`
- `autoscaling:TerminateInstanceInAutoScalingGroup`
- `ec2:DescribeInstances`

Already configured in `kubestock-node-role`.

### Pod Security

The autoscaler pod runs with:
- Non-root user (65534)
- Read-only root filesystem
- No privilege escalation
- Dropped capabilities

## Cost Optimization

Cluster Autoscaler helps reduce costs by:

1. **Scaling down idle nodes** after 10 minutes
2. **Packing pods efficiently** using least-waste strategy
3. **Balancing node groups** to avoid partial utilization

### Monitor Costs

Track scaling events:

```bash
# Count scale-up/down events
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler | grep "scale_up"
kubectl logs -n cluster-autoscaler -l app=cluster-autoscaler | grep "scale_down"
```

### Tips

- Set appropriate resource requests (not too high)
- Use Horizontal Pod Autoscaler (HPA) for pod-level scaling
- Consider spot instances for non-critical workloads
- Review node utilization regularly

## GitOps Management

Cluster Autoscaler configuration is fully managed via GitOps:

**Repository Structure:**
```
gitops/
├── apps/
│   └── cluster-autoscaler.yaml           # ArgoCD Application
└── base/
    └── cluster-autoscaler/
        ├── deployment.yaml               # Main configuration
        ├── rbac.yaml                     # Permissions
        ├── service.yaml                  # Service for metrics
        ├── podmonitor.yaml               # Prometheus monitoring
        └── kustomization.yaml            # Kustomize config
```

**Making Changes:**
1. Edit files in `gitops/base/cluster-autoscaler/`
2. Commit and push to GitOps repository
3. ArgoCD automatically syncs changes (within 3 minutes)
4. No manual kubectl apply needed

## References

- [Official Documentation](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [AWS Cloud Provider Guide](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [Best Practices](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#best-practices)
