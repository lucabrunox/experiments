## Learning and sharing random stuff

### Terraform

Start by creating an S3 bucket, for example:

```bash
aws s3api create-bucket --acl private --bucket learning-12345-terraform --create-bucket-configuration LocationConstraint=eu-west-1
```

Then create a config for the Terraform backend:

```bash
cd tf

cat <<EOF > backend.conf
bucket = "learning-12345-terraform"
key    = "learning/terraform.tfstate"
region = "eu-west-1"
EOF

terraform init --backend-config=backend.conf
terraform apply
```

Check the state is indeed in S3:

```bash
aws s3 ls s3://learning-12345-terraform/learning/terraform.tfstate
```