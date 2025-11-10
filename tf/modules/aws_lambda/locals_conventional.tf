# Inputs that are created by other terraform modules that we're using
# because the names are conventional.

locals {
    # Created by coreinfra (github.com/mission-tech/coreinfra)
    conventional_coreinfra_vpc_name = "${local.org}-${var.env}"
    conventional_coreinfra_default_kms_key_alias = "${local.org}-${var.env}-default"
}
