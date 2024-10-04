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

provider "aws" {
  region = var.region
}

resource "aws_key_pair" "k8s_control_plane_key" {
  public_key = file(var.ssh_pub_key_file)
}

module "k8s_control_plane_template" {
  source = "./modules/k8s_control_plane_template"
  vpc_id = module.experiments_vpc.vpc_id
  ssh_key_name = aws_key_pair.k8s_control_plane_key.key_name
  repository_arns = [module.experiments_ecr_frontend.repository_arn]
}

resource "aws_autoscaling_group" "experiments_k8s_cluster" {
  vpc_zone_identifier = module.experiments_vpc.public_subnets
  max_size = 1
  min_size = 0
  desired_capacity = var.asg_desired_capacity
  instance_refresh {
    strategy = "Rolling"
  }

  target_group_arns = [for group in module.experiments_nlb.target_groups: group.arn]

  launch_template {
    id      = module.k8s_control_plane_template.template_id
    version = module.k8s_control_plane_template.template_latest_version
  }
}

output "experiments_nlb_dns_name" {
  value = module.experiments_nlb.dns_name
}
