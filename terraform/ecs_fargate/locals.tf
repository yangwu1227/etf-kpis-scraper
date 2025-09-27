locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.region

  tags = {
    scope   = "ecs_fargate"
    project = var.stack_name
  }
}
