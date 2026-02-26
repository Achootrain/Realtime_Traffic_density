terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # For production, uncomment and configure remote backend:
  # backend "s3" {
  #   bucket         = "traffic-system-tfstate"
  #   key            = "terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

data "local_file" "aws_credentials" {
  filename = pathexpand(var.aws_credentials_csv_path)
}

locals {
  aws_creds = csvdecode(data.local_file.aws_credentials.content)
}

provider "aws" {
  region     = var.aws_region
  access_key = local.aws_creds[0]["Access key ID"]
  secret_key = local.aws_creds[0]["Secret access key"]

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
