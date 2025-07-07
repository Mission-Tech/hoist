# This policy grants the minimum permissions required for an AWS role to successfully
# apply this Terraform module. Attach this policy to any role that needs to run
# terraform plan/apply for the hoist_lambda module.
# Everything else in this terraform module should be able to be managed with just the IAM permissions
# in this policy. 
# It's fine that this policy doesn't give permissions to manage this policy itself - it'll be created
# by a different role.

resource "aws_iam_policy" "meta" {
  name        = "${var.app}-${var.env}-hoist-lambda-tf-meta"
  description = "Permissions required to run terraform for the hoist_lambda module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR repository and lifecycle policy management
      {
        Sid    = "ECRManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource",
          "ecr:TagResource",
          "ecr:PutLifecyclePolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:DeleteRepository"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.app}-${var.env}"
      },
      # IAM policy creation for the ECR access policy
      {
        Sid    = "IAMPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:DeletePolicy",
          "iam:TagPolicy",
          "iam:ListPolicyTags"
        ]
        Resource = "arn:aws:iam::*:policy/${var.app}-${var.env}-ecr"
      },
      # IAM policy attachment - only allow attaching the specific ECR policy to the CI role
      {
        Sid    = "IAMPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.ci_assume_role_name}"
        Condition = {
          StringLike = {
            "iam:PolicyARN": "arn:aws:iam::*:policy/${var.app}-${var.env}-ecr" # Must match policy name in main module
          }
        }
      },
      # Allow listing attached policies to verify state
      {
        Sid    = "IAMListPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "arn:aws:iam::*:role/${var.ci_assume_role_name}"
      },
      # IAM role creation and management for CodeDeploy
      {
        Sid    = "CodeDeployRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:ListRoleTags",
          "iam:UpdateAssumeRolePolicy",
          "iam:ListRolePolicies"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}-codedeploy"
      },
      # Allow listing attached policies on CodeDeploy role (needed for Terraform state checks)
      {
        Sid    = "CodeDeployRoleListPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}-codedeploy"
      },
      # Allow attaching AWS managed CodeDeploy policies to the CodeDeploy role
      {
        Sid    = "CodeDeployPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}-codedeploy"
        Condition = {
          StringLike = {
            "iam:PolicyARN": [
              "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda",
              "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambdaLimited"
            ]
          }
        }
      },
    ]
  })

  tags = {
    Name        = "${var.app}-${var.env}-hoist-lambda-terraform"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "Terraform execution policy for hoist_lambda module"
  }
}

resource "aws_iam_role_policy_attachment" "tfstate_access" {
    role       = var.ci_assume_role_name
    policy_arn = aws_iam_policy.meta.arn
}
