terraform {
  required_version = ">= 1.10.0" # S3 native state locking (use_lockfile) needs 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 with native locking (no DynamoDB table needed).
  # Replace the bucket name with the one you created in ./bootstrap
  backend "s3" {
    bucket       = "tfprojecttcbucket"
    profile = "jenkins-infra"
    key          = "tomcat-demo/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
