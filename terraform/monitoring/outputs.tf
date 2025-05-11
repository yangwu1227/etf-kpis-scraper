output "success_sns_topic_arn" {
  description = "ARN of the SNS topic for task success notifications"
  value       = aws_sns_topic.success.arn
}

output "failure_sns_topic_arn" {
  description = "ARN of the SNS topic for task failure notifications"
  value       = aws_sns_topic.failure.arn
}

output "chatbot_config_arn" {
  description = "ARN of the AWS chatbot slack channel configuration"
  value       = aws_chatbot_slack_channel_configuration.chatbot_slack.chat_configuration_arn
}
