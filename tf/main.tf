terraform {
  backend "s3" {
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.16.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.68"
    }
  }
}

variable "region" {
  type    = string
  #default = "eu-west-1"
}

variable "asg_desired_capacity" {
  type = number
  default = 1
}

provider "aws" {
  region = var.region
}

resource "aws_dynamodb_table" "learning_table" {
  name           = "LearningTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  range_key      = "rk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "rk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Terraform   = "true"
    Name        = "LearningTable"
    Environment = "learning"
  }
}

data "aws_ami" "latest_amzn" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

data "aws_availability_zones" "any" {
  state = "available"
}

/* VPC, trying the github module */

module "learning_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.any.zone_ids
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24"]

  map_public_ip_on_launch = true
  create_igw = true
}

/* EC2 */

variable "ssh_pub_key_file" {
  default = "~/.ssh/id_rsa.pub"
}

resource "aws_key_pair" "learning_key" {
  key_name   = "learning_key"
  public_key = file(var.ssh_pub_key_file)
}

resource "aws_iam_instance_profile" "learning_ec2_profile" {
  role = aws_iam_role.learning_ec2_role.name
}

resource "aws_launch_template" "learning_template" {
  image_id      = data.aws_ami.latest_amzn.id
  instance_type = "t4g.nano"
  user_data = filebase64("${path.module}/user_data/user_data.sh")
  key_name = aws_key_pair.learning_key.key_name
  vpc_security_group_ids = [aws_security_group.learning_sg.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.learning_ec2_profile.arn
  }
}

resource "aws_iam_role" "learning_ec2_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

resource "aws_security_group" "learning_sg" {
  vpc_id = module.learning_vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["80.233.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "learning_asg" {
  vpc_zone_identifier = module.learning_vpc.public_subnets
  max_size = 1
  min_size = 0
  desired_capacity = var.asg_desired_capacity
  instance_refresh {
    strategy = "Rolling"
  }

  launch_template {
    id      = aws_launch_template.learning_template.id
    version = aws_launch_template.learning_template.latest_version
  }
}

