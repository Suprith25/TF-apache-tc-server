# 🐱 modules/tomcat_instances/variables.tf - inputs: network ids, how many servers, instance type, Tomcat version, artifact bucket

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "instance_count" {
  type    = number
  default = 3
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "tomcat_version" {
  type    = string
  default = "10.1.34"
}
variable "region" { type = string }
variable "artifact_bucket_name" { type = string }
variable "artifact_prefix" { type = string }
