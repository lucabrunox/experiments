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

  name = "learning_vpc"
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.any.zone_ids
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24"]

  create_igw = true
}

/* EC2 */

resource "aws_launch_template" "learning_template" {
  image_id      = data.aws_ami.latest_amzn.id
  instance_type = "t4g.nano"
}

resource "aws_autoscaling_group" "learning_asg" {
  vpc_zone_identifier = module.learning_vpc.public_subnets
  max_size = 1
  min_size = 0
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.learning_template.id
    version = aws_launch_template.learning_template.latest_version
  }
}
