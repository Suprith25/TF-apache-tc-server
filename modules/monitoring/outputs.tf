output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  value = aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name
}
