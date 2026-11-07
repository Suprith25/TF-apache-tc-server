# ⚖️ modules/alb/variables.tf - inputs: name prefix, VPC id, subnets, and the instance ids to balance

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "instance_ids" { type = list(string) }
