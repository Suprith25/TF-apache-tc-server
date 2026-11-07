locals {
  # EC2 basic monitoring publishes every 5 minutes (free). Detailed (1-min) monitoring costs extra.
  period = 300
}

# ---------------- Alerts: SNS topic + email ----------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS sends a confirmation email: click "Confirm subscription"
}

# ---------------- One CPU alarm per server ----------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = length(var.instance_ids)
  alarm_name          = "${var.name}-${count.index + 1}-cpu-above-${var.cpu_threshold}"
  alarm_description   = "CPU utilization on ${var.name}-${count.index + 1} is above ${var.cpu_threshold}% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.instance_ids[count.index] }
  statistic           = "Average"
  period              = local.period
  evaluation_periods  = 2 # 2 x 5 min = sustained, avoids alerting on a short spike
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------- Dashboard ----------------
locals {
  per_instance = { for i, id in var.instance_ids : id => "${var.name}-${i + 1}" }

  ec2_metric = { for m in ["CPUUtilization", "NetworkIn", "NetworkOut", "StatusCheckFailed", "DiskReadOps", "DiskWriteOps"] :
    m => [for id, label in local.per_instance : ["AWS/EC2", m, "InstanceId", id, { label = label }]]
  }

  widgets = [
    {
      type       = "text", x = 0, y = 0, width = 24, height = 2
      properties = { markdown = "# ${var.name}: 3 Tomcat servers\nEC2 basic monitoring (5-minute data). CPU alarm threshold: **${var.cpu_threshold}%**." }
    },
    {
      type = "alarm", x = 0, y = 2, width = 8, height = 6
      properties = {
        title  = "CPU > ${var.cpu_threshold}% alarms"
        alarms = [for a in aws_cloudwatch_metric_alarm.cpu_high : a.arn]
      }
    },
    {
      type = "metric", x = 8, y = 2, width = 16, height = 6
      properties = {
        title   = "CPU utilization (%)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Average"
        period  = local.period
        metrics = local.ec2_metric["CPUUtilization"]
        yAxis   = { left = { min = 0, max = 100 } }
        annotations = {
          horizontal = [{ label = "Alarm threshold", value = var.cpu_threshold, color = "#d62728" }]
        }
      }
    },
    {
      type = "metric", x = 0, y = 8, width = 12, height = 6
      properties = {
        title   = "Network in (bytes)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = local.period
        metrics = local.ec2_metric["NetworkIn"]
      }
    },
    {
      type = "metric", x = 12, y = 8, width = 12, height = 6
      properties = {
        title   = "Network out (bytes)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = local.period
        metrics = local.ec2_metric["NetworkOut"]
      }
    },
    {
      type = "metric", x = 0, y = 14, width = 8, height = 6
      properties = {
        title   = "Status check failed (0 = healthy)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Maximum"
        period  = local.period
        metrics = local.ec2_metric["StatusCheckFailed"]
      }
    },
    {
      type = "metric", x = 8, y = 14, width = 8, height = 6
      properties = {
        title   = "Disk read ops"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = local.period
        metrics = local.ec2_metric["DiskReadOps"]
      }
    },
    {
      type = "metric", x = 16, y = 14, width = 8, height = 6
      properties = {
        title   = "Disk write ops"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = local.period
        metrics = local.ec2_metric["DiskWriteOps"]
      }
    },
    {
      type = "metric", x = 0, y = 20, width = 8, height = 6
      properties = {
        title  = "ALB healthy / unhealthy servers"
        region = var.region
        view   = "timeSeries"
        stat   = "Average"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { label = "Healthy" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { label = "Unhealthy" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 20, width = 8, height = 6
      properties = {
        title  = "ALB requests and 5xx errors"
        region = var.region
        view   = "timeSeries"
        stat   = "Sum"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "Requests" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "Target 5xx" }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "ELB 5xx" }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 20, width = 8, height = 6
      properties = {
        title  = "ALB response time (s)"
        region = var.region
        view   = "timeSeries"
        stat   = "Average"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { label = "Avg response time" }],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-servers"
  dashboard_body = jsonencode({ widgets = local.widgets })
}
