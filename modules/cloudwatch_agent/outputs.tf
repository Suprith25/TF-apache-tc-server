output "log_group_names" {
  value = aws_cloudwatch_log_group.tomcat[*].name
}
