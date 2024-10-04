data "aws_availability_zones" "any" {
  state = "available"
}

module "experiments_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.any.zone_ids
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  map_public_ip_on_launch = true
  create_igw = true
}