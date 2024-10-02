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

/* Variables */

variable "region" {
  type    = string
}

variable "asg_desired_capacity" {
  type = number
  default = 1
}

variable "nlb_enabled" {
  type = bool
  default = false
}

provider "aws" {
  region = var.region
}

variable "ssh_pub_key_file" {
  default = "~/.ssh/id_rsa.pub"
}

data "aws_availability_zones" "any" {
  state = "available"
}

/* VPC, trying the github module */

module "experiments_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.any.zone_ids
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  map_public_ip_on_launch = true
  create_igw = true
}

/* EC2 user data */

resource "random_id" "experiments_user_data_bucket_id" {
  byte_length = 8
}

resource "aws_s3_bucket" "experiments_s3_user_data" {
  bucket_prefix = "experiments-"
  force_destroy = true
}

resource "aws_s3_object" "experiments_user_data" {
  bucket = aws_s3_bucket.experiments_s3_user_data.bucket
  for_each = fileset("${path.module}/user_data/", "*")
  key = each.value
  source = "${path.module}/user_data/${each.value}"
  etag = filemd5("${path.module}/user_data/${each.value}")
}

/* EC2 role */

resource "aws_iam_instance_profile" "experiments_ec2_profile" {
  role = aws_iam_role.experiments_ec2_role.name
}

resource "aws_iam_role" "experiments_ec2_role" {
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

resource "aws_iam_role_policy" "experiments_ec2_inline_policy" {
  role = aws_iam_role.experiments_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.experiments_s3_user_data.arn,
          "${aws_s3_bucket.experiments_s3_user_data.arn}/*"
        ]
      },
      {
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Effect = "Allow"
        Resource = [
          module.experiments_ecr_frontend.repository_arn
        ]
      },
      {
        "Effect": "Allow",
        "Action": "ecr:GetAuthorizationToken",
        "Resource": "*"
      }
    ]
  })
}

/* EC2 security */

resource "aws_key_pair" "experiments_key" {
  key_name   = "experiments_key"
  public_key = file(var.ssh_pub_key_file)
}

resource "aws_security_group" "experiments_sg" {
  vpc_id = module.experiments_vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // NLB
  ingress {
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    security_groups = module.experiments_nlb.security_group_id != null ? [module.experiments_nlb.security_group_id] : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* EC2 launch */

data "aws_ami" "latest_amzn" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

locals {
  user_data_hash = sha1(join("", [for f in fileset(path.module, "user_data/**") : filesha1("${path.module}/${f}")]))
}

resource "aws_launch_template" "experiments_template" {
  image_id      = data.aws_ami.latest_amzn.id
  instance_type = "t4g.medium"
  depends_on = [aws_s3_object.experiments_user_data]

  user_data = base64encode(<<EOF
#!/bin/bash
export HOME=/root
mkdir /root/init
cd /root/init
# trigger: ${local.user_data_hash}
aws s3 cp --recursive s3://${aws_s3_bucket.experiments_s3_user_data.bucket}/ ./
chmod +x init.sh
./init.sh && rm -rf /root/init # keep init files around for debugging
EOF
  )

  key_name = aws_key_pair.experiments_key.key_name
  vpc_security_group_ids = [aws_security_group.experiments_sg.id]
  block_device_mappings {
    # swap
    device_name = "/dev/sdf"
    ebs {
      volume_size = 8
      volume_type = "gp3"
      delete_on_termination = "true"
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.experiments_ec2_profile.arn
  }
}

resource "aws_autoscaling_group" "experiments_asg" {
  vpc_zone_identifier = module.experiments_vpc.public_subnets
  max_size = 1
  min_size = 0
  desired_capacity = var.asg_desired_capacity
  instance_refresh {
    strategy = "Rolling"
  }

  target_group_arns = [for group in module.experiments_nlb.target_groups: group.arn]

  launch_template {
    id      = aws_launch_template.experiments_template.id
    version = aws_launch_template.experiments_template.latest_version
  }
}

/* NLB */

module "experiments_nlb" {
  source = "terraform-aws-modules/alb/aws"
  create = var.nlb_enabled
  load_balancer_type = "network"
  vpc_id = module.experiments_vpc.vpc_id
  subnets = aws_autoscaling_group.experiments_asg.vpc_zone_identifier
  enable_deletion_protection = false

  listeners = [
    {
      port = 80
      protocol = "TCP"
      forward = {
        target_group_key = "experiments"
      }
    }
  ]

  target_groups = {
    experiments = {
      name_prefix = "exp-"
      protocol = "TCP"
      port = 30000
      target_type = "instance"
      create_attachment = false
      health_check = {
        protocol = "HTTP"
        port = 30000
        path = "/"
        matcher = "200-399"
      }
    }
  }

  security_group_ingress_rules = {
    all_tcp = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.experiments_vpc.vpc_cidr_block
    }
  }
}

/* ECR */

module "experiments_ecr_frontend" {
  source = "terraform-aws-modules/ecr/aws"
  repository_name = "experiments-frontend"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep only the last 3 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 3
        },
        action = {
          type = "expire"
        },
      }
    ]
  })
}

/* GitHub */

resource "aws_iam_policy" "experiments_github_ecr" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:BatchGetImage"
        ]
        Effect = "Allow"
        Resource = [
          module.experiments_ecr_frontend.repository_arn
        ]
      },
      {
        "Effect": "Allow",
        "Action": "ecr:GetAuthorizationToken",
        "Resource": "*"
      }
    ]
  })
}

module "experiments_github_oidc" {
  source  = "terraform-module/github-oidc-provider/aws"
  version = "~> 1"

  create_oidc_provider = true
  create_oidc_role     = true

  repositories              = ["lucabrunox/experiments"]
  oidc_role_attach_policies = [aws_iam_policy.experiments_github_ecr.arn]
}

/* Outputs */

output "experiments_nlb_dns_name" {
  value = module.experiments_nlb.dns_name
}
