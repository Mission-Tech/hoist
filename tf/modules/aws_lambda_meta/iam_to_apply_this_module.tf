# This policy grants the minimum permissions required for an AWS role to successfully
# apply this Terraform module. Attach this policy to any role that needs to run
# terraform plan/apply for the hoist_lambda module.
# Everything else in this terraform module should be able to be managed with just the IAM permissions
# in this policy. 
# It's fine that this policy doesn't give permissions to manage this policy itself - it'll be created
# by a different role.

# ECR and basic infrastructure policy
resource "aws_iam_policy" "ecr_infrastructure" {
  name        = "${var.app}-${var.env}-hoist-lambda-tf-ecr"
  description = "ECR and basic infrastructure permissions for hoist_lambda module"

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
          "ecr:DeleteRepository",
          "ecr:PutImageTagMutability",
          "ecr:SetRepositoryPolicy",
          "ecr:GetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.app}-${var.env}*"
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
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig"
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
          "iam:DeleteRolePolicy",
          "iam:PassRole"
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
      # API Gateway read operations - cannot be scoped by ABAC
      # NOTE: apigateway:Request/ApiName and apigateway:Resource/ApiName condition keys
      # are NOT available for GET operations (GetRestApi, GetRestApis). AWS only provides
      # these keys for CreateRestApi, UpdateRestApi, and DeleteRestApi operations.
      # Therefore, read operations must be granted on all APIs. Write operations below
      # are properly scoped to our naming convention.
      {
        Sid    = "APIGatewayRead"
        Effect = "Allow"
        Action = [
          "apigateway:GET"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis",
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
      },
      # API Gateway creation - unrestricted because CreateRestApi has no usable condition keys
      {
        Sid    = "APIGatewayCreate"
        Effect = "Allow"
        Action = [
          "apigateway:POST"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis"
        ]
      },
      # API Gateway modify/delete operations - scoped by ABAC to our naming convention
      {
        Sid    = "APIGatewayModify"
        Effect = "Allow"
        Action = [
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
        Condition = {
          "ForAnyValue:StringLikeIfExists" = {
            "apigateway:Request/ApiName" = "${var.app}-${var.env}*",
            "apigateway:Resource/ApiName" = "${var.app}-${var.env}*"
          }
        }
      },
      # API Gateway sub-resource creation (methods, resources, integrations, etc.) - allow on our APIs
      # Note: Condition keys are not available for all sub-resource operations, so we allow broader access
      {
        Sid    = "APIGatewaySubResources"
        Effect = "Allow"
        Action = [
          "apigateway:POST",
          "apigateway:PUT"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis/*"
        ]
      },
    ]
  })

  tags = {
    Name        = "${var.app}-${var.env}-hoist-lambda-terraform-ecr"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "ECR and infrastructure policy for hoist_lambda module"
  }
}

# Compute and networking policy
resource "aws_iam_policy" "compute_networking" {
  name        = "${var.app}-${var.env}-hoist-lambda-tf-compute"
  description = "Compute and networking permissions for hoist_lambda module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Resource = [
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:vpc/*"
        ]
        Condition = {
          StringLike = {
            "aws:RequestedRegion": "*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app}-${var.env}-hoist-lambda-terraform-compute"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "Compute and networking policy for hoist_lambda module"
  }
}

# Storage policy (S3)
resource "aws_iam_policy" "storage" {
  name        = "${var.app}-${var.env}-hoist-lambda-tf-storage"
  description = "Storage permissions for hoist_lambda module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "s3:DeleteBucket*",
          "s3:GetAccelerateConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketVersioning",
          "s3:GetBucketLogging",
          "s3:GetBucketNotification",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketCors",
          "s3:GetBucketWebsite",
          "s3:GetBucketTagging",
          "s3:PutEncryptionConfiguration"
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
      }
    ]
  })

  tags = {
    Name        = "${var.app}-${var.env}-hoist-lambda-terraform-storage"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "Storage policy for hoist_lambda module"
  }
}

# Policy attachments
resource "aws_iam_role_policy_attachment" "ecr_infrastructure" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.ecr_infrastructure.arn
}

resource "aws_iam_role_policy_attachment" "compute_networking" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.compute_networking.arn
}

resource "aws_iam_role_policy_attachment" "storage" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.storage.arn
}
