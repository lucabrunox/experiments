#!/bin/bash
set -euo pipefail

echo "== INIT START =="

export PATH=$PATH:/usr/local/bin
export KUBECONFIG=/etc/kubernetes/admin.conf

function update_system() {
  yum update -y
}

function install_containerd() {
  yum install containerd -y
  systemctl enable containerd
  systemctl start containerd
}

function configure_netfilter() {
  echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
  modprobe br_netfilter
  cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system
}

function install_kube_tools() {
  # Use v1.29 because cri-tools is v1.29: https://v1-29.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF
  yum install -y cri-tools kubelet kubeadm kubectl --disableexcludes=kubernetes
  systemctl enable kubelet
}

function create_cluster() {
  # https://v1-29.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#initializing-your-control-plane-node
  kubeadm init --config ./kubeadm.yaml
}

function install_helm() {
  # https://helm.sh/docs/intro/install/
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

function install_flannel() {
  # For assigning IPs to Pods: https://github.com/flannel-io/flannel?tab=readme-ov-file#deploying-flannel-with-helm
  kubectl create ns kube-flannel
  kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
  helm repo add flannel https://flannel-io.github.io/flannel/
  helm install flannel --set podCidr="10.244.0.0/16" --namespace kube-flannel flannel/flannel
}

function create_masters_group() {
  # Map experiments:masters group to cluster-admin role
  kubectl apply -f masters-group.yaml
}

function create_ec2_user_admin() {
  # Make ec2-user part of the K8s experiments:masters admin group
  openssl genrsa -out ec2-user.key 4096
  openssl req -new -key ec2-user.key -out ec2-user.req -subj "/CN=ec2-user/O=experiments:masters"
  local BASE64REQ=$(cat ec2-user.req | base64 | tr -d '\n')
  cat <<EOF > ec2-user-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ec2-user-csr
spec:
  groups:
  - system:authenticated
  request: $BASE64REQ
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF
  kubectl apply -f ec2-user-csr.yaml
  # Sign with the cluster key
  kubectl certificate approve ec2-user-csr
  kubectl wait csr/ec2-user-csr --for=jsonpath="{.status.certificate}" --timeout=60s
  # Get the signed certificate
  kubectl get csr/ec2-user-csr -o jsonpath="{.status.certificate}" | base64 -d > ec2-user.crt
  # Add cluster to the config
  kubectl --kubeconfig ec2-user-config config set-cluster experiments --server=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}") --embed-certs --certificate-authority=/etc/kubernetes/pki/ca.crt
  # Create kube config for ec2-user
  kubectl --kubeconfig ec2-user-config config set-credentials ec2-user --embed-certs --client-key ec2-user.key --client-certificate ec2-user.crt
  # Add context to the config
  kubectl --kubeconfig ec2-user-config config set-context ec2-user@experiments --cluster experiments --user ec2-user
  # Make default
  kubectl --kubeconfig ec2-user-config config use-context ec2-user@experiments

  # Move config to ec2-user home
  mkdir /home/ec2-user/.kube
  mv ec2-user-config /home/ec2-user/.kube/config
  chown -R ec2-user:ec2-user /home/ec2-user/.kube
  chmod 700 /home/ec2-user/.kube
  chmod 600 /home/ec2-user/.kube/config
}

update_system
install_containerd
configure_netfilter
install_kube_tools
create_cluster
install_helm
install_flannel
create_masters_group
create_ec2_user_admin

echo "== INIT END =="