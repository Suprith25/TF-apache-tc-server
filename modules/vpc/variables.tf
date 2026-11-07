# 🌐 modules/vpc/variables.tf - inputs: name prefix, VPC CIDR, list of subnet CIDRs

variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "public_subnet_cidrs" { type = list(string) }
