# Look up the pipeline KMS key created by coreinfra
# This is only done if no explicit pipeline_kms_key_id is provided
data "aws_kms_key" "pipeline_artifacts" {
    count = var.pipeline_kms_key_id == "" ? 1 : 0
    
    key_id = local.conventional_pipeline_kms_key_alias
}

# Get the actual key ID (not alias) for use in resources
locals {
    pipeline_kms_key_id = var.pipeline_kms_key_id != "" ? var.pipeline_kms_key_id : (
        length(data.aws_kms_key.pipeline_artifacts) > 0 ? data.aws_kms_key.pipeline_artifacts[0].id : ""
    )
}