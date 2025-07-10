# Inputs that are created by other terraform modules that we're using 
# because the names are conventional.

locals {
    # Created by coreinfra (github.com/mission-tech/coreinfra
    conventional_coreinfra_vpc_name = "${local.org}-${var.env}"
    conventional_coreinfra_subnets = [
        "${local.org}-${var.env}-private-0",
        "${local.org}-${var.env}-private-1",
        "${local.org}-${var.env}-private-2"
    ]
}
