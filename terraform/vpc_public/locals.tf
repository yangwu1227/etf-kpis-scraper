locals {
  tags = {
    scope   = "vpc_public"
    project = var.stack_name
  }

  # Use exactly two AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Extract the VPC prefix length, e.g., 16 from 10.0.0.0/16
  vpc_prefix = tonumber(split("/", var.vpc_cidr)[1])
  # Calculate number of bits needed for AZ allocation
  # For 2 AZs we need 1 bit, for 3 - 4 AZs we need 2 bits
  az_bits = ceil(log(length(local.azs), 2))

  # Examples: /16 VPC -> /24 public (8 bits), /20 VPC -> /27 public (7 bits), /24 VPC -> /28 public (4 bits)
  public_bits = local.vpc_prefix <= 16 ? 8 : (local.vpc_prefix <= 20 ? 7 : 4)
  # Examples: /16 VPC + 8 bits = /24 public subnets
  public_prefix = local.vpc_prefix + local.public_bits

  # Public subnets start at the beginning of the VPC range since no private subnets exist
  # Exactly two public subnets, one per AZ
  public_subnets = [
    for i, _ in local.azs :
    cidrsubnet(var.vpc_cidr, local.public_bits, i)
  ]

  # IP utilization for tagging and visibility (32 is the total number of bits in an IPv4 address)
  total_ips_allocated = length(local.azs) * pow(2, 32 - local.public_prefix)
  vpc_total_ips       = pow(2, 32 - local.vpc_prefix)
  utilization_percent = (local.total_ips_allocated / local.vpc_total_ips) * 100

  # Example result: {"0" => {cidr = "10.0.32.0/24", az = "us-east-1a"}, "1" => {cidr = "10.0.33.0/24", az = "us-east-1b"}}
  public_subnet_map = {
    for i, cidr in local.public_subnets :
    tostring(i) => { cidr = cidr, az = local.azs[i] }
  }
}
