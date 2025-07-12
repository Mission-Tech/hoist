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
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}*"
      },
      # Allow listing attached policies on CodeDeploy role (needed for Terraform state checks)
      {
        Sid    = "CodeDeployRoleListPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}*"
      },
      # Allow attaching AWS managed CodeDeploy policies to the CodeDeploy role
      {
        Sid    = "CodeDeployPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}*"
        Condition = {
          StringLike = {
            "iam:PolicyARN": [
              "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda",
              "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambdaLimited"
            ]
          }
        }
      },
      # CodeDeploy application and deployment group management
      {
        Sid    = "CodeDeployAppManagement"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateApplication",
          "codedeploy:GetApplication",
          "codedeploy:DeleteApplication",
          "codedeploy:TagResource",
          "codedeploy:ListTagsForResource",
          "codedeploy:CreateDeploymentGroup",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:UpdateDeploymentGroup",
          "codedeploy:DeleteDeploymentGroup",
          "codedeploy:CreateDeploymentConfig",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:DeleteDeploymentConfig"
        ]
        Resource = [
          "arn:aws:codedeploy:*:*:application:${var.app}-${var.env}*",
          "arn:aws:codedeploy:*:*:deploymentgroup:${var.app}-${var.env}*/*",
          "arn:aws:codedeploy:*:*:deploymentconfig:${var.app}-${var.env}*"
        ]
      },
      # Lambda function and execution role management
      {
        Sid    = "LambdaFunctionManagement"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:GetFunction",
          "lambda:UpdateFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:DeleteFunction",
          "lambda:TagResource",
          "lambda:ListTags",
          "lambda:CreateAlias",
          "lambda:GetAlias",
          "lambda:UpdateAlias",
          "lambda:DeleteAlias",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:ListVersionsByFunction"
        ]
        Resource = [
          "arn:aws:lambda:*:*:function:${var.app}-${var.env}",
          "arn:aws:lambda:*:*:function:${var.app}-${var.env}:*",
          "arn:aws:lambda:*:*:function:${var.app}-${var.env}-*",
          "arn:aws:lambda:*:*:function:${var.app}-${var.env}-*:*"
        ]
      },
      # IAM role management for Lambda execution and trigger roles
      {
        Sid    = "LambdaRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:ListRoleTags",
          "iam:UpdateAssumeRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}*"
      },
      # Allow attaching Lambda execution policies
      {
        Sid    = "LambdaExecutionPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-${var.env}*"
        Condition = {
          StringEquals = {
            "iam:PolicyARN": [
              "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
              "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
            ]
          }
        }
      },
      # CloudWatch alarm management
      {
        Sid    = "CloudWatchAlarmManagement"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:TagResource",
          "cloudwatch:ListTagsForResource"
        ]
        Resource = "arn:aws:cloudwatch:*:*:alarm:${var.app}-${var.env}*"
      },
      # EventBridge rule management
      {
        Sid    = "EventBridgeManagement"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DescribeRule",
          "events:DeleteRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule",
          "events:TagResource",
          "events:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:events:*:*:rule/${var.app}-${var.env}*",
          "arn:aws:events:*:*:rule/*/${var.app}-${var.env}*"
        ]
      },
      # Allow reading Lambda service role for permissions
      {
        Sid    = "ServiceLinkedRoleRead"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/AWSServiceRoleForLambda"
      },
      # API Gateway management - scoped to this app/env only by naming pattern using ABAC
      {
        Sid    = "APIGatewayManagement"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis",
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
        Condition = {
          "ForAnyValue:StringLikeIfExists" = {
            "apigateway:Request/ApiName" = "${var.app}-${var.env}*"
          }
        }
      },
      {
        Sid    = "APIGatewayManagementResource"
        Effect = "Allow" 
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis",
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
        Condition = {
          "ForAnyValue:StringLikeIfExists" = {
            "apigateway:Resource/ApiName" = "${var.app}-${var.env}*"
          }
        }
      },
      # VPC and Security Group read permissions for Lambda
      {
        Sid    = "VPCReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      # Security Group management for Lambda
      {
        Sid    = "SecurityGroupManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/Name": "${var.app}-${var.env}*"
          }
        }
      },
      # ECR image read permissions for Lambda deployment
      {
        Sid    = "ECRImageRead"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.app}-${var.env}*"
      },
      # S3 bucket management - allow any bucket with the app-env prefix
      {
        Sid    = "S3BucketManagement"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucket*",
          "s3:PutBucket*",
          "s3:DeleteBucket*"
        ]
        Resource = "arn:aws:s3:::${var.app}-${var.env}*"
      },
      # S3 object permissions for any objects in app-env prefixed buckets
      {
        Sid    = "S3ObjectManagement"
        Effect = "Allow"
        Action = [
          "s3:GetObject*",
          "s3:PutObject*",
          "s3:DeleteObject*",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "arn:aws:s3:::${var.app}-${var.env}*/*"
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
