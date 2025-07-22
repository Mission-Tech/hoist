data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Look up the pipeline KMS key created by coreinfra
data "aws_kms_key" "pipeline_artifacts" {
    key_id = local.conventional_pipeline_kms_key_alias
}
