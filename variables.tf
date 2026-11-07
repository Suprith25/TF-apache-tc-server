variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "tomcat-demo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# Free tier: t3.micro (newer accounts) or t2.micro (older accounts / some regions)
variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "tomcat_version" {
  type    = string
  default = "10.1.34"
}

variable "github_repo" {
  type        = string
  default     = "Suprith25/Java-mini-project"
  description = "Java project to build, as owner/repo"
}

variable "app_dir" {
  type    = string
  default = "sample-app" # folder in the repo containing pom.xml
}

variable "war_name" {
  type    = string
  default = "sample" # <finalName> in the pom; also the Tomcat context path
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "app_major_minor" {
  type        = string
  default     = "1.0"
  description = "WAR version = <this>.<CodeBuild build number>. Bump to 1.1, 2.0 ... for releases"
}

variable "artifact_bucket_name" {
  type        = string
  default     = "tfprojecttcbucket" # same bucket that holds the Terraform state
  description = "Existing S3 bucket used for CodePipeline artifacts and deploy files"
}

variable "alert_email" {
  type        = string
  default     = "bjsuprith@gmail.com"
  description = "Email that receives CloudWatch alarm notifications (AWS sends a confirmation link)"
}

variable "cpu_alarm_threshold" {
  type    = number
  default = 90
}
