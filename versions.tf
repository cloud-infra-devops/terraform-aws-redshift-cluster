terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.25.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
  cloud {
    organization = "cloud-infra-dev"
    workspaces {
      name    = "testing-terraform-aws-modules" # Workspace with VCS driven workflow
      project = "AWS-Cloud-IaC"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}
