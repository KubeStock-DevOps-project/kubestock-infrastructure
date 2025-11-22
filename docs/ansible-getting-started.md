# Ansible & Kubespray Quickstart

Use this playbook to (re)install the Kubestock cluster or to apply Kubespray changes from the bastion or dev server.

## 1. Prerequisites

- You can SSH into the bastion (`ssh -i ~/.ssh/kubestock-key ubuntu@<bastion-ip>`).
- Terraform has already provisioned the infrastructure under `~/kubestock-infrastructure/terraform/prod`.
- Python 3.10+ is available on the machine running Ansible (bastion or dev server).

## 2. Prep the Kubespray environment

```bash
cd ~/kubestock-infrastructure/kubespray
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

> Reactivate the virtualenv (`source venv/bin/activate`) in future sessions before running Ansible.

## 3. Refresh inventory variables

Grab the current IPs and endpoints from Terraform outputs:

```bash
cd ~/kubestock-infrastructure/terraform/prod
MASTER_IP=$(terraform output -raw control_plane_private_ip)
readarray -t WORKER_IPS <<< "$(terraform output -json worker_private_ips | jq -r '.[]')"
NLB_DNS=$(terraform output -raw nlb_dns_name)
```

Update the Kubespray inventory if needed (`kubespray/inventory/kubestock/hosts.ini`). Static workers live at the IPs from `worker_private_ips`; add/remove entries to match that list.

> Terraform automatically applies `terraform/prod/worker_user_data.sh` to each worker instance so that Python 3 and its tooling are preinstalled for Ansible. No manual prep is required on the nodes before running Kubespray.

### Group variables

`kubespray/inventory/kubestock/group_vars/all/all.yml` should contain:

```yaml
---
ansible_user: ubuntu
ansible_become: true
ansible_private_key_file: ~/.ssh/kubestock-key
ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
ansible_python_interpreter: /usr/bin/python3
```

`kubespray/inventory/kubestock/group_vars/k8s_cluster/k8s-cluster.yml` should include:

```yaml
---
cluster_name: kubestock
apiserver_loadbalancer_domain_name: "${NLB_DNS}"
loadbalancer_apiserver_port: 6443
supplementary_addresses_in_ssl_keys:
  - "${NLB_DNS}"
  - "${MASTER_IP}"
kube_network_plugin: calico
container_manager: containerd
kube_proxy_mode: iptables
```

## 4. Test Ansible connectivity

Before running long playbooks, make sure Ansible can reach every host:

```bash
cd ~/kubestock-infrastructure/kubespray
source venv/bin/activate
ansible all -i inventory/kubestock/hosts.ini -m ping -b
```

You should see `SUCCESS` responses from `master-1`, `worker-1`, and `worker-2`. Investigate SSH or inventory issues if any host fails.

## 5. Run the main Kubespray playbook

```bash
cd ~/kubestock-infrastructure/kubespray
source venv/bin/activate
ansible-playbook -i inventory/kubestock/hosts.ini --become --become-user=root cluster.yml
```

- Use `tmux`/`screen` to avoid losing progress.
- Expect 30–60 minutes for a full install.

## 6. Fetch kubeconfig and test

```bash
# Fetch the kubeconfig from master-1
cd ~/kubestock-infrastructure/kubespray
CONFIG_FILE=inventory/kubestock/hosts.ini
ansible master-1 -i ${CONFIG_FILE} -b -m fetch -a "src=/root/.kube/config dest=~/kubeconfig flat=yes"

# Get the NLB DNS name
cd ~/kubestock-infrastructure/terraform/prod
NLB_DNS=$(terraform output -raw nlb_dns_name)

# Update kubeconfig to use the NLB endpoint instead of the internal master IP
kubectl --kubeconfig=~/kubeconfig config set-cluster kubestock --server="https://${NLB_DNS}:6443"

# Set KUBECONFIG environment variable for this session and persist it
export KUBECONFIG=~/kubeconfig
echo 'export KUBECONFIG=~/kubeconfig' >> ~/.bashrc

# Smoke test via the load balancer
kubectl get --raw=/healthz
kubectl get nodes -o wide
```

You should see `master-1`, `worker-1`, and `worker-2` in `Ready` state.

> **Note:** The kubeconfig is fetched with the internal master IP by default. We update it to use the NLB DNS so all API requests go through the load balancer, which is the proper production setup. The `KUBECONFIG` environment variable is persisted in `~/.bashrc` so future shell sessions automatically use the correct config.

## 7. Day-2 add-ons (optional)

```bash
kubectl apply -k "https://github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Verify with `kubectl get pods -A`. Store the ArgoCD admin password for handoff:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```
