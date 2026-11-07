# One log group per server: tomcat1loggroup, tomcat2loggroup, tomcat3loggroup
resource "aws_cloudwatch_log_group" "tomcat" {
  count             = length(var.instance_ids)
  name              = "tomcat${count.index + 1}loggroup"
  retention_in_days = var.retention_in_days # short retention keeps usage inside the free 5 GB
}

# Let the servers write only to their own log groups
resource "aws_iam_role_policy" "logs" {
  name = "${var.name}-cloudwatch-agent-logs"
  role = var.instance_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = flatten([
        for g in aws_cloudwatch_log_group.tomcat : [g.arn, "${g.arn}:*"]
      ])
    }]
  })
}

# SSM document that installs the agent and ships the Tomcat logs
resource "aws_ssm_document" "install" {
  name          = "${var.name}-install-cloudwatch-agent"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install CloudWatch agent and ship Tomcat logs to a log group"
    parameters = {
      LogGroupName = { type = "String", description = "Target CloudWatch log group" }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "installAndConfigure"
      inputs = { runCommand = split("\n", file("${path.module}/install.sh")) }
    }]
  })
}

# Runs on each server now, and re-checks daily (script is idempotent)
resource "aws_ssm_association" "install" {
  count               = length(var.instance_ids)
  name                = aws_ssm_document.install.name
  association_name    = "${var.name}-cwagent-${count.index + 1}"
  schedule_expression = "rate(1 day)"

  targets {
    key    = "InstanceIds"
    values = [var.instance_ids[count.index]]
  }

  parameters = {
    LogGroupName = aws_cloudwatch_log_group.tomcat[count.index].name
  }

  depends_on = [aws_iam_role_policy.logs]
}
