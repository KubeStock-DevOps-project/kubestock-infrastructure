# 🧩 KubeStock Cluster Build Plan

This is the **step-by-step plan** to provision and configure the **KubeStock production infrastructure**.
We will execute these steps **manually, one by one**, from the **Bastion host**.

**Repository:** `kubestock-infrastructure`
**Kubespray Path:** `./kubespray` (Assumed to be a git submodule in this repo)

---

## 🏗️ Phase 1: Provision Cloud Infrastructure (Terraform)

**Status:** 🚀 **NEXT UP**
**Goal:** Create all AWS resources (**VPC, Subnets, VMs, RDS, Cognito, NLB**) using Terraform.
**Directory:** `./prod`

### 🧰 Commands

```bash
# 1. Change to the production directory
cd ./prod

# 2. Initialize Terraform (to download providers and backend config)
terraform init -reconfigure

# 3. Apply the plan (takes ~5–10 mins)
terraform apply
```

### ✅ Verification

Run these commands manually from the `prod` directory:

```bash
terraform output bastion_public_ip
terraform output control_plane_private_ip
terraform output rds_hostname
```

You should see valid output for each.
➡️ Proceed to Phase 2 only after `terraform apply` completes **100% successfully**.

---

## ⚙️ Phase 2: Configure Kubespray (Ansible Inventory)

**Status:** ⏳ **PENDING**
**Goal:** Tell **Kubespray (Ansible)** which machines to install Kubernetes on.
**Directories:** `./prod/` → `./kubespray/`

### 🧰 Commands

```bash
# 1. Get the IP of your Control Plane node
MASTER_IP=$(terraform output -raw control_plane_private_ip)

# 2. Get the IP of your Worker node (from the ASG)
ASG_NAME=$(terraform output -raw worker_asg_name)
WORKER_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

# 3. Get the DNS name of your K8s API Load Balancer
NLB_DNS=$(terraform output -raw nlb_dns_name)

# 4. Path to your private SSH key
PRIVATE_KEY="~/.ssh/kubestock-key.pem"
```

### 🧾 Create Inventory Configuration

```bash
CONFIG_FILE="./kubespray/inventory/kubestock/hosts.ini"
mkdir -p ./kubespray/inventory/kubestock
cp -rfp ./kubespray/inventory/sample/* ./kubespray/inventory/kubestock/

cat > ${CONFIG_FILE} <<-EOF
[all]
master-1 ansible_host=${MASTER_IP} ansible_user=ubuntu etcd_member_name=etcd-1
worker-1 ansible_host=${WORKER_IP} ansible_user=ubuntu

[kube_control_plane]
master-1

[etcd]
master-1

[kube_node]
worker-1

[k8s_cluster:children]
kube_control_plane
kube_node
EOF
```

### ⚙️ Add Kubespray Variable Configuration

```bash
G_VARS="./kubespray/inventory/kubestock/group_vars"

cat >> ${G_VARS}/all/all.yml <<-EOF
ansible_private_key_file: ${PRIVATE_KEY}
EOF

cat >> ${G_VARS}/k8s_cluster/k8s-cluster.yml <<-EOF
apiserver_loadbalancer_domain_name: "${NLB_DNS}"
loadbalancer_apiserver_port: 6443
kube_network_plugin: calico
container_manager: containerd
EOF
```

### ✅ Verification

```bash
cat ./kubespray/inventory/kubestock/hosts.ini
cat ./kubespray/inventory/kubestock/group_vars/k8s_cluster/k8s-cluster.yml
```

Confirm all IPs and the **NLB DNS** are correct.

---

## 🚀 Phase 3: Install Kubernetes (Kubespray Run)

**Status:** ⏳ **PENDING**
**Goal:** Run the Ansible playbook to install Kubernetes on all provisioned VMs.
**Duration:** ~30–60 minutes
**Directory:** `./kubespray`

### 🧰 Commands

```bash
cd ./kubespray
ansible-playbook -i inventory/kubestock/hosts.ini --become --become-user=root cluster.yml
```

> 💡 Use `tmux` or `screen` to avoid session disconnection during the long run.

### ✅ Verification

The playbook ends with:

```
PLAY RECAP
failed=0
```

---

## 🔐 Phase 4: Get Cluster Access (Kubeconfig)

**Status:** ⏳ **PENDING**
**Goal:** Retrieve the kubeconfig from the master node to your Bastion.
**Directory:** `./kubespray`

### 🧰 Commands

```bash
CONFIG_FILE="inventory/kubestock/hosts.ini"
ansible master-1 -i ${CONFIG_FILE} -b -m fetch -a "src=/root/.kube/config dest=~/kubeconfig flat=yes"

export KUBECONFIG=~/kubeconfig
echo "export KUBECONFIG=~/kubeconfig" >> ~/.bashrc

kubectl get nodes
```

### ✅ Verification

`kubectl get nodes` should show:

```
master-1   Ready
worker-1   Ready
```

---

## 🧩 Phase 5: Install "Day 2" Platform Add-ons

**Status:** ⏳ **PENDING**
**Goal:** Install critical add-ons for a usable Kubernetes platform.
**Directory:** `~/`

### 🧰 Commands

```bash
# 1. AWS EBS CSI Driver
kubectl apply -k "https://github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"

# 2. NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

# 3. ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### ✅ Verification

Run:

```bash
kubectl get pods -A
```

You should see:

* `ebs-csi-controller`
* `ingress-nginx`
* `argocd-server`
  in **Running** state.

---

## ⚡ Phase 6: Finalize Auto Scaling (Terraform Update)

**Status:** ⏳ **PENDING**
**Goal:** Update the **AWS Launch Template** with the `kubeadm join` command so the ASG can launch working nodes.
**Directory:** `./prod`

### 🧰 Commands

```bash
CONFIG_FILE="../kubespray/inventory/kubestock/hosts.ini"
JOIN_CMD=$(ansible master-1 -i ${CONFIG_FILE} -b -m shell -a "kubeadm token create --print-join-command" | grep "kubeadm join")

USER_DATA_FILE="worker_user_data.sh"
cat > ${USER_DATA_FILE} <<-EOF
#!/bin/bash
apt-get update
apt-get install -y kubelet kubeadm containerd
# ... other pre-install tasks from Kubespray may be needed ...
${JOIN_CMD}
EOF
```

Then manually **edit** `./prod/compute.tf`:

```hcl
user_data = filebase64("${path.module}/worker_user_data.sh")
```

Apply the change:

```bash
cd ./prod
terraform apply -auto-approve
```

### ✅ Verification

Terraform output shows modification of the launch template.

#### 🧪 Final Test (Optional)

```bash
aws autoscaling set-desired-capacity --auto-scaling-group-name ${ASG_NAME} --desired-capacity 2
kubectl get nodes
```

A new `worker-2` node should appear and become **Ready**.

---

## 🤝 Phase 7: Handoff to Team

**Status:** ⏳ **PENDING**
**Goal:** Provide final credentials to Platform and App Dev teams.

### 🧰 Commands

```bash
# 1. ArgoCD admin password
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 2. RDS Hostname
cd ./prod
RDS_HOST=$(terraform output -raw rds_hostname)

# 3. Cognito IDs
COGNITO_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id)

# 4. Print summary
echo "--- PLATFORM TEAM HANDOFF ---"
echo "Kubeconfig: ~/kubeconfig"
echo "ArgoCD URL: (Port-forward to 'argocd-server -n argocd 8080:443')"
echo "ArgoCD User: admin"
echo "ArgoCD Pass: ${ARGO_PASS}"
echo ""
echo "--- APP DEV TEAM HANDOFF ---"
echo "Production RDS Host: ${RDS_HOST}"
echo "Cognito Pool ID: ${COGNITO_POOL_ID}"
echo "Cognito Client ID: ${COGNITO_CLIENT_ID}"
```

---

## ✅ Completion

🎉 You’re done!
Your **KubeStock production cluster** is up and running — ready for **GitOps handoff** to the team.
