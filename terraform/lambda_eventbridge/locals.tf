locals {
  aws_region = data.aws_region.current.region

  tags = {
    scope   = "lambda_eventbridge"
    project = var.stack_name
  }
}
