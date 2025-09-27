locals {
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id

  ecs_cluster_name   = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_cluster_name
  ecs_log_group_name = "/aws/ecs/${var.stack_name}"

  sns_topics_names = ["success", "failure"]

  log_metric_filter_patterns = {
    success = var.success_pattern
    failure = var.failure_pattern
  }

  tags = {
    scope   = "monitoring"
    project = var.stack_name
  }
}
