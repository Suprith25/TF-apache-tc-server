variable "name" { type = string }
variable "region" { type = string }
variable "instance_ids" { type = list(string) }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "alert_email" { type = string }
variable "cpu_threshold" {
  type    = number
  default = 90
}
