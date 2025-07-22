# CodePipeline for Terraform Plan (branch pushes) - runs in parallel across all accounts

resource "aws_codepipeline" "branch" {
    name     = "${var.org}-${var.app}-${local.env}-terraform-plan"
    role_arn = aws_iam_role.codepipeline.arn
    pipeline_type = "V2"

    artifact_store {
        location = aws_s3_bucket.tf_artifacts.id
        type     = "S3"
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
            namespace = "SourceVariables"  # Capture source metadata including version

            configuration = {
                S3Bucket    = aws_s3_bucket.ci_upload.id
                S3ObjectKey = "branch/latest.zip"  # Fixed key that CI will overwrite
                PollForSourceChanges = false  # We use EventBridge trigger instead
            }
        }
    }

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

        # Prod account plan
        # action {
        #     name            = "PlanProd"
        #     category        = "Invoke"
        #     owner           = "AWS"
        #     provider        = "Lambda"
        #     version         = "1"
        #     input_artifacts = ["source_output"]
        #     output_artifacts = ["prod_plan_output"]
        #     run_order       = 1
        #     role_arn        = "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_lambda_plan_invoker_name}"
        # 
        #     configuration = {
        #         FunctionName = local.conventional_prod_lambda_plan_lambda_function_name
        #         UserParameters = jsonencode({
        #             env = "prod"
        #             metadata_path = "metadata.json"
        #         })
        #     }
        # }

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
    }

    stage {
        name = "Report"

        action {
            name            = "ConsolidateResults"
            category        = "Invoke"
            owner           = "AWS"
            provider        = "Lambda"
            version         = "1"
            input_artifacts = ["dev_plan_output", "tools_plan_output"] # TODO(izaak): add prod_plan_output

            configuration = {
                FunctionName = module.lambda_consolidate_results.lambda_function_name
                UserParameters = jsonencode({})
            }
        }
    }

    # No pipeline variables needed - metadata comes from files in the artifact

    execution_mode = "PARALLEL"  # Allow concurrent executions

    tags = local.tags
}
