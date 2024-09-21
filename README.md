## Learning and sharing random stuff

This repo contains step-by-step creationg of low-level Terraform + K8s + other stuff for learning purposes.

### Terraform to create a K8s cluster on EC2

Define the AWS region that will be used for all the commands:

```bash
export AWS_REGION=eu-west-1
```

Create an S3 bucket for terraform state:

```bash
aws s3api create-bucket --acl private --bucket learning-12345-terraform --create-bucket-configuration LocationConstraint=$AWS_REGION
```

Initialize:

```bash
cd tf

cat <<EOF > backend.conf
bucket = "learning-12345-terraform"
key    = "learning/terraform.tfstate"
region = "$AWS_REGION"
EOF

terraform init --backend-config=backend.conf
terraform get
```

Apply the plan which will create a K8s cluster:

```bash
terraform apply \
  -var "region=$AWS_REGION" \
  -var "asg_desired_capacity=1"
```

Use asg_desired_capacity=0 to tear down the cluster.

### Kubernetes single-node cluster on EC2 with kubeadm

Created a raw low-level simple K8s cluster on EC2 on a single master node. Some interesting facts:

- It takes 2 minutes and 20 second until all containers are in Running state.
- A t4g.medium is needed to run a cluster. Using a t4g.nano with swap is not enough because the apiserver/etcd will keep timing out.
- CoreDNS and kube-proxy addons are installed by default.
- The advertising IP is coming from `ip route` and it coincides with the private IP of the instance rather than the public one.
- Explanation of flannel networking: https://mvallim.github.io/kubernetes-under-the-hood/documentation/kube-flannel.html

SSH into the EC2 instance and run crictl and kubectl commands to inspect the cluster:

```bash
sudo su

crictl ps

export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get all -A
```

If the cluster is not up check the instance init logs:

```bash
sudo cat /var/log/cloud-init-output.log
```
