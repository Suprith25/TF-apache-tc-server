# 🌐 modules/vpc/main.tf - the network
#
# Builds a VPC (your own private network in AWS) with public subnets that can reach
# the internet:
#
#    Internet <-> Internet Gateway <-> Route table (0.0.0.0/0) <-> 3 public subnets
#
# A subnet is "public" when its route table sends internet traffic to an Internet Gateway.

# Ask AWS which Availability Zones (separate data centres) exist in this region.
# Spreading subnets over several AZs keeps the app up if one data centre fails.
data "aws_availability_zones" "available" {
  state = "available"
}

# The VPC itself. DNS support lets instances resolve names like AWS service endpoints.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

# The door between the VPC and the internet.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# count = one subnet per CIDR in the list. count.index is 0,1,2.
# map_public_ip_on_launch gives every server in it a public IP automatically.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${count.index + 1}" }
}

# Route table = the VPC's road map. This rule says: anything not local (0.0.0.0/0) goes out via the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

# Attach the route table to each subnet (otherwise the subnet would not be public).
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
