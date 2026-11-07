variable "name" { type = string }
variable "instance_ids" { type = list(string) }
variable "instance_role_name" { type = string }
variable "retention_in_days" {
  type    = number
  default = 7
}
