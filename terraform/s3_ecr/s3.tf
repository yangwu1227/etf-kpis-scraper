resource "aws_s3_bucket" "s3_bucket" {
  bucket        = replace(var.stack_name, "_", "-")
  force_destroy = true

  tags = local.tags
}
