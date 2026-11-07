# 🧰 versions.tf - Terraform + provider versions and the REMOTE STATE backend
#
# WHAT: Tells Terraform which version it needs, which providers to download
# (here only AWS), and WHERE to store the state file.
# WHY: The "state file" is Terraform's memory of what it created. Keeping it in S3
# (instead of on your laptop) lets a team share it and survive a lost laptop.

terraform {
  # Minimum Terraform CLI version. 1.10 added S3-native state locking.
  required_version = ">= 1.10.0" # S3 native state locking (use_lockfile) needs 1.10+

  # A provider is a plugin that knows how to talk to one platform (AWS here).
  # "~> 5.0" means any 5.x release, but never 6.0 (avoids breaking changes).
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 with native locking (no DynamoDB table needed).
  # Replace the bucket name with the one you created in ./bootstrap
  # Backend = where state lives. The bucket must ALREADY exist (created by ./bootstrap).
  # Variables are NOT allowed inside a backend block, so values are written literally.
  #   bucket       - S3 bucket that stores the state
  #   profile      - which local AWS CLI profile Terraform uses to reach the bucket
  #   key          - path of the state file inside the bucket (the "file name")
  #   encrypt      - encrypt the state at rest (state can contain sensitive values)
  #   use_lockfile - lock using a ".tflock" file in S3 so two people cannot
  #                  run apply at the same time (no DynamoDB table needed)
  backend "s3" {
    bucket       = "tfprojecttcbucket"
    profile      = "jenkins-infra"
    key          = "tomcat-demo/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
