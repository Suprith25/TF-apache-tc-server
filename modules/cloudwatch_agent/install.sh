set -e
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/tomcat/logs/catalina.out",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-catalina-out",
            "timestamp_format": "%d-%b-%Y %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          },
          {
            "file_path": "/opt/tomcat/logs/catalina.*.log",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-catalina",
            "timestamp_format": "%d-%b-%Y %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          },
          {
            "file_path": "/opt/tomcat/logs/localhost.*.log",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-localhost",
            "timestamp_format": "%d-%b-%Y %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          },
          {
            "file_path": "/opt/tomcat/logs/localhost_access_log.*.txt",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-access",
            "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
          },
          {
            "file_path": "/opt/tomcat/logs/manager.*.log",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-manager",
            "timestamp_format": "%d-%b-%Y %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          },
          {
            "file_path": "/opt/tomcat/logs/host-manager.*.log",
            "log_group_name": "{{LogGroupName}}",
            "log_stream_name": "{instance_id}-host-manager",
            "timestamp_format": "%d-%b-%Y %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          }
        ]
      }
    }
  }
}
JSON

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
