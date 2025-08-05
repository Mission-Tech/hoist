# CodePipeline for Terraform Apply (main branch) - Plan → Manual Approval → Apply

locals {
    main_pipeline_name = "${var.org}-${var.app}-${local.env}-terraform-apply"
    
    # Stage names for the main pipeline
    main_pipeline_stages = {
        source           = "Source"
        plan             = "TerraformPlan"
        apply_dev_tools  = "ApplyDevTools"
        prod_approval    = "ProdApproval"
        apply_prod       = "ApplyProd"
    }
    
    # Action names
    main_pipeline_actions = {
        plan_dev    = "PlanDev"
        plan_tools  = "PlanTools"
        plan_prod   = "PlanProd"
        apply_dev   = "ApplyDev"
        apply_tools = "ApplyTools"
        apply_prod  = "ApplyProd"
    }
}

resource "aws_codepipeline" "main" {
    name     = local.main_pipeline_name
    role_arn = aws_iam_role.codepipeline.arn
    pipeline_type = "V2"

    artifact_store {
        location = aws_s3_bucket.tf_artifacts.id
        type     = "S3"
        
        # Use the shared KMS key for encryption
        encryption_key {
            id   = var.pipeline_artifacts_kms_key_arn
            type = "KMS"
        }
    }

    stage {
        name = local.main_pipeline_stages.source

        action {
            name             = "Source"
            category         = "Source"
            owner            = "AWS"
            provider         = "S3"
            version          = "1"
            output_artifacts = ["source_output"]
            namespace        = "SourceVariables"  # Capture source metadata including version

            configuration = {
                S3Bucket    = aws_s3_bucket.ci_upload.id
                S3ObjectKey = "main/latest.zip"  # Fixed key that CI will overwrite
                PollForSourceChanges = false  # We use EventBridge trigger instead
            }
        }
    }

    # Apply dev and tools immediately (one-shot apply without separate plan)
    stage {
        name = local.main_pipeline_stages.apply_dev_tools

        # Apply to dev environment
        action {
            name             = local.main_pipeline_actions.apply_dev
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            version          = "1"
            input_artifacts  = ["source_output"]
            output_artifacts = ["dev_apply_output"]
            run_order        = 1
            role_arn         = "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_apply_invoker_name}"

            configuration = {
                ProjectName = "${var.org}-${var.app}-dev-terraform-apply-auto"
            }
        }

        # Apply to tools environment
        action {
            name             = local.main_pipeline_actions.apply_tools
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            version          = "1"
            input_artifacts  = ["source_output"]
            output_artifacts = ["tools_apply_output"]
            run_order        = 1

            configuration = {
                ProjectName = module.tf_runner.codebuild_terraform_apply_auto_project_name
            }
        }
    }

    # Plan prod for review
    stage {
        name = local.main_pipeline_stages.plan

        action {
            name            = local.main_pipeline_actions.plan_prod
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
    }

    # Manual approval for prod with enhanced notification
    stage {
        name = local.main_pipeline_stages.prod_approval

        action {
            name     = "ApproveProdDeploy"
            category = "Approval"
            owner    = "AWS"
            provider = "Manual"
            version  = "1"

            configuration = {
                NotificationArn = aws_sns_topic.manual_approval.arn
                CustomData      = "Dev and Tools have been deployed. Please review the prod terraform plan and approve if ready to apply changes to production."
            }
        }
    }

    # Apply prod after approval
    stage {
        name = local.main_pipeline_stages.apply_prod

        action {
            name             = local.main_pipeline_actions.apply_prod
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            version          = "1"
            input_artifacts  = ["source_output", "prod_plan_output"]
            output_artifacts = ["prod_apply_output"]
            run_order        = 1
            role_arn         = "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_apply_invoker_name}"

            configuration = {
                ProjectName = local.conventional_prod_codebuild_apply_project_name
                PrimarySource = "source_output"
            }
        }
    }

    # No pipeline variables needed - metadata comes from files in the artifact

    execution_mode = "QUEUED"  # Apply terraform runs in order

    tags = local.tags
}