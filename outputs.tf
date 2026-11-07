# 📤 outputs.tf - values Terraform prints after "apply"
#
# Outputs are how a module tells the outside world something useful (URLs, IDs).
# Show them again any time with:  terraform output

# ID of the VPC (handy when looking at it in the AWS console).
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "tomcat_urls" {
  description = "Open these in a browser"
  value       = module.tomcat.urls
}

output "public_ips" {
  value = module.tomcat.public_ips
}

# Load balancer test URL. Refresh it and the page text changes between servers 1, 2 and 3.
output "alb_url" {
  description = "Load-balanced URL (refresh to see /hello.html rotate between servers)"
  value       = "http://${module.alb.alb_dns_name}/hello.html"
}

# The GitHub connection starts in PENDING state. A human must authorize it once in the console.
output "github_connection_arn" {
  description = "Authorize this connection once in Console > Developer Tools > Connections"
  value       = module.cicd.connection_arn
}

output "pipeline_name" {
  value = module.cicd.pipeline_name
}

# Where your deployed Java app is available once the pipeline has run.
output "app_url" {
  value = "http://${module.alb.alb_dns_name}/${var.war_name}/"
}

output "dashboard_url" {
  description = "CloudWatch dashboard for the 3 servers"
  value       = module.monitoring.dashboard_url
}

output "cpu_alarms" {
  value = module.monitoring.alarm_names
}

output "tomcat_log_groups" {
  description = "One CloudWatch log group per Tomcat server"
  value       = module.cloudwatch_agent.log_group_names
}
