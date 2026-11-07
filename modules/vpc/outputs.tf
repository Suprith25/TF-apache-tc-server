# 🌐 modules/vpc/outputs.tf - IDs other modules need (servers and load balancer live inside this VPC)

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
