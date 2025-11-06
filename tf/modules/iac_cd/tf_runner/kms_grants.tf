# KMS Grants for cross-account CodeBuild access to pipeline artifacts
# This allows the CodeBuild roles in this account to decrypt the KMS key in the tools account

# Grant for terraform-plan CodeBuild role
resource "aws_kms_grant" "codebuild_plan" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  key_id            = local.conventional_pipeline_kms_key_alias_arn
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
  key_id            = local.conventional_pipeline_kms_key_alias_arn
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
