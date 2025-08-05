# Conventional naming patterns for terraform state resources

locals {
    # S3 bucket for terraform state
    conventional_tfstate_bucket_name = "${var.org}-coreinfra-${var.env}-${data.aws_caller_identity.current.account_id}-tfstate"
    
    # DynamoDB table for terraform state locking
    conventional_tfstate_lock_table_name = "${var.org}-coreinfra-${var.env}-tfstate-lock"
}