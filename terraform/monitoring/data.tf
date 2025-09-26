data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "ecs_fargate" {
  backend = "s3"
  config = {
    bucket  = var.terraform_state_bucket
    key     = var.ecs_fargate_state_key
    region  = data.aws_region.current.region
    profile = var.profile
  }
}
