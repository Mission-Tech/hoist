# CodePipeline for Terraform Apply (main branch) - STUB for future implementation

resource "aws_codepipeline" "main" {
    name     = "${var.org}-${var.app}-${local.env}-terraform-apply"
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

            configuration = {
                S3Bucket    = aws_s3_bucket.ci_upload.id
                S3ObjectKey = "main/latest.zip"  # Fixed key that CI will overwrite
                PollForSourceChanges = false  # We use EventBridge trigger instead
            }
        }
    }

    stage {
        name = "ApplyStub"

        action {
            name     = "ApplyPlaceholder"
            category = "Approval"
            owner    = "AWS"
            provider = "Manual"
            version  = "1"

            configuration = {
                CustomData = "This is a placeholder for the terraform apply pipeline. Implementation pending."
            }
        }
    }

    # No pipeline variables needed - metadata comes from files in the artifact

    execution_mode = "QUEUED"  # Apply terraform runs in order

    tags = local.tags
}