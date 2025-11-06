# KMS Grants for cross-account CodeBuild access to pipeline artifacts
#
# Why grants?
# - CodeBuild jobs in dev/prod need to decrypt S3 artifacts from the tools account's pipeline bucket
# - The KMS key is in the tools account, but we can't modify its policy for every app
# - Grants allow this module to bootstrap access without touching the central key policy
#
# How it works:
# 1. Coreinfra passes the KMS ARN directly (to avoid circular dependency during bootstrap)
# 2. Apps like gometheus read from /coreinfra/shared parameter store (created by coreinfra)
# 3. This module creates grants for the CodeBuild terraform-plan and terraform-apply roles
# 4. The KMS key policy in tools account allows cross-account grant creation
#
# Bootstrap order:
# 1. Apply coreinfra tools (creates KMS key + policy allowing cross-account grants)
# 2. Apply coreinfra dev/prod (creates parameter with KMS ARN + grants for coreinfra roles)
# 3. Apply app dev/prod locally once (creates grants for app roles)
# 4. Future applies work via CI/CD pipeline (CodeBuild can now decrypt artifacts)

# Read the KMS key ARN from parameter store only if not provided as variable
data "aws_ssm_parameter" "pipeline_artifacts_kms_key_arn" {
  count = var.pipeline_artifacts_kms_key_arn == null ? 1 : 0
  name  = "/coreinfra/shared/pipeline_artifacts_kms_key_arn"
}

locals {
  kms_key_arn = var.pipeline_artifacts_kms_key_arn != null ? var.pipeline_artifacts_kms_key_arn : data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn[0].value
}

# Grant for terraform-plan CodeBuild role
resource "aws_kms_grant" "codebuild_plan" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  key_id            = local.kms_key_arn
  grantee_principal = aws_iam_role.codebuild_terraform_plan.arn
  
  operations = [
    "Decrypt",
    "Encrypt",
    "DescribeKey",
    "GenerateDataKey"
  ]
  
  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.codebuild_terraform_plan.arn
}

# Grant for terraform-apply CodeBuild role
resource "aws_kms_grant" "codebuild_apply" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-apply"
  key_id            = local.kms_key_arn
  grantee_principal = aws_iam_role.codebuild_terraform_apply.arn
  
  operations = [
    "Decrypt",
    "Encrypt",
    "DescribeKey",
    "GenerateDataKey"
  ]
  
  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.codebuild_terraform_apply.arn
}

# Note: No separate grant needed for terraform-apply-auto
# It reuses the same IAM role as terraform-apply (see codebuild_terraform_apply_auto.tf:7)
