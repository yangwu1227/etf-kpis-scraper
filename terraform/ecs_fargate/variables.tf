variable "profile" {
  description = "The AWS credentials profile to use for deployment"
  type        = string
}

variable "stack_name" {
  description = "The name of the stack, used for tagging and resource identification"
  type        = string
}

variable "cpu_architecture" {
  description = "The CPU architecture of the task (e.g., X86_64)"
  type        = string
}

variable "operating_system_family" {
  description = "The operating system family of the task (e.g., LINUX)"
  type        = string
}

variable "cpu" {
  description = "The number of CPU units to reserve for the container"
  type        = number
}

variable "memory" {
  description = "The amount of memory (in MiB) to reserve for the container"
  type        = number
}

variable "size_in_gib" {
  description = "The amount of ephemeral storage (in GiB) to reserve for the container"
  type        = number
}

variable "environment_file_s3_arn" {
  description = "The S3 ARN of the environment file for the container"
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
