# CodeBuild project for running terraform plan
resource "aws_codebuild_project" "terraform_plan" {
    name = "${var.org}-${var.app}-${var.env}-terraform-plan"
    
    service_role = aws_iam_role.codebuild_terraform_plan.arn
    
    artifacts {
        type = "CODEPIPELINE"
    }
    
    environment {
        compute_type                = "BUILD_GENERAL1_SMALL"
        image                      = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
        type                       = "ARM_CONTAINER"
        image_pull_credentials_type = "CODEBUILD"
        
        # Pass tfvars as environment variables
        dynamic "environment_variable" {
            for_each = var.tfvars
            content {
                name  = "TF_VAR_${environment_variable.key}"
                value = environment_variable.value
            }
        }
        
        # Pass parameter store prefix for sensitive vars
        environment_variable {
            name  = "PARAMETER_STORE_PREFIX"
            value = local.parameter_prefix
        }
        
        environment_variable {
            name  = "OPENTOFU_VERSION"
            value = var.opentofu_version
        }
        
        environment_variable {
            name  = "ENVIRONMENT"
            value = var.env
        }
    }
    
    source {
        type = "CODEPIPELINE"
        buildspec = file("${path.module}/buildspec_plan.yml")
    }
    
    tags = local.tags
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_terraform_plan" {
    name = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "codebuild.amazonaws.com"
                }
                Action = "sts:AssumeRole"
            }
        ]
    })
    
    tags = local.tags
}

# Attach ReadOnlyAccess for terraform plan
resource "aws_iam_role_policy_attachment" "codebuild_terraform_plan_readonly" {
    role       = aws_iam_role.codebuild_terraform_plan.name
    policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Use base_meta module to grant terraform state access
module "base_meta" {
    source = "github.com/Mission-Tech/hoist//tf/modules/base_meta?ref=base_meta/v0.1.9"

    tfstate_access_role_name = aws_iam_role.codebuild_terraform_plan.name
    env                      = var.env
    app                      = var.app
    org                      = var.org
}

# Policy for CodeBuild
resource "aws_iam_role_policy" "codebuild_terraform_plan" {
    name = "terraform-plan-policy"
    role = aws_iam_role.codebuild_terraform_plan.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = [
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.terraform_plan.name}",
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.terraform_plan.name}:*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath"
                ]
                Resource = [
                    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:GetJobDetails",
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult"
                ]
                Resource = "*"
                # CodePipeline doesn't support resource-level permissions
            },
            {
                # Allow reading artifacts from the tools account pipeline bucket (cross-account)
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion"
                ]
                Resource = "arn:aws:s3:::${local.conventional_tools_pipeline_artifacts_bucket}/*"
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ]
                Resource = "arn:aws:s3:::${local.conventional_tools_pipeline_artifacts_bucket}"
            }
        ]
    })
}
