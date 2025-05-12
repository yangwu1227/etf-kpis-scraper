# Define log group for ECS tasks and get reference to ecs cluster
locals {
  log_group_name   = "/aws/ecs/${var.stack_name}"
  ecs_cluster_name = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_cluster_name
}

# SNS topics for notifications
resource "aws_sns_topic" "success" {
  name = "${var.stack_name}_success"

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
    Name    = "${var.stack_name}_success"
    project = var.stack_name
  }
}

resource "aws_sns_topic" "failure" {
  name = "${var.stack_name}_failure"

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
    Name    = "${var.stack_name}_failure"
    project = var.stack_name
  }
}

# Create separate policy documents for each topic
data "aws_iam_policy_document" "events_to_sns_success" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.success.arn]

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
    resources = [aws_sns_topic.failure.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

# Apply policies to respective topics
resource "aws_sns_topic_policy" "events_to_success_sns" {
  arn    = aws_sns_topic.success.arn
  policy = data.aws_iam_policy_document.events_to_sns_success.json
}

resource "aws_sns_topic_policy" "events_to_failure_sns" {
  arn    = aws_sns_topic.failure.arn
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
        Action   = var.chatbot_policies
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

# CloudWatch log filters and alarms
resource "aws_cloudwatch_log_metric_filter" "success" {
  name           = "${var.stack_name}_success"
  pattern        = var.success_pattern
  log_group_name = local.log_group_name

  metric_transformation {
    name          = "${var.stack_name}_success_metric"
    namespace     = "Custom/ECSFargate"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "failure" {
  name           = "${var.stack_name}_failure"
  pattern        = var.failure_pattern
  log_group_name = local.log_group_name

  metric_transformation {
    name          = "${var.stack_name}_failure_metric"
    namespace     = "Custom/ECSFargate"
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "success" {
  alarm_name          = "${var.stack_name}_success"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "${var.stack_name}_success_metric"
  namespace           = "Custom/ECSFargate"
  period              = var.period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors successful completion of fargate task for ${var.stack_name}"
  alarm_actions       = [aws_sns_topic.success.arn]
  treat_missing_data  = var.treat_missing_data
  datapoints_to_alarm = var.datapoints_to_alarm

  tags = {
    Name    = "${var.stack_name}_success_alarm"
    project = var.stack_name
  }

  depends_on = [
    aws_cloudwatch_log_metric_filter.success,
    aws_sns_topic.success
  ]
}

resource "aws_cloudwatch_metric_alarm" "failure" {
  alarm_name          = "${var.stack_name}_failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "${var.stack_name}_failure_metric"
  namespace           = "Custom/ECSFargate"
  period              = var.period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors failures in fargate task for ${var.stack_name}"
  alarm_actions       = [aws_sns_topic.failure.arn]
  treat_missing_data  = var.treat_missing_data
  datapoints_to_alarm = var.datapoints_to_alarm

  tags = {
    Name    = "${var.stack_name}_failure_alarm"
    project = var.stack_name
  }

  depends_on = [
    aws_cloudwatch_log_metric_filter.failure,
    aws_sns_topic.failure
  ]
}

# EventBridge rules and targets for ECS task state changes
# Event bridge examples: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern.html
# Describe task API: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeTasks.html
resource "aws_cloudwatch_event_rule" "task_exit_failure" {
  name        = "${var.stack_name}_task_exit_failure"
  description = "Match tasks with certain stopped codes"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.ecs"],
    detail-type = ["ECS Task State Change"],
    # Task-level failures (not container-level failure, which is handled by cloudwatch alarms): https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Task.html
    detail = {
      clusterArn = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.ecs_cluster_name}"],
      lastStatus = ["STOPPED"],
      # EssentialContainerExited is already covered by the cloudwatch alarm with log metric filter
      stopCode = [{ "anything-but" : ["UserInitiated", "ServiceSchedulerInitiated", "EssentialContainerExited"] }]
    }
  })

  tags = {
    project = var.stack_name
  }
}

resource "aws_cloudwatch_event_target" "ecs_task_stopped_to_sns" {
  rule      = aws_cloudwatch_event_rule.task_exit_failure.name
  target_id = "${var.stack_name}_ecs_task_stopped_sns"
  arn       = aws_sns_topic.failure.arn

  depends_on = [
    aws_cloudwatch_event_rule.task_exit_failure,
    aws_sns_topic.failure
  ]
}

# AWS chatbot slack configuration
resource "aws_iam_policy" "additional_guardrail_policy" {
  name        = "${var.stack_name}_additional_guardrail_policy"
  description = "Additional guardrail policy for AWS chatbot"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_chatbot_slack_channel_configuration" "chatbot_slack" {
  configuration_name = "${var.stack_name}_slack_config"
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.success.arn,
    aws_sns_topic.failure.arn
  ]
  guardrail_policy_arns = concat(var.guardrail_policies, [aws_iam_policy.additional_guardrail_policy.arn])
  logging_level         = var.logging_level

  tags = merge(var.chatbot_tags, {
    project = var.stack_name
  })

  depends_on = [
    aws_iam_role.chatbot_role,
    aws_iam_role_policy_attachment.chatbot_policy_attachment,
    aws_sns_topic.success,
    aws_sns_topic.failure
  ]
}
