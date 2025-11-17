# CodeBuild project for running terraform apply with auto-approve (dev/tools)
resource "aws_codebuild_project" "terraform_apply_auto" {
    count = var.enable_auto_apply ? 1 : 0
    
    name = "${var.org}-${var.app}-${var.env}-terraform-apply-auto"
    
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
        buildspec = file("${path.module}/buildspec_apply_auto.yml")
    }

    # Conditionally add VPC configuration
    # Dynamic block with empty list = block not included at all (required for tools env without NAT gateway)
    # Dynamic block with [1] = block included once (for app envs with NAT gateway)
    dynamic "vpc_config" {
        for_each = var.enable_vpc_config ? [1] : []
        content {
            vpc_id             = data.aws_vpc.main[0].id
            subnets            = local.private_subnet_ids
            security_group_ids = [aws_security_group.terraform_runner[0].id]
        }
    }

    tags = local.tags
}