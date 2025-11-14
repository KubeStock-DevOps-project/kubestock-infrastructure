# Developer Access Playbook

Step-by-step instructions for onboarding/offboarding developers, configuring kubectl, and establishing secure tunnels to the Kubestock cluster.

## 1. Onboarding a developer

### 1.1 Developer generates a key pair
```bash
ssh-keygen -t ed25519 -C "developer.name@kubestock.com" -f ~/.ssh/kubestock-dev
```
The developer shares `~/.ssh/kubestock-dev.pub` with the platform admin.

### 1.2 Admin adds the key to the bastion
```bash
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159
echo "ssh-ed25519 AAAA... developer.name@kubestock.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 1.3 Developer tests SSH access
```bash
ssh -i ~/.ssh/kubestock-dev ubuntu@100.30.61.159
```

### 1.4 Provide kubeconfig securely
On the dev server or bastion:
```bash
cat ~/kubeconfig
```
Share the file via a secure channel (never commit to git). Developers should save it as `~/.kube/kubestock-config` with `chmod 600`.

## 2. Configuring kubectl & tunnels (developer laptop)

### 2.1 Install kubectl
- macOS: `brew install kubectl`
- Linux: download from https://kubernetes.io/docs/tasks/tools/
- Windows: follow the same link.

### 2.2 Update kubeconfig to use the tunnel endpoint (via NLB)
```bash
export KUBECONFIG=~/.kube/kubestock-config
kubectl config set-cluster kubestock --server=https://127.0.0.1:6443
```

### 2.3 SSH config & aliases (`~/.ssh/config`)
```sshconfig
Host kubestock
  HostName 100.30.61.159
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ServerAliveInterval 60
  ServerAliveCountMax 3
  # Forward local 6443 to the NLB (not directly to the control-plane)
  LocalForward 6443 kubestock-nlb-api-773436c2b62a3c5f.elb.us-east-1.amazonaws.com:6443

Host ks-control
  HostName 10.0.10.21
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock

Host ks-worker-1
  HostName 10.0.11.30
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock

Host ks-worker-2
  HostName 10.0.12.30
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock
```
Adjust identities/hostnames as needed.

### 2.4 Shell helpers (`~/.bashrc` or `~/.zshrc`)
```bash
export KUBECONFIG=~/.kube/kubestock-config
alias ks-start='ssh -f -N kubestock && echo "Tunnel started"'
alias ks-stop='pkill -f "ssh.*kubestock" && echo "Tunnel stopped"'
alias ks-status='ps aux | grep "ssh.*kubestock" | grep -v grep && echo "Tunnel is running" || echo "Tunnel is not running"'
alias k='kubectl'
alias kgn='kubectl get nodes'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
```
`source ~/.bashrc` afterwards.

### 2.5 Daily workflow
```bash
ks-start
kubectl get nodes
kubectl get pods -A
# ...work...
ks-stop
```

## 3. Offboarding a developer
1. Remove their line from `~/.ssh/authorized_keys` on the bastion.
2. Invalidate any issued kubeconfigs.
3. Audit tunneling aliases/keys.

## 4. Troubleshooting
- **Tunnel down**: run `ks-status`, restart with `ks-stop && ks-start`.
- **kubectl connection refused**: ensure tunnel is running and kubeconfig points to `127.0.0.1:6443`.
- **Permission denied (publickey)**: confirm the correct private key is used and the public key exists on the bastion.
- **NLB health**: from bastion `curl -k https://kubestock-nlb-api-773436c2b62a3c5f.elb.us-east-1.amazonaws.com:6443/healthz` should return `ok`.

## 5. Optional tools
- **k9s** (TUI for Kubernetes)
  - macOS: `brew install derailed/k9s/k9s`
  - Linux: download from https://github.com/derailed/k9s/releases
- **Helm**: `brew install helm` or run the official install script on Linux.

## 6. Security best practices
1. Each developer must have a unique SSH keypair.
2. Always use the bastion tunnel (or a locked-down egress host)—never expose the control plane directly; route kubectl to the NLB.
3. Keep kubeconfigs private (`chmod 600`, no git commits).
4. Stop tunnels when not actively using the cluster.
5. Restrict bastion security groups to known office/VPN IPs.
