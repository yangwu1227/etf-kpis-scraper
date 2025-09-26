resource "random_id" "this" {
  byte_length = 4
}

# Build JSON with jsonencode, then unescape < and > so EventBridge can substitute
locals {
  # Markdown body with ECS-specific placeholders for EventBridge input_transformer
  description_md = <<EOD
  Status: <last_status>
  Cluster: `<cluster_arn>`
  Task: `<task_arn>`
  Launch: <launch_type>  |  Platform: <platform_version>  |  AZ: <avz>
  Resources: CPU <cpu>  |  Memory <memory>  |

  Timeline

  * Created: <created_at>
  * Updated: <updated_at>

  Primary container

  * Name: <primary_container_name>  |  Status: <primary_container_status>
  * Image: <primary_container_image>
  EOD

  q_payload_obj = {
    version = "1.0"
    source  = "custom"
    id      = random_id.this.hex
    content = {
      textType    = "client-markdown"
      title       = "Scraper ECS Task Failed"
      description = local.description_md
      keywords    = ["ecs", "fargate", "etf_kpis_scraper"]
    }
    metadata = {
      threadId            = "<task_arn>"
      summary             = "ECS task <last_status>"
      eventType           = "ecs.taskStateChange"
      enableCustomActions = true
    }
  }

  # Build JSON, then restore "<" and ">" so EventBridge will substitute placeholders
  q_payload_json_raw = jsonencode(local.q_payload_obj)
  q_payload_json     = replace(replace(local.q_payload_json_raw, "\\u003c", "<"), "\\u003e", ">")
}

# CloudWatch log metric filters for log patterns (i.e., emitted by the python/shell processes running inside tasks)
resource "aws_cloudwatch_log_metric_filter" "filters" {
  for_each = local.log_metric_filter_patterns

  name           = "${var.stack_name}_${each.key}_metric_filter"
  pattern        = each.value
  log_group_name = local.ecs_log_group_name

  metric_transformation {
    name          = "${var.stack_name}_${each.key}_metric_filter"
    namespace     = "Custom/ECSFargate"
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch alarms based on log metric filters (i.e., monitors success or failures of the processes running inside tasks)
resource "aws_cloudwatch_metric_alarm" "alarms" {
  for_each = local.log_metric_filter_patterns

  alarm_name          = "${var.stack_name}_${each.key}_alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = aws_cloudwatch_log_metric_filter.filters[each.key].metric_transformation[0].name
  namespace           = "Custom/ECSFargate"
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors completion of fargate task for ${var.stack_name} given pattern: ${each.value}"
  alarm_actions       = [aws_sns_topic.notifications[each.key].arn]

  evaluation_periods  = var.evaluation_periods
  period              = var.period
  treat_missing_data  = var.treat_missing_data
  datapoints_to_alarm = var.datapoints_to_alarm

  tags = local.tags

  depends_on = [
    aws_cloudwatch_log_metric_filter.filters,
    aws_sns_topic.notifications
  ]
}

# EventBridge rules and targets for ECS task state changes (i.e., monitors task-level executionfailures)
# Event bridge examples: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern.html
# Describe task API: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeTasks.html
resource "aws_cloudwatch_event_rule" "ecs_task_failure" {
  name        = "${var.stack_name}_task_exit_failure"
  description = "Match tasks state changes with certain stopped codes"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.ecs"],
    detail-type = ["ECS Task State Change"],
    # Task-level failures (not container-level failure, which is handled by cloudwatch alarms): https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Task.html
    detail = {
      clusterArn = ["arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:cluster/${local.ecs_cluster_name}"],
      lastStatus = ["STOPPED"],
      # EssentialContainerExited is already covered by the cloudwatch alarm with log metric filters
      stopCode = [{ "anything-but" : ["UserInitiated", "ServiceSchedulerInitiated", "EssentialContainerExited"] }]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "publish_failure_events_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_task_failure.name
  target_id = "${var.stack_name}_task_exit_failure_target"
  arn       = aws_sns_topic.notifications["failure"].arn

  input_transformer {
    # See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_task_events.html
    input_paths = {
      task_arn         = "$.detail.taskArn"
      cluster_arn      = "$.detail.clusterArn"
      last_status      = "$.detail.lastStatus"
      launch_type      = "$.detail.launchType"
      platform_version = "$.detail.platformVersion"
      avz              = "$.detail.availabilityZone"
      created_at       = "$.detail.createdAt"
      updated_at       = "$.detail.updatedAt"
      cpu              = "$.detail.cpu"
      memory           = "$.detail.memory"

      # Primary container fields
      primary_container_name   = "$.detail.containers[0].name"
      primary_container_status = "$.detail.containers[0].lastStatus"
      primary_container_image  = "$.detail.containers[0].image"
    }

    input_template = local.q_payload_json
  }

  depends_on = [
    aws_cloudwatch_event_rule.ecs_task_failure,
    aws_sns_topic.notifications["failure"]
  ]
}

