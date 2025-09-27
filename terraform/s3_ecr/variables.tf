variable "profile" {
  description = "The AWS credentials profile to use for deployment"
  type        = string
}

variable "stack_name" {
  description = "The name of the stack, used for tagging and resource identification"
  type        = string
}

variable "retained_image_count" {
  description = "Number of images to retain with a specific tag"
  type        = number
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images will expire"
  type        = number
}
