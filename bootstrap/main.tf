# 🪣 bootstrap/main.tf - one-time setup of the S3 bucket that stores Terraform state
#
# CHICKEN-AND-EGG: the main project keeps its state in S3, but S3 must exist first.
# So this tiny separate project creates the bucket using LOCAL state.
# Run it once:  cd bootstrap && terraform init && terraform apply -var bucket_name=<unique-name>
# S3 bucket names are global across all AWS accounts, so pick a unique one.

# Run this ONCE (local state) to create the S3 bucket that holds the main project's state.
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform state"
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name
}

# Versioning keeps old copies of the state file, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt everything in the bucket at rest (AES-256).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Hard safety switch: this bucket can never be made public by mistake.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value = aws_s3_bucket.state.id
}
