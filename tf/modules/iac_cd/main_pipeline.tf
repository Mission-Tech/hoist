# CodePipeline for Terraform Apply (main branch) - Plan → Manual Approval → Apply

locals {
    main_pipeline_name = "${var.org}-${var.app}-${local.env}-terraform-apply"
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
        name = "Source"

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

    # Plan stage - same as branch pipeline but for apply
    stage {
        name = "TerraformPlan"

        # Dev account plan
        action {
            name            = "PlanDev"
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

        # Tools account plan
        action {
            name            = "PlanTools"
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

        # TODO: Add prod when ready
        # action {
        #     name            = "PlanProd"
        #     category        = "Build"
        #     owner           = "AWS"
        #     provider        = "CodeBuild"
        #     version         = "1"
        #     input_artifacts = ["source_output"]
        #     output_artifacts = ["prod_plan_output"]
        #     run_order       = 1
        #     role_arn        = "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_plan_invoker_name}"
        #
        #     configuration = {
        #         ProjectName = local.conventional_prod_codebuild_plan_project_name
        #     }
        # }
    }

    # Manual approval stage
    stage {
        name = "ManualApproval"

        action {
            name     = "ManualApproval"
            category = "Approval"
            owner    = "AWS"
            provider = "Manual"
            version  = "1"

            configuration = {
                NotificationArn = aws_sns_topic.manual_approval.arn
                CustomData      = "Please review the terraform plan and approve if ready to apply changes."
            }
        }
    }

    # Apply stage
    stage {
        name = "TerraformApply"

        # Apply to dev environment
        action {
            name             = "ApplyDev"
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            version          = "1"
            input_artifacts  = ["source_output", "dev_plan_output"]
            output_artifacts = ["dev_apply_output"]
            run_order        = 1
            role_arn         = "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_apply_invoker_name}"

            configuration = {
                ProjectName = local.conventional_dev_codebuild_apply_project_name
            }
        }

        # Apply to tools environment
        action {
            name             = "ApplyTools"
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            version          = "1"
            input_artifacts  = ["source_output", "tools_plan_output"]
            output_artifacts = ["tools_apply_output"]
            run_order        = 1

            configuration = {
                ProjectName = module.tf_runner.codebuild_terraform_apply_project_name
            }
        }

        # TODO: Add prod when ready
        # action {
        #     name             = "ApplyProd"
        #     category         = "Build"
        #     owner            = "AWS"
        #     provider         = "CodeBuild"
        #     version          = "1"
        #     input_artifacts  = ["source_output", "prod_plan_output"]
        #     output_artifacts = ["prod_apply_output"]
        #     run_order        = 1
        #     role_arn         = "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_apply_invoker_name}"
        #
        #     configuration = {
        #         ProjectName = local.conventional_prod_codebuild_apply_project_name
        #     }
        # }
    }

    # No pipeline variables needed - metadata comes from files in the artifact

    execution_mode = "QUEUED"  # Apply terraform runs in order

    tags = local.tags
}