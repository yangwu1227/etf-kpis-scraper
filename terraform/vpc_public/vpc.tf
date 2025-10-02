resource "aws_vpc" "public" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name        = "${var.stack_name}_vpc"
    utilization = "${local.utilization_percent}%"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.public.id
  tags = merge(local.tags, {
    Name = "${var.stack_name}_igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.public.id
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true
  availability_zone       = each.value.az

  tags = merge(local.tags, {
    Name = "${var.stack_name}_public_subnet_${each.key}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.public.id
  tags = merge(local.tags, {
    Name = "${var.stack_name}_rtb"
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

resource "aws_security_group" "public" {
  vpc_id = aws_vpc.public.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.stack_name}_sg"
  })
}
