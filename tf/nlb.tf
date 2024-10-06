module "experiments_nlb" {
  source = "terraform-aws-modules/alb/aws"
  create = var.nlb_enabled
  load_balancer_type = "network"
  vpc_id = module.experiments_vpc.vpc_id
  subnets = aws_autoscaling_group.experiments_k8s_control_plane.vpc_zone_identifier
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

resource "aws_vpc_security_group_ingress_rule" "experiments_nlb" {
  count = var.nlb_enabled ? 1 : 0
  security_group_id = module.k8s_control_plane_template.security_group_id

  referenced_security_group_id = module.experiments_nlb.security_group_id
  from_port         = 30000
  to_port           = 30000
  ip_protocol       = "tcp"
}