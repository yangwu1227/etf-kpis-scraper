resource "aws_vpc" "private" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    name = "${var.stack_name}_vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.private.id
  tags = merge(local.tags, {
    name = "${var.stack_name}_igw"
  })
}

resource "aws_subnet" "public" {
  for_each = tomap({
    for index, cidr in var.public_subnet_cidrs :
    index => { cidr = cidr, az = var.availability_zones[index] }
  })

  vpc_id                  = aws_vpc.private.id
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true
  availability_zone       = each.value.az

  tags = merge(local.tags, {
    name = "${var.stack_name}_public_subnet_${each.key}"
  })
}

resource "aws_subnet" "private" {
  for_each = tomap({
    for index, cidr in var.private_subnet_cidrs :
    index => { cidr = cidr, az = var.availability_zones[index] }
  })

  vpc_id                  = aws_vpc.private.id
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false
  availability_zone       = each.value.az

  tags = merge(local.tags, {
    name = "${var.stack_name}_private_subnet_${each.key}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.private.id
  tags = merge(local.tags, {
    name = "${var.stack_name}_public_rtb"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain   = "vpc"
}

resource "aws_nat_gateway" "nat" {
  for_each = aws_subnet.public

  subnet_id     = each.value.id
  allocation_id = aws_eip.nat[each.key].id
  tags = merge(local.tags, {
    name = "${var.stack_name}_nat_gw_${each.key}"
  })
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.private.id
  tags = merge(local.tags, {
    name = "${var.stack_name}_private_rtb_${each.key}"
  })
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_security_group" "private" {
  vpc_id = aws_vpc.private.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    name = "${var.stack_name}_sg"
  })
}
