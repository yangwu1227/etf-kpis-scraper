# Define log group for ECS tasks and get reference to ecs cluster
locals {
  log_group_name   = "/aws/ecs/${var.stack_name}"
  ecs_cluster_name = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_cluster_name
}

# SNS topics for notifications
resource "aws_sns_topic" "task_success" {
  name = "${var.stack_name}_task_success"

  # Add delivery policy with variables
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = var.sns_min_delay_target
        maxDelayTarget     = var.sns_max_delay_target
        numRetries         = var.sns_num_retries
        numNoDelayRetries  = var.sns_num_no_delay_retries
        numMinDelayRetries = var.sns_num_min_delay_retries
        backoffFunction    = var.sns_backoff_function
      }
      disableSubscriptionOverrides = false
    }
  })

  tags = {
    Name    = "${var.stack_name}_task_success"
    project = var.stack_name
  }
}

resource "aws_sns_topic" "task_failure" {
  name = "${var.stack_name}_task_failure"

  # Add delivery policy with variables
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = var.sns_min_delay_target
        maxDelayTarget     = var.sns_max_delay_target
        numRetries         = var.sns_num_retries
        numNoDelayRetries  = var.sns_num_no_delay_retries
        numMinDelayRetries = var.sns_num_min_delay_retries
        backoffFunction    = var.sns_backoff_function
      }
      disableSubscriptionOverrides = false
    }
  })

  tags = {
    Name    = "${var.stack_name}_task_failure"
    project = var.stack_name
  }
}

# Create separate policy documents for each topic
data "aws_iam_policy_document" "events_to_sns_success" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.task_success.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "events_to_sns_failure" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.task_failure.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

# Apply policies to respective topics
resource "aws_sns_topic_policy" "events_to_task_success_sns" {
  arn    = aws_sns_topic.task_success.arn
  policy = data.aws_iam_policy_document.events_to_sns_success.json
}

resource "aws_sns_topic_policy" "events_to_task_failure_sns" {
  arn    = aws_sns_topic.task_failure.arn
  policy = data.aws_iam_policy_document.events_to_sns_failure.json
}

# IAM resources for chatbot
resource "aws_iam_role" "chatbot_role" {
  name = "${var.stack_name}_chatbot_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    project = var.stack_name
  }
}

resource "aws_iam_policy" "chatbot_policy" {
  name        = "${var.stack_name}_chatbot_policy"
  description = "Policy for AWS ChatBot to access CloudWatch resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = var.chatbot_iam_permissions
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_role.chatbot_role]
}

resource "aws_iam_role_policy_attachment" "chatbot_policy_attachment" {
  role       = aws_iam_role.chatbot_role.name
  policy_arn = aws_iam_policy.chatbot_policy.arn

  depends_on = [
    aws_iam_role.chatbot_role,
    aws_iam_policy.chatbot_policy
  ]
}

# CloudWatch log metrics and filters
resource "aws_cloudwatch_log_metric_filter" "task_success" {
  name           = "${var.stack_name}_task_success"
  pattern        = var.success_pattern
  log_group_name = local.log_group_name

  metric_transformation {
    name          = "${var.stack_name}_task_success_metric"
    namespace     = "Custom/ECSFargate"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "task_failure" {
  name           = "${var.stack_name}_task_failure"
  pattern        = var.failure_pattern
  log_group_name = local.log_group_name

  metric_transformation {
    name          = "${var.stack_name}_task_failure_metric"
    namespace     = "Custom/ECSFargate"
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "task_success" {
  alarm_name          = "${var.stack_name}_task_success"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "${var.stack_name}_task_success_metric"
  namespace           = "Custom/ECSFargate"
  period              = var.period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors successful completion of fargate task for ${var.stack_name}"
  alarm_actions       = [aws_sns_topic.task_success.arn]
  treat_missing_data  = var.treat_missing_data
  datapoints_to_alarm = var.datapoints_to_alarm

  tags = {
    Name    = "${var.stack_name}_task_success_alarm"
    project = var.stack_name
  }

  depends_on = [
    aws_cloudwatch_log_metric_filter.task_success,
    aws_sns_topic.task_success
  ]
}

resource "aws_cloudwatch_metric_alarm" "task_failure" {
  alarm_name          = "${var.stack_name}_task_failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "${var.stack_name}_task_failure_metric"
  namespace           = "Custom/ECSFargate"
  period              = var.period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors failures in fargate task for ${var.stack_name}"
  alarm_actions       = [aws_sns_topic.task_failure.arn]
  treat_missing_data  = var.treat_missing_data
  datapoints_to_alarm = var.datapoints_to_alarm

  tags = {
    Name    = "${var.stack_name}_task_failure_alarm"
    project = var.stack_name
  }

  depends_on = [
    aws_cloudwatch_log_metric_filter.task_failure,
    aws_sns_topic.task_failure
  ]
}

resource "aws_cloudwatch_metric_alarm" "container_exit_failure" {
  alarm_name          = "${var.stack_name}_container_exit_failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.container_exit_evaluation_periods
  metric_name         = "ContainerExitCode"
  namespace           = "AWS/ECS"
  period              = var.container_exit_period
  statistic           = "Maximum"
  threshold           = var.container_exit_threshold
  alarm_description   = "This alarm monitors ECS task exit codes for non-zero values"
  alarm_actions       = [aws_sns_topic.task_failure.arn]
  treat_missing_data  = var.container_missing_data # Infrastructure metric, use "missing" per AWS recommendation
  datapoints_to_alarm = var.datapoints_to_alarm
  ok_actions          = [aws_sns_topic.task_success.arn]

  dimensions = {
    ClusterName = local.ecs_cluster_name
  }

  tags = {
    Name    = "${var.stack_name}_container_exit_failure_alarm"
    project = var.stack_name
  }

  depends_on = [
    aws_sns_topic.task_failure,
    aws_sns_topic.task_success
  ]
}

# EventBridge rules and targets for ECS task state changes
# Documentation: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern.html
resource "aws_cloudwatch_event_rule" "ecs_task_stopped" {
  name        = "${var.stack_name}_task_stopped"
  description = "Capture ECS task stopped events for ${var.stack_name}"
  state       = "ENABLED" # Explicitly enable the rule

  event_pattern = jsonencode({
    source      = ["aws.ecs"],
    detail-type = ["ECS Task State Change"],
    detail = {
      clusterArn    = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.ecs_cluster_name}"],
      lastStatus    = ["STOPPED"],
      stoppedReason = [{ "anything-but" : "Essential container in task exited" }]
    }
  })

  tags = {
    project = var.stack_name
  }
}

resource "aws_cloudwatch_event_target" "ecs_task_stopped_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped.name
  target_id = "${var.stack_name}_ecs_task_stopped_sns"
  arn       = aws_sns_topic.task_failure.arn

  depends_on = [
    aws_cloudwatch_event_rule.ecs_task_stopped,
    aws_sns_topic.task_failure
  ]
}

# AWS chatbot slack configuration
resource "aws_chatbot_slack_channel_configuration" "chatbot_slack" {
  configuration_name = "${var.stack_name}_slack_config"
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.task_success.arn,
    aws_sns_topic.task_failure.arn
  ]
  guardrail_policy_arns = var.guardrail_policies
  logging_level         = var.logging_level

  tags = merge(var.chatbot_tags, {
    project = var.stack_name
  })

  depends_on = [
    aws_iam_role.chatbot_role,
    aws_iam_role_policy_attachment.chatbot_policy_attachment,
    aws_sns_topic.task_success,
    aws_sns_topic.task_failure
  ]
}
