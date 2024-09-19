## Learning and sharing random stuff

### Terraform

Define the AWS region that will be used for the rest of the commands:

```bash
export AWS_REGION=eu-west-1
```

Start by creating an S3 bucket, for example:

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

Apply the plan:

```bash
terraform apply \
  -var "region=$AWS_REGION" \
  -var "asg_desired_capacity=1"
```

Verify the state is indeed in S3:

```bash
aws s3 ls s3://learning-12345-terraform/learning/terraform.tfstate
```

Verify an EC2 instance has started:

```bash
aws ec2 describe-instances
```

Tear down:

```bash
terraform apply \
  -var "region=$AWS_REGION" \
  -var "asg_desired_capacity=0"
```