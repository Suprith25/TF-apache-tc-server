# 🚀 modules/cicd/variables.tf - inputs: names, GitHub repo/branch, version prefix, app folder and WAR name, scan strictness (trivy_*)

variable "name" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "artifact_bucket_name" { type = string }
variable "github_repo" {
  type        = string
  description = "owner/repo of the Java project"
}
variable "github_branch" {
  type    = string
  default = "main"
}
variable "major_minor" {
  type        = string
  default     = "1.0"
  description = "Base version; build number is appended: MAJOR.MINOR.<build>"
}
variable "codedeploy_tag_value" {
  type        = string
  description = "Value of the CodeDeployGroup tag on the target EC2 instances"
}
variable "app_url" {
  type        = string
  description = "Public base URL (ALB) used by the test stage"
}
# Trivy only reports vulnerabilities of this severity or worse. CRITICAL keeps the demo from failing too often.
variable "trivy_severity" {
  type    = string
  default = "CRITICAL"
}
# "1" = fail the pipeline when something is found. Use "0" for report-only mode.
variable "trivy_exit_code" {
  type    = string
  default = "1"
}
variable "app_dir" {
  type        = string
  default     = "sample-app"
  description = "Folder inside the GitHub repo that holds pom.xml"
}
variable "war_name" {
  type        = string
  default     = "sample"
  description = "<finalName> in the pom = WAR file name = Tomcat context path"
}
