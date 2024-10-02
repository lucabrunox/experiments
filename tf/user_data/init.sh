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

update_system
install_containerd
configure_netfilter
install_kube_tools
create_cluster
install_helm
install_flannel

echo "== INIT END =="