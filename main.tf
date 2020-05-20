# -----------------------------------------------------------------------------
# Calculate which AZs to build subnets within
# -----------------------------------------------------------------------------

data "aws_availability_zones" "us_azs" {
  provider = aws.us-west-1
  state    = "available"
}

data "aws_availability_zones" "eu_azs" {
  provider = aws.eu-central-1
  state    = "available"
}

locals {
  us_az_suffixes = [for az in data.aws_availability_zones.us_azs.names : trimprefix(az, "us-west-1")]
  us_azs         = slice(local.us_az_suffixes, 0, var.num_azs > length(local.us_az_suffixes) ? length(local.us_az_suffixes) : var.num_azs)
  eu_az_suffixes = [for az in data.aws_availability_zones.eu_azs.names : trimprefix(az, "eu-central-1")]
  eu_azs         = slice(local.eu_az_suffixes, 0, var.num_azs > length(local.eu_az_suffixes) ? length(local.eu_az_suffixes) : var.num_azs)

  common_tags = { "Owner" = "Jamie Caesar", "Company" = "Spacely Sprockets" }
}

# -----------------------------------------------------------------------------
# US West 1 Admin VPC
# -----------------------------------------------------------------------------

module "us_vpc" {
  source  = "tfe.aws.shadowmonkey.com/spacelysprockets/ss_vpc/aws"
  version = "0.0.4"

  cidr_block = "10.1.0.0/16"
  vpc_name   = "us_admin"
  tags       = local.common_tags

  providers = {
    aws = aws.us-west-1
  }
}

# -----------------------------------------------------------------------------
# EU Central 1 Admin VPC
# -----------------------------------------------------------------------------

module "eu_vpc" {
  source  = "tfe.aws.shadowmonkey.com/spacelysprockets/ss_vpc/aws"
  version = "0.0.4"

  cidr_block = "10.2.0.0/16"
  vpc_name   = "eu_admin"
  tags       = local.common_tags

  providers = {
    aws = aws.eu-central-1
  }
}

# # -----------------------------------------------------------------------------
# # VPC Peering between Admin VPCs
# # -----------------------------------------------------------------------------

# resource "aws_vpc_peering_connection" "us-eu" {
#   provider      = aws.us-west-1
#   vpc_id        = module.us_vpc.vpc_id
#   peer_vpc_id   = module.eu_vpc.vpc_id
#   peer_region   = "eu-central-1"
#   auto_accept   = false
# }

# # Accepter's side of the connection.
# resource "aws_vpc_peering_connection_accepter" "eu-us" {
#   provider                  = aws.eu-central-1
#   vpc_peering_connection_id = aws_vpc_peering_connection.us-eu.id
#   auto_accept               = true
# }


