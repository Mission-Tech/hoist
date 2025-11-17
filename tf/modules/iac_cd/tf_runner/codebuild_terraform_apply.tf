# CodeBuild project for running terraform apply
resource "aws_codebuild_project" "terraform_apply" {
    name = "${var.org}-${var.app}-${var.env}-terraform-apply"
    
    service_role = aws_iam_role.codebuild_terraform_apply.arn
    
    artifacts {
        type = "CODEPIPELINE"
    }
    
    cache {
        type = "LOCAL"
        modes = ["LOCAL_SOURCE_CACHE", "LOCAL_CUSTOM_CACHE"]
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
        
        environment_variable {
            name  = "ROOT_MODULE_DIR"
            value = var.root_module_dir
        }
    }
    
    source {
        type = "CODEPIPELINE"
        buildspec = file("${path.module}/buildspec_apply.yml")
    }

    vpc_config {
        vpc_id             = data.aws_vpc.main.id
        subnets            = local.public_subnet_ids
        security_group_ids = [aws_security_group.terraform_runner.id]
    }

    tags = local.tags
}

# IAM role for CodeBuild Apply
resource "aws_iam_role" "codebuild_terraform_apply" {
    name = "${var.org}-${var.app}-${var.env}-codebuild-terraform-apply"
    
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

# TODO: Add IAM boundary policy to restrict permissions
# Attach AdministratorAccess for terraform apply (needs IAM permissions that PowerUserAccess doesn't provide)
resource "aws_iam_role_policy_attachment" "codebuild_terraform_apply_admin" {
    role       = aws_iam_role.codebuild_terraform_apply.name
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Use base_meta module to grant terraform state access
module "base_meta_apply" {
    source = "github.com/Mission-Tech/hoist//tf/modules/base_meta?ref=experimental/iac_cd/v0.0.6"

    tfstate_access_role_name = aws_iam_role.codebuild_terraform_apply.name
    env                      = var.env
    app                      = var.app
    org                      = var.org
}

# Policy for CodeBuild Apply
resource "aws_iam_role_policy" "codebuild_terraform_apply" {
    name = "terraform-apply-policy"
    role = aws_iam_role.codebuild_terraform_apply.id
    
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
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.terraform_apply.name}",
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.terraform_apply.name}:*"
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
                # Allow reading/writing artifacts from the tools account pipeline bucket
                # This is needed for both cross-account access AND for the tools account itself
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject"
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
            },
            {
                # Allow KMS operations for cross-account S3 access
                # The tools account pipeline bucket uses KMS encryption
                Effect = "Allow"
                Action = [
                    "kms:Decrypt",
                    "kms:DescribeKey",
                    "kms:GenerateDataKey"  # Needed for encryption when writing artifacts
                ]
                Resource = [
                    "arn:aws:kms:${data.aws_region.current.name}:${var.tools_account_id}:key/*" # TODO(izaak): be more restrictive
                ]
                Condition = {
                    StringLike = {
                        "kms:ViaService" = [
                            "s3.${data.aws_region.current.name}.amazonaws.com"
                        ]
                    }
                }
            }
        ]
    })
}