/* Will refactor into a module once I add another repo */

module "experiments_ecr_frontend" {
  source          = "terraform-aws-modules/ecr/aws"
  repository_name = "experiments-frontend"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep only the last 3 images",
        selection = {
          tagStatus   = "tagged",
          tagPrefixList = ["v"],
          countType   = "imageCountMoreThan",
          countNumber = 3
        },
        action = {
          type = "expire"
        },
      }
    ]
  })
}

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
