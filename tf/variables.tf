variable "region" {
  type = string
  description = "AWS region"
}

variable "asg_desired_capacity" {
  type = number
  default = 1
  description = "Desired number of instances in Auto Scaling Group"
}

variable "nlb_enabled" {
  type = bool
  default = false
  description = "Enable Network Load Balancer"
}

variable "ssh_pub_key_file" {
  default = "~/.ssh/id_rsa.pub"
  description = "Path to SSH public key file"
}