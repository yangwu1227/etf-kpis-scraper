terraform {
  backend "s3" {
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket  = var.terraform_state_bucket
    key     = var.iam_terraform_state_key
    region  = var.region
    profile = var.profile
  }
}

data "terraform_remote_state" "s3_ecr" {
  backend = "s3"
  config = {
    bucket  = var.terraform_state_bucket
    key     = var.s3_ecr_terraform_state_key
    region  = var.region
    profile = var.profile
  }
}
