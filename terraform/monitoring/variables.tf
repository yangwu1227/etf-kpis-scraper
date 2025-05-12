variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
}

variable "profile" {
  description = "The AWS credentials profile to use for deployment"
  type        = string
}

variable "stack_name" {
  description = "The name of the stack, used for tagging and resource identification"
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state files"
  type        = string
}

variable "ecs_fargate_state_key" {
  description = "S3 key for ECS Fargate Terraform state"
  type        = string
}

variable "slack_workspace_id" {
  description = "The ID of the Slack workspace/team to send notifications to (used as slack_team_id)"
  type        = string
}

variable "slack_channel_id" {
  description = "The ID of the Slack channel to send notifications to"
  type        = string
}

variable "success_pattern" {
  description = "Log pattern that indicates task success"
  type        = string
  default     = "[SUCCESS]"
}

variable "failure_pattern" {
  description = "Log pattern that indicates task failure"
  type        = string
  default     = "[ERROR]"
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate for the alarm"
  type        = number
  default     = 1
}

variable "period" {
  description = "Duration in seconds to evaluate the metric"
  type        = number
  default     = 60
}

variable "treat_missing_data" {
  description = "How to treat missing data in CloudWatch alarms (missing, ignore, breaching, notBreaching)"
  type        = string
  default     = "notBreaching"
  validation {
    condition     = contains(["missing", "ignore", "breaching", "notBreaching"], var.treat_missing_data)
    error_message = "The treat_missing_data value must be one of: missing, ignore, breaching, notBreaching."
  }
}

variable "datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger the alarm"
  type        = number
  default     = 1
}

variable "logging_level" {
  description = "Specifies the logging level for ChatBot configuration (ERROR, INFO, or NONE)"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["ERROR", "INFO", "NONE"], var.logging_level)
    error_message = "Logging level must be one of: ERROR, INFO, or NONE."
  }
}

variable "chatbot_tags" {
  description = "Tags to add to the ChatBot configuration"
  type        = map(string)
  default     = {}
}

variable "guardrail_policies" {
  description = "List of IAM policy ARNs that are applied as channel guardrails (used as guardrail_policy_arns)"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]
}

variable "chatbot_policies" {
  description = "List of IAM permissions for the policy to attach to the ChatBot role"
  type        = list(string)
  default = [
    "cloudwatch:Describe*",
    "cloudwatch:Get*",
    "cloudwatch:List*",
    "logs:Get*",
    "logs:List*",
    "logs:Describe*",
    "logs:TestMetricFilter",
    "logs:FilterLogEvents",
    "sns:Get*",
    "sns:List*",
    "ecs:DescribeTasks"
  ]
}

# Add these new variables for SNS delivery policy
variable "sns_min_delay_target" {
  description = "The minimum delay for SNS delivery retries (in seconds)"
  type        = number
  default     = 1
  validation {
    condition     = var.sns_min_delay_target >= 1 && var.sns_min_delay_target <= 3600
    error_message = "Minimum delay must be between 1 and 3600 seconds."
  }
}

variable "sns_max_delay_target" {
  description = "The maximum delay for SNS delivery retries (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.sns_max_delay_target >= 1 && var.sns_max_delay_target <= 3600
    error_message = "Maximum delay must be between 1 and 3600 seconds."
  }
}

variable "sns_num_retries" {
  description = "The total number of SNS delivery retries"
  type        = number
  default     = 50
  validation {
    condition     = var.sns_num_retries >= 0 && var.sns_num_retries <= 100
    error_message = "Number of retries must be between 0 and 100."
  }
}

variable "sns_num_no_delay_retries" {
  description = "The number of SNS delivery retries with no delay"
  type        = number
  default     = 3
}

variable "sns_num_min_delay_retries" {
  description = "The number of SNS delivery retries with minimum delay"
  type        = number
  default     = 2
}

variable "sns_backoff_function" {
  description = "The backoff function for SNS delivery retries"
  type        = string
  default     = "exponential"
  validation {
    condition     = contains(["arithmetic", "exponential", "geometric", "linear"], var.sns_backoff_function)
    error_message = "Backoff function must be one of: arithmetic, exponential, geometric, linear."
  }
}
