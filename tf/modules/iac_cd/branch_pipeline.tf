# CodePipeline for Terraform Plan (branch pushes) - runs in parallel across all accounts

locals {
    branch_pipeline_name = "${var.org}-${var.app}-${local.env}-terraform-plan"
    
    # Stage names for the branch pipeline
    branch_pipeline_stages = {
        source = "Source"
        plan   = "TerraformPlan"
    }
    
    # Action names
    branch_pipeline_actions = {
        plan_dev   = "PlanDev"
        plan_tools = "PlanTools"
        plan_prod  = "PlanProd"
    }
}

resource "aws_codepipeline" "branch" {
    name     = local.branch_pipeline_name
    role_arn = aws_iam_role.codepipeline.arn
    pipeline_type = "V2"

    artifact_store {
        location = aws_s3_bucket.tf_artifacts.id
        type     = "S3"

        # Use the shared KMS key for encryption
        encryption_key {
            id   = data.aws_kms_key.pipeline_artifacts.arn
            type = "KMS"
        }
    }

    stage {
        name = local.branch_pipeline_stages.source

        action {
            name             = "Source"
            category         = "Source"
            owner            = "AWS"
            provider         = "S3"
            version          = "1"
            output_artifacts = ["source_output"]
            namespace = "SourceVariables"  # Capture source metadata including version

            configuration = {
                S3Bucket    = aws_s3_bucket.ci_upload.id
                S3ObjectKey = "branch/latest.zip"  # Fixed key that CI will overwrite
                PollForSourceChanges = false  # We use EventBridge trigger instead
            }
        }
    }

    stage {
        name = local.branch_pipeline_stages.plan

        # Dev account plan
        action {
            name            = local.branch_pipeline_actions.plan_dev
            category        = "Build"
            owner           = "AWS"
            provider        = "CodeBuild"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["dev_plan_output"]
            run_order       = 1
            role_arn        = "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_plan_invoker_name}"

            configuration = {
                ProjectName = local.conventional_dev_codebuild_plan_project_name
            }
        }

        # Prod account plan
        action {
            name            = local.branch_pipeline_actions.plan_prod
            category        = "Build"
            owner           = "AWS"
            provider        = "CodeBuild"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["prod_plan_output"]
            run_order       = 1
            role_arn        = "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_plan_invoker_name}"

            configuration = {
                ProjectName = local.conventional_prod_codebuild_plan_project_name
            }
        }

        # Tools account plan
        action {
            name            = local.branch_pipeline_actions.plan_tools
            category        = "Build"
            owner           = "AWS"
            provider        = "CodeBuild"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["tools_plan_output"]
            run_order       = 1

            configuration = {
                ProjectName = module.tf_runner.codebuild_terraform_plan_project_name
            }
        }
    }


    # No pipeline variables needed - metadata comes from files in the artifact

    execution_mode = "PARALLEL"  # Allow concurrent executions

    tags = local.tags
}
