# CodePipeline for Terraform Plan (branch pushes) - runs in parallel across all accounts

resource "aws_codepipeline" "terraform_plan" {
    name     = "${var.org}-${var.app}-${var.env}-terraform-plan"
    role_arn = aws_iam_role.codepipeline.arn

    artifact_store {
        location = aws_s3_bucket.terraform_artifacts.bucket
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

            configuration = {
                S3Bucket    = "#{variables.sourceS3Bucket}"
                S3ObjectKey = "#{variables.sourceS3Key}"
            }
        }
    }

    stage {
        name = "TerraformPlan"

        # Dev account plan
        action {
            name            = "PlanDev"
            category        = "Invoke"
            owner           = "AWS"
            provider        = "Lambda"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["dev_plan_output"]
            run_order       = 1

            configuration = {
                FunctionName = module.lambda_terraform_plan.lambda_function_name
                UserParameters = jsonencode({
                    environment = "dev"
                    account_id  = var.dev_account_id
                    commit_sha  = "#{variables.commitSha}"
                    branch      = "#{variables.branch}"
                    author      = "#{variables.author}"
                })
            }
        }

        # Prod account plan
        action {
            name            = "PlanProd"
            category        = "Invoke"
            owner           = "AWS"
            provider        = "Lambda"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["prod_plan_output"]
            run_order       = 1

            configuration = {
                FunctionName = module.lambda_terraform_plan.lambda_function_name
                UserParameters = jsonencode({
                    environment = "prod"
                    account_id  = var.prod_account_id
                    commit_sha  = "#{variables.commitSha}"
                    branch      = "#{variables.branch}"
                    author      = "#{variables.author}"
                })
            }
        }

        # Tools account plan
        action {
            name            = "PlanTools"
            category        = "Invoke"
            owner           = "AWS"
            provider        = "Lambda"
            version         = "1"
            input_artifacts = ["source_output"]
            output_artifacts = ["tools_plan_output"]
            run_order       = 1

            configuration = {
                FunctionName = module.lambda_terraform_plan.lambda_function_name
                UserParameters = jsonencode({
                    environment = "tools"
                    account_id  = data.aws_caller_identity.current.account_id
                    commit_sha  = "#{variables.commitSha}"
                    branch      = "#{variables.branch}"
                    author      = "#{variables.author}"
                })
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
            input_artifacts = ["dev_plan_output", "prod_plan_output", "tools_plan_output"]

            configuration = {
                FunctionName = module.lambda_consolidate_results.lambda_function_name
                UserParameters = jsonencode({
                    commit_sha = "#{variables.commitSha}"
                    branch     = "#{variables.branch}"
                    author     = "#{variables.author}"
                    pr_number  = "#{variables.prNumber}"
                })
            }
        }
    }

    variable {
        name         = "sourceS3Bucket"
        default_value = aws_s3_bucket.terraform_artifacts.bucket
        description  = "S3 bucket containing terraform artifacts"
    }

    variable {
        name         = "sourceS3Key"
        default_value = ""
        description  = "S3 key of terraform artifact"
    }

    variable {
        name         = "prNumber"
        default_value = ""
        description  = "Pull request number if applicable"
    }

    variable {
        name         = "commitSha"
        default_value = ""
        description  = "Git commit SHA"
    }

    variable {
        name         = "branch"
        default_value = ""
        description  = "Git branch name"
    }

    variable {
        name         = "author"
        default_value = ""
        description  = "Commit author"
    }

    tags = local.tags
}