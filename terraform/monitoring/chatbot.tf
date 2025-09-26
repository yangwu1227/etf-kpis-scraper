# Chatbot role, policy, and attachment
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

  tags = local.tags
}

resource "aws_iam_policy" "chatbot_policy" {
  name        = "${var.stack_name}_chatbot_policy"
  description = "Policy for AWS ChatBot to access aws resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = var.chatbot_actions
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

# Channel guardrail policies
resource "aws_iam_policy" "guardrail_ecs_policy" {
  name        = "${var.stack_name}_guardrail_ecs_policy"
  description = "Guardrail policy for AWS chatbot to restrict ECS actions users can perform from slack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = var.chatbot_guardrail_ecs_actions
        Resource = "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task/${local.ecs_cluster_name}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "guardrail_logs_policy" {
  name        = "${var.stack_name}_guardrail_logs_policy"
  description = "Guardrail policy for AWS chatbot to restrict CloudWatch logs actions users can perform from slack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = var.chatbot_guardrail_logs_actions
        Resource = "arn:aws:logs:${local.aws_region}:${local.aws_account_id}:log-group:/ecs/${local.ecs_cluster_name}"
      }
    ]
  })
}

# Slack configuration
resource "aws_chatbot_slack_channel_configuration" "chatbot_slack" {
  configuration_name = "${var.stack_name}_slack_config"
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [for topic_arn in aws_sns_topic.notifications : topic_arn.arn]
  guardrail_policy_arns = [
    aws_iam_policy.guardrail_ecs_policy.arn,
    aws_iam_policy.guardrail_logs_policy.arn
  ]
  logging_level = var.logging_level

  tags = local.tags

  depends_on = [
    aws_iam_role.chatbot_role,
    aws_iam_policy.chatbot_policy,
    aws_iam_role_policy_attachment.chatbot_policy_attachment,
    aws_iam_policy.guardrail_ecs_policy,
    aws_iam_policy.guardrail_logs_policy,
    aws_sns_topic.notifications
  ]
}
