# 🐱 modules/tomcat_instances/outputs.tf - public IPs, direct URLs (port 8080) and instance ids

output "public_ips" {
  value = aws_instance.tomcat[*].public_ip
}

output "urls" {
  value = [for i in aws_instance.tomcat : "http://${i.public_ip}:8080"]
}

output "instance_ids" {
  value = aws_instance.tomcat[*].id
}

output "instance_role_name" {
  value = aws_iam_role.instance.name
}
