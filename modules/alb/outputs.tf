# ⚖️ modules/alb/outputs.tf - DNS name (the public URL), security group id and target group name

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_name" {
  value = aws_lb_target_group.tomcat.name
}
