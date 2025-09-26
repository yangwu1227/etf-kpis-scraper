locals {
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
}

# SNS topics for notifications for both success and failure
resource "aws_sns_topic" "notifications" {
  for_each = toset(local.sns_topics_names)

  name = "${var.stack_name}_${each.value}"

  delivery_policy = jsonencode({ http = local.http })

  tags = local.tags
}

# IAM policy documents for each topic
data "aws_iam_policy_document" "publish_to_sns" {
  for_each = toset(local.sns_topics_names)

  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.notifications[each.value].arn]

    # This allows Eventbridge and CloudWatch to publish to the SNS topics
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

# Apply policies to respective topics
resource "aws_sns_topic_policy" "publish_to_sns_policy" {
  for_each = toset(local.sns_topics_names)

  arn    = aws_sns_topic.notifications[each.value].arn
  policy = data.aws_iam_policy_document.publish_to_sns[each.value].json

  depends_on = [
    aws_sns_topic.notifications,
    data.aws_iam_policy_document.publish_to_sns,
  ]
}
