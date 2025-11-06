data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Look up the KMS key for pipeline artifacts (created by coreinfra in tools account)
data "aws_kms_key" "pipeline_artifacts" {
  key_id = "alias/${local.conventional_pipeline_kms_key_name}"
}
