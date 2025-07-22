# Determine VPC and subnet IDs
locals {
  # Use provided VPC ID or look it up by convention
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.lookup[0].id
  
  # Use provided subnet IDs or look them up by convention
  subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : data.aws_subnets.lookup[0].ids
}

# Data source for VPC (only if not provided via variable)
data "aws_vpc" "lookup" {
  count = var.vpc_id == "" ? 1 : 0
  
  filter {
    name   = "tag:Name"
    values = [local.conventional_coreinfra_vpc_name]
  }
}

# Data source for public subnets (only if not provided via variable)
data "aws_subnets" "lookup" {
  count = length(var.public_subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "tag:Name"
    values = local.conventional_coreinfra_public_subnets
  }
}

# Security group for CodeBuild
resource "aws_security_group" "codebuild" {
  name        = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  description = "Security group for CodeBuild terraform plan"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for internet access"
  }

  tags = merge(local.tags, {
    Name = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  })
}

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
    
    # VPC configuration for accessing RDS and other private resources
    vpc_config {
        vpc_id = local.vpc_id
        
        subnets = local.subnet_ids
        
        security_group_ids = [
            aws_security_group.codebuild.id
        ]
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
    source = "github.com/Mission-Tech/hoist//tf/modules/base_meta?ref=experimental/iac_cd/v0.0.6"

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
                # VPC permissions for CodeBuild - Network interface operations
                Effect = "Allow"
                Action = [
                    "ec2:CreateNetworkInterface",
                    "ec2:DeleteNetworkInterface",
                    "ec2:DescribeNetworkInterfaces"
                ]
                Resource = [
                    "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"
                ]
                Condition = {
                    StringEquals = {
                        "ec2:Vpc" = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:vpc/${local.vpc_id}"
                    }
                }
            },
            {
                # VPC permissions for CodeBuild - CreateNetworkInterfacePermission
                Effect = "Allow"
                Action = [
                    "ec2:CreateNetworkInterfacePermission"
                ]
                Resource = [
                    "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"
                ]
                Condition = {
                    StringEquals = {
                        "ec2:AuthorizedService" = "codebuild.amazonaws.com"
                    }
                }
            },
            {
                # VPC permissions for CodeBuild - Describe operations (read-only)
                Effect = "Allow"
                Action = [
                    "ec2:DescribeVpcs",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeDhcpOptions"
                ]
                Resource = "*"
                # Note: These describe operations don't support resource-level permissions
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
