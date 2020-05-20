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
  version = "0.0.6"

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
  version = "0.0.6"

  cidr_block = "10.2.0.0/16"
  vpc_name   = "eu_admin"
  tags       = local.common_tags

  providers = {
    aws = aws.eu-central-1
  }
}

# -----------------------------------------------------------------------------
# VPC Peering between Admin VPCs
# -----------------------------------------------------------------------------

resource "aws_vpc_peering_connection" "us-eu" {
  provider    = aws.us-west-1
  vpc_id      = module.us_vpc.vpc_id
  peer_vpc_id = module.eu_vpc.vpc_id
  peer_region = "eu-central-1"
  auto_accept = false
}

# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "eu-us" {
  provider                  = aws.eu-central-1
  vpc_peering_connection_id = aws_vpc_peering_connection.us-eu.id
  auto_accept               = true
}

resource "aws_route" "us-eu" {
  provider = aws.us-west-1
  for_each = toset(module.us_vpc.route_tables)

  route_table_id            = each.value
  destination_cidr_block    = module.eu_vpc.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.us-eu.id
}

resource "aws_route" "eu-us" {
  provider = aws.eu-central-1
  for_each = toset(module.eu_vpc.route_tables)

  route_table_id            = each.value
  destination_cidr_block    = module.us_vpc.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.us-eu.id
}

# -----------------------------------------------------------------------------
# US Bastion Host
# -----------------------------------------------------------------------------

resource "aws_key_pair" "jamie" {
  provider   = aws.us-west-1
  key_name   = "jamie-admin"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKRqLi7AYYkDPqK09dtXtpXoV5tSL1iu1XA2wcYKe8TVUxi+sLY6XuOmD7E6NkSi70AtEqoANIsBQOSfYfc0yOX0Q30UAuQTW8SC3VAevtguxj6Yy18P/auokaLLgDvaYdlRNPdF74P0Tu21sn4Ak8rS4LjIqj3NcRKgn2Ng0SHHaY+opp4VWBnhBWWiNnz4A1Ul4Y1etmFp6BJVoLV51L7CK9XhYYHWx2uEUMyMP1Yz9raDRIlBxH7ulaw4rPfkVf9oLdE+BuD0VycoDv2GYf9gWSxZ31cQN5yZ5eUZyUKg8ZV1M+FQmDzsyL3P6R6QrI1ELUSMr0Qjgoz2tB9M3X"
}

resource "aws_security_group" "bastionHost" {
  provider    = aws.us-west-1
  name        = "bastionHost"
  description = "bastionHost"
  vpc_id      = module.us_vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Private Inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "sg_BastionHost" }, local.common_tags)
}

resource "aws_instance" "bastion" {
  provider                    = aws.us-west-1
  ami                         = "ami-06fcc1f0bc2c8943f"
  instance_type               = "t2.small"
  key_name                    = aws_key_pair.jamie.key_name
  subnet_id                   = module.us_vpc.subnets.public.a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastionHost.id]

  tags = merge({ Name = "us_bastion" }, local.common_tags)
}

# -----------------------------------------------------------------------------
# EU Bastion Host
# -----------------------------------------------------------------------------


resource "aws_key_pair" "jamie-eu" {
  provider   = aws.eu-central-1
  key_name   = "jamie-admin-eu"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKRqLi7AYYkDPqK09dtXtpXoV5tSL1iu1XA2wcYKe8TVUxi+sLY6XuOmD7E6NkSi70AtEqoANIsBQOSfYfc0yOX0Q30UAuQTW8SC3VAevtguxj6Yy18P/auokaLLgDvaYdlRNPdF74P0Tu21sn4Ak8rS4LjIqj3NcRKgn2Ng0SHHaY+opp4VWBnhBWWiNnz4A1Ul4Y1etmFp6BJVoLV51L7CK9XhYYHWx2uEUMyMP1Yz9raDRIlBxH7ulaw4rPfkVf9oLdE+BuD0VycoDv2GYf9gWSxZ31cQN5yZ5eUZyUKg8ZV1M+FQmDzsyL3P6R6QrI1ELUSMr0Qjgoz2tB9M3X"
}

resource "aws_security_group" "eubastionHost" {
  provider    = aws.eu-central-1
  name        = "bastionHost"
  description = "bastionHost"
  vpc_id      = module.eu_vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Private Inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "sg_BastionHost" }, local.common_tags)
}

resource "aws_instance" "eubastion" {
  provider                    = aws.eu-central-1
  ami                         = "ami-076431be05aaf8080"
  instance_type               = "t2.small"
  key_name                    = aws_key_pair.jamie-eu.key_name
  subnet_id                   = module.eu_vpc.subnets.public.a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.eubastionHost.id]

  tags = merge({ Name = "eu_bastion" }, local.common_tags)
}
