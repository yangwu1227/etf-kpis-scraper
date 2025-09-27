variable "profile" {
  description = "The AWS credentials profile to use for deployment"
  type        = string
}

variable "stack_name" {
  description = "The name of the stack, used for tagging and resource identification"
  type        = string
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function (e.g., python3.12)"
  type        = string
}

variable "lambda_handler" {
  description = "The entry point for the Lambda function"
  type        = string
}

variable "lambda_architecture" {
  description = "Lambda architecture (e.g., x86_64, arm64)"
  type        = string
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
}

variable "lambda_code_s3_bucket" {
  description = "Name of the S3 bucket for where the zippped Lambda function code is stored"
  type        = string
}

variable "lambda_code_s3_key" {
  description = "S3 key for the zippped Lambda function code"
  type        = string
}

variable "schedule_expression" {
  description = "Schedule expression for the EventBridge rule"
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket for IAM Terraform state files"
  type        = string
}

variable "iam_terraform_state_key" {
  description = "S3 key for IAM Terraform state"
  type        = string
}

variable "s3_ecr_terraform_state_key" {
  description = "S3 key for S3 and ECR Terraform state"
  type        = string
}

variable "vpc_terraform_state_key" {
  description = "S3 key for VPC Terraform state"
  type        = string

}

variable "ecs_fargate_state_key" {
  description = "S3 key for ECS Fargate Terraform state"
  type        = string
}

variable "assign_public_ip" {
  description = "Assign a public IP to the ECS Fargate task"
  type        = string
}

variable "env" {
  description = "Environment for the stack (e.g., dev, prod)"
  type        = string
}
