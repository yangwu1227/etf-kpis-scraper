locals {
  aws_region     = data.aws_region.current.region

  tags = {
    scope   = "vpc_private"
    project = var.stack_name
  }
}
