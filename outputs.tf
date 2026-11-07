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

output "alb_url" {
  description = "Load-balanced URL (refresh to see /hello.html rotate between servers)"
  value       = "http://${module.alb.alb_dns_name}/hello.html"
}

output "github_connection_arn" {
  description = "Authorize this connection once in Console > Developer Tools > Connections"
  value       = module.cicd.connection_arn
}

output "pipeline_name" {
  value = module.cicd.pipeline_name
}

output "app_url" {
  value = "http://${module.alb.alb_dns_name}/${var.war_name}/"
}
