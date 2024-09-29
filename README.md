## Learning and sharing random stuff

This repo contains step-by-step creationg of low-level Terraform + K8s + other stuff for learning purposes.

### Day 1: Set up Terraform with a remote backend

Commit: https://github.com/lucabrunox/learning/tree/cd8378154c378

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
  -var "asg_desired_capacity=1" \
  -var "nlb_enabled=true"
```

Use asg_desired_capacity=0 to tear down the cluster.

### Day 2: Kubernetes single-node cluster on EC2 with kubeadm

Commit: https://github.com/lucabrunox/learning/tree/9cc3ac81d7f

Using a raw K8s instead of EKS to learn some low-level details. Some interesting facts:

- It takes 2 minutes and 20 second until all containers are in Running state.
- A t4g.medium is needed to run a cluster. Using a t4g.nano with swap is not enough because the apiserver/etcd will keep timing out.
- CoreDNS and kube-proxy addons are installed by default.
- The advertising IP is coming from `ip route` and it coincides with the private IP of the instance rather than the public one.
- Explanations of K8s networking:
  - https://mvallim.github.io/kubernetes-under-the-hood/documentation/kube-flannel.html
  - https://www.redhat.com/sysadmin/kubernetes-pods-communicate-nodes

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

### Day 3: A Django frontend with GH action to build a Docker image and push to ECR

Commit: https://github.com/lucabrunox/learning/tree/5216dfe5efd6

Set up following https://docs.djangoproject.com/en/5.1/intro/tutorial01/ with `django-admin startproject mysite`.

The Dockerfile is self-explanatory. To try it out:

```bash
docker run -p 8000:8000 --rm -it $(docker build -q .)
```

Then open http://localhost:8000

To test GH actions I've set up act to run in a Docker, so that it doesn't need to be installed:

```bash
./test_gh.sh
```

Which in turn creates the frontend Docker, yay!

The GH also contains a job to push to ECR, which is not tested locally.

### Day 4: Deploy the Django app in K8s using the ECR image

Commit: https://github.com/lucabrunox/learning/tree/5216dfe5efd6

Needless to say that without EKS it's more complicated, but worth the learnings.

Learnings:
- Using CronJob to get AWS creds from the node, login to ECR, and store the secret for pulling images.
- CronJob doesn't start immediately, need to wait a minute.
- Need to untaint control plane node in other to schedule pods.
- Need to build the frontend image for ARM, obviously.
- Python app fails because it can't find the UTC timezone, needs tzdata.
- Cannot change the matching labels of a K8s deployment.

At the end we're able to execute the following kubectl on the EC2 instance to deploy the app and watch it working:

```bash
kubectl apply -f k8s/ecr-credentials.yaml
kubectl apply -f frontend/k8s/manifest.yaml

curl $(kubectl get svc frontend -o=jsonpath='{.spec.clusterIP}'):8000
```

### Day 5: Expose service via NLB and NodePort

Commit: https://github.com/lucabrunox/learning/tree/f03d8449f869

Publicly exposing the service via NLB learnings:
- Allowed node ports only from 30000
- NLB security group must be configured for each listener port
- NLBs need at least 2 subnets for redundancy
- Django has an ALLOWED_HOSTS config to prevent Host header attacks
- Django detects a tty when logging to stdout

```bash
kubectl apply -f k8s/ecr-credentials.yaml
kubectl apply -f frontend/k8s/manifest.yaml

curl http://$(terraform output --raw learning_nlb_dns_name)
```