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
