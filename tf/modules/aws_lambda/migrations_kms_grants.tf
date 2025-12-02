# KMS Grants for cross-account migrations CodeBuild access to pipeline artifacts
#
# Why grants?
# - Migrations CodeBuild in dev/prod needs to decrypt S3 artifacts from the tools account's pipeline bucket
# - The KMS key is in the tools account, but we can't modify its policy for every app
# - Grants allow this module to bootstrap access without touching the central key policy
#
# How it works:
# 1. Read the KMS ARN from /coreinfra/shared parameter store (created by coreinfra)
# 2. This module creates a grant for the migrations CodeBuild role
# 3. The KMS key policy in tools account allows cross-account grant creation
#
# Bootstrap order:
# 1. Apply coreinfra tools (creates KMS key + policy allowing cross-account grants)
# 2. Apply coreinfra dev/prod (creates parameter with KMS ARN)
# 3. Apply app dev/prod (creates grant for app's migrations role)
# 4. Pipeline can now run migrations (CodeBuild can decrypt artifacts)

# Read the KMS key ARN from parameter store
data "aws_ssm_parameter" "pipeline_artifacts_kms_key_arn" {
  count = var.enable_migrations ? 1 : 0
  name  = "/coreinfra/shared/pipeline_artifacts_kms_key_arn"
}

# Grant for migrations CodeBuild role
resource "aws_kms_grant" "migrations" {
  count             = var.enable_migrations ? 1 : 0
  name              = "${var.app}-${var.env}-codebuild-migrations"
  key_id            = data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn[0].value
  grantee_principal = aws_iam_role.migrations[0].arn

  operations = [
    "Decrypt",
    "DescribeKey"
  ]

  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.migrations[0].arn
}
