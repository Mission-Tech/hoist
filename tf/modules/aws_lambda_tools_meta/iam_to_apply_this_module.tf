# This policy grants the minimum permissions required for an AWS role to successfully
# apply this Terraform module. Attach this policy to any role that needs to run
# terraform plan/apply for the aws_lambda_tools module.
# Everything else in this terraform module should be able to be managed with just the IAM permissions
# in this policy.
# It's fine that this policy doesn't give permissions to manage this policy itself - it'll be created
# by a different role.

# CodePipeline and artifact storage policy
resource "aws_iam_policy" "codepipeline_artifacts" {
  name        = "${var.app}-tools-hoist-lambda-tools-tf-pipeline"
  description = "CodePipeline and artifact storage permissions for aws_lambda_tools module (updated)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 bucket management for pipeline artifacts
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
        Resource = "arn:aws:s3:::${var.app}-*-tools-*"
      },
      # S3 object permissions for pipeline artifacts
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
        Resource = "arn:aws:s3:::${var.app}-*-tools-*/*"
      },
      # CodePipeline management
      {
        Sid    = "CodePipelineManagement"
        Effect = "Allow"
        Action = [
          "codepipeline:CreatePipeline",
          "codepipeline:GetPipeline",
          "codepipeline:GetPipelineState",
          "codepipeline:GetPipelineExecution",
          "codepipeline:ListPipelineExecutions",
          "codepipeline:UpdatePipeline",
          "codepipeline:DeletePipeline",
          "codepipeline:TagResource",
          "codepipeline:ListTagsForResource",
          "codepipeline:UntagResource"
        ]
        Resource = "arn:aws:codepipeline:*:*:${var.app}-tools-*"
      }
    ]
  })

  tags = {
    Name        = "${var.app}-tools-hoist-lambda-tools-terraform-pipeline"
    Module      = "aws_lambda_tools"
    Application = var.app
    Environment = "tools"
    Description = "CodePipeline and artifact storage policy for aws_lambda_tools module"
  }
}

# IAM roles and policies for pipeline components
resource "aws_iam_policy" "iam_management" {
  name        = "${var.app}-tools-hoist-lambda-tools-tf-iam"
  description = "IAM management permissions for aws_lambda_tools module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # IAM role management for pipeline components
      {
        Sid    = "IAMRoleManagement"
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
        Resource = "arn:aws:iam::*:role/${var.app}-tools-*"
      },
      # Allow attaching AWS managed policies for CodePipeline
      {
        Sid    = "IAMPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::*:role/${var.app}-tools-*"
        Condition = {
          StringEquals = {
            "iam:PolicyARN": [
              "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app}-tools-hoist-lambda-tools-terraform-iam"
    Module      = "aws_lambda_tools"
    Application = var.app
    Environment = "tools"
    Description = "IAM management policy for aws_lambda_tools module"
  }
}

# Lambda function management
resource "aws_iam_policy" "lambda_functions" {
  name        = "${var.app}-tools-hoist-lambda-tools-tf-lambda"
  description = "Lambda function management permissions for aws_lambda_tools module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda function management
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
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig"
        ]
        Resource = [
          "arn:aws:lambda:*:*:function:${var.app}-tools-*",
          "arn:aws:lambda:*:*:function:${var.app}-tools-*:*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app}-tools-hoist-lambda-tools-terraform-lambda"
    Module      = "aws_lambda_tools"
    Application = var.app
    Environment = "tools"
    Description = "Lambda function management policy for aws_lambda_tools module"
  }
}

# EventBridge and SNS management
resource "aws_iam_policy" "events_notifications" {
  name        = "${var.app}-tools-hoist-lambda-tools-tf-events"
  description = "EventBridge and SNS permissions for aws_lambda_tools module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "events:ListTagsForResource",
          "events:PutEventBusPolicy",
          "events:DeleteEventBusPolicy",
          "events:DescribeEventBus"
        ]
        Resource = [
          "arn:aws:events:*:*:rule/${var.app}-*",
          "arn:aws:events:*:*:event-bus/default"
        ]
      },
      # SNS topic management
      {
        Sid    = "SNSTopicManagement"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:DeleteTopic",
          "sns:TagResource",
          "sns:ListTagsForResource",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:GetSubscriptionAttributes",
          "sns:SetSubscriptionAttributes"
        ]
        Resource = "arn:aws:sns:*:*:${var.app}-tools-*"
      }
    ]
  })

  tags = {
    Name        = "${var.app}-tools-hoist-lambda-tools-terraform-events"
    Module      = "aws_lambda_tools"
    Application = var.app
    Environment = "tools"
    Description = "EventBridge and SNS management policy for aws_lambda_tools module"
  }
}

# Parameter Store read permissions
resource "aws_iam_policy" "parameter_store" {
  name        = "${var.app}-tools-hoist-lambda-tools-tf-params"
  description = "Parameter Store read permissions for aws_lambda_tools module"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Parameter Store read permissions for shared parameters
      {
        Sid    = "ParameterStoreRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/coreinfra/shared/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app}-tools-hoist-lambda-tools-terraform-params"
    Module      = "aws_lambda_tools"
    Application = var.app
    Environment = "tools"
    Description = "Parameter Store read policy for aws_lambda_tools module"
  }
}

# Policy attachments
resource "aws_iam_role_policy_attachment" "codepipeline_artifacts" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.codepipeline_artifacts.arn
}

resource "aws_iam_role_policy_attachment" "iam_management" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.iam_management.arn
}

resource "aws_iam_role_policy_attachment" "lambda_functions" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.lambda_functions.arn
}

resource "aws_iam_role_policy_attachment" "events_notifications" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.events_notifications.arn
}

resource "aws_iam_role_policy_attachment" "parameter_store" {
  role       = var.ci_assume_role_name
  policy_arn = aws_iam_policy.parameter_store.arn
}
