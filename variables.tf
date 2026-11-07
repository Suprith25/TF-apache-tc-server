# 🎛️ variables.tf - INPUTS of the root module (the knobs you can change)
#
# Each variable has a default, so "terraform apply" works out of the box.
# Override one with:  terraform apply -var instance_type=t2.micro
# or put values in a terraform.tfvars file (git-ignored).

# AWS region everything is created in (Mumbai).
variable "region" {
  type    = string
  default = "ap-south-1"
}

# Prefix used in the names of almost every resource (tomcat-demo-vpc, tomcat-demo-alb ...).
variable "project_name" {
  type    = string
  default = "tomcat-demo"
}

# IP range of the private network. 10.0.0.0/16 = about 65,000 addresses.
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# One CIDR block per subnet. 3 entries = 3 subnets, each placed in a different Availability Zone.
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# Free tier: t3.micro (newer accounts) or t2.micro (older accounts / some regions)
variable "instance_type" {
  type    = string
  default = "t3.micro"
}

# Tomcat release the servers install.
variable "tomcat_version" {
  type    = string
  default = "10.1.34"
}

# --- CI/CD settings ---
# The GitHub repository the pipeline builds, in owner/repo form.
variable "github_repo" {
  type        = string
  default     = "Suprith25/Java-mini-project"
  description = "Java project to build, as owner/repo"
}

# Folder inside that repo which contains pom.xml (Maven's project file).
variable "app_dir" {
  type    = string
  default = "sample-app" # folder in the repo containing pom.xml
}

# Name of the WAR file. Tomcat serves it at /<war_name>/ (this is called the "context path").
variable "war_name" {
  type    = string
  default = "sample" # <finalName> in the pom; also the Tomcat context path
}

# Branch to watch. A push to this branch starts the pipeline.
variable "github_branch" {
  type    = string
  default = "main"
}

# Version prefix. Final WAR version = this + CodeBuild build number, e.g. 1.0.7.
variable "app_major_minor" {
  type        = string
  default     = "1.0"
  description = "WAR version = <this>.<CodeBuild build number>. Bump to 1.1, 2.0 ... for releases"
}

# Existing bucket reused for pipeline artifacts. Pipeline roles can only touch their own folders in it, never the state file.
variable "artifact_bucket_name" {
  type        = string
  default     = "tfprojecttcbucket" # same bucket that holds the Terraform state
  description = "Existing S3 bucket used for CodePipeline artifacts and deploy files"
}
