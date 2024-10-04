resource "aws_iam_instance_profile" "this" {
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
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
}

resource "aws_iam_role_policy" "this" {
  role = aws_iam_role.this.id
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
          aws_s3_bucket.user_data.arn,
          "${aws_s3_bucket.user_data.arn}/*"
        ]
      },
      {
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Effect = "Allow"
        Resource = var.repository_arns
      },
      {
        "Effect": "Allow",
        "Action": "ecr:GetAuthorizationToken",
        "Resource": "*"
      }
    ]
  })
}

resource "aws_security_group" "this" {
  vpc_id = var.vpc_id
  /* Do not put ingress/egress in here, because otherwise it cannot be expanded with external rules */
}

resource "aws_vpc_security_group_ingress_rule" "ingress_22" {
  security_group_id = aws_security_group.this.id

  from_port = 22
  to_port = 22
  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "egress" {
  security_group_id = aws_security_group.this.id

  ip_protocol = "-1"
  cidr_ipv4 = "0.0.0.0/0"
}