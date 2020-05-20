output "us_vpc_data" {
  value = {
    "vpc_id" = module.us_vpc.vpc_id
    "cidr"   = module.us_vpc.cidr
    "region" = "us-west-1"
  }
}

output "eu_vpc_data" {
  value = {
    "vpc_id" = module.eu_vpc.vpc_id
    "cidr"   = module.eu_vpc.cidr
    "region" = "eu-central-1"
  }
}

output "wp_pcx" {
  value = aws_vpc_peering_connection.us-wp.id
}

output "wp_pcx" {
  value = aws_vpc_peering_connection.us-dr.id
}
