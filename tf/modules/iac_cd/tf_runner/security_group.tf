# VPC and subnet datasources for CodeBuild VPC configuration
# Only created when enable_vpc_config is true (app environments with NAT gateway)
data "aws_vpc" "main" {
  count = var.enable_vpc_config ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [local.conventional_coreinfra_vpc_name]
  }
}

data "aws_ssm_parameter" "private_subnet_ids" {
  count = var.enable_vpc_config ? 1 : 0
  name  = "/coreinfra/shared/private_subnet_ids"
}

locals {
  conventional_coreinfra_vpc_name = "${var.org}-${var.env}"
  private_subnet_ids              = var.enable_vpc_config ? split(",", data.aws_ssm_parameter.private_subnet_ids[0].value) : []
}

# Security group for CodeBuild terraform runner
# This security group is used by all CodeBuild projects (plan, apply, apply_auto)
# to access VPC resources like RDS databases during terraform operations.
# Only created when enable_vpc_config is true (app environments with NAT gateway)
#
# Specifically, this is needed for:
# - croft_base module: The bootstrap process that grants rds_iam role to the master user
# - croft_app module: Creating per-app databases and roles via the postgresql provider
resource "aws_security_group" "terraform_runner" {
  count = var.enable_vpc_config ? 1 : 0

  name        = "${var.org}-${var.app}-${var.env}-terraform-runner"
  description = "Security group for terraform runner CodeBuild projects - allows access to VPC resources"
  vpc_id      = data.aws_vpc.main[0].id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.org}-${var.app}-${var.env}-terraform-runner"
  })
}
