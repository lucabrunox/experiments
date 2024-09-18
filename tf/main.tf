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
      version = "~> 4.16"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
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