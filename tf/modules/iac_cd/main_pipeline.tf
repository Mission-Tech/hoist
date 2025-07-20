# CodePipeline for Terraform Apply (main branch) - STUB for future implementation

resource "aws_codepipeline" "main" {
    name     = "${var.org}-${var.app}-${local.env}-terraform-apply"
    role_arn = aws_iam_role.codepipeline.arn

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
                S3Bucket    = aws_s3_bucket.tf_artifacts.id
                S3ObjectKey = "#{variables.sourceS3Key}"
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

    variable {
        name         = "sourceS3Key"
        default_value = ""
        description  = "S3 key of terraform artifact"
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