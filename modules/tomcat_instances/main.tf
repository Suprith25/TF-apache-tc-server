# 🐱 modules/tomcat_instances/main.tf - the 3 Apache Tomcat servers
#
# Creates: a firewall (security group), an IAM role (permissions for the servers) and
# the EC2 instances. Each instance runs user_data.sh.tftpl on first boot to install
# Java and Tomcat, so no manual SSH setup is needed.

# An AMI is the machine image (operating system) an instance boots from.
# AWS publishes the newest Amazon Linux 2023 AMI id in an SSM parameter; we read it so we never hardcode an AMI id.
# Latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Firewall for the servers. DEMO ONLY: 8080 and 22 are open to the whole internet.
# In production allow 8080 only from the ALB security group and use SSM Session Manager instead of SSH.
resource "aws_security_group" "tomcat" {
  name_prefix = "${var.name}-tomcat-"
  description = "Allow Tomcat (8080) and SSH from the internet - demo only"
  vpc_id      = var.vpc_id

  ingress {
    description = "Tomcat"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-tomcat-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM = permissions. An instance cannot call AWS APIs unless it has a role.
# This role allows two things: (1) read the CodeDeploy bundle from S3, (2) be managed through SSM.
# ---- IAM role so instances can pull CodeDeploy bundles from S3 (and use SSM instead of SSH)
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# The role. The trust policy above says "the EC2 service may assume (use) this role".
resource "aws_iam_role" "instance" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Least privilege: read-only access to ONE folder of the S3 bucket (the pipeline artifacts), nothing else.
resource "aws_iam_role_policy" "artifact_read" {
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion"]
      Resource = "arn:aws:s3:::${var.artifact_bucket_name}/${var.artifact_prefix}/*"
    }]
  })
}

# AWS-managed policy that lets Systems Manager reach the server (shell access without opening SSH).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# An instance profile is the wrapper that attaches a role to an EC2 instance.
resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.instance.name
}

# count = 3 servers. Server i goes to subnet i (modulo the number of subnets), so they land in different AZs.
# user_data runs once at first boot (installs Java, Tomcat, CodeDeploy agent).
# user_data_replace_on_change = if the script changes, the server is REPLACED so the new script actually runs.
resource "aws_instance" "tomcat" {
  count                       = var.instance_count
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.tomcat.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    tomcat_version = var.tomcat_version
    server_name    = "${var.name}-${count.index + 1}"
    region         = var.region
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name}-${count.index + 1}"
    # The pipeline finds its target servers by this tag, not by instance id.
    CodeDeployGroup = var.name # CodeDeploy deployment group targets this tag
  }
}
