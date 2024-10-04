variable "ssh_key_name" {
  type        = string
  description = "The name of the key pair"
}

variable "repository_arns" {
  type        = list(string)
  description = "List of ARNs of ECR repositories that the nodes can access"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}