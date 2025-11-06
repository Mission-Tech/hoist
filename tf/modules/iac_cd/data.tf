data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Look up the KMS key for pipeline artifacts (created by coreinfra in tools account)
# This key encrypts S3 artifacts in the pipeline bucket. We look it up here so:
# 1. The iac_cd module (tools account) can pass it to tf_runner without needing a variable
# 2. CodePipeline and Lambda IAM policies can reference it
# 3. The S3 bucket encryption can use it
data "aws_kms_key" "pipeline_artifacts" {
  key_id = "alias/${local.conventional_pipeline_kms_key_name}"
}
