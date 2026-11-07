# 🐱☁️ Tomcat on AWS with Terraform and a full CI/CD pipeline

🎓 A teaching project. With Terraform you build, on AWS:

1. 🌐 A **network** (VPC, subnets, route table)
2. 🖥️ **Three Apache Tomcat servers** (EC2) behind an **Application Load Balancer** ⚖️
3. 🚀 A **CI/CD pipeline** (AWS CodePipeline) that, every time you push to GitHub, **scans, builds, versions, stores and deploys** a Java WAR file to the three servers, then **tests** it

🗄️ Terraform state is kept in **S3** with **native locking** 🔒 (no DynamoDB needed). Everything runs on AWS ☁️, so nothing is built on your laptop 💻❌.

> 📌 This README is for branch `code-pipeline`. Other branches add more (see [Branches](#-branches)).

---

## 🗺️ 1. The big picture

```
                         git push
   👩‍💻 Developer ─────────────────────────►  🐙 GitHub  (Java project: Suprith25/Java-mini-project)
                                              │ push event (GitHub App)
                                              ▼
 ┌──────────────────────────────  AWS CodePipeline 🚀 ───────────────────────────────┐
 │                                                                                 │
 │  Source ─► CodeScan ─► Build ─► Publish ─► Deploy ─► Test                       │
 │  clone     Semgrep     Maven    store WAR   CodeDeploy  smoke test              │
 │            + Trivy     + auto   in          to 3 servers through the ALB        │
 │                        version  CodeArtifact                                    │
 └─────────────────────────────────────────────────────────────────────────────────┘
                                              │ deploys WAR
                                              ▼
  🌍 Internet ──► ⚖️ ALB :80 ──► 🐱 Tomcat server 1 ┐
                       ├─► 🐱 Tomcat server 2 ├  (EC2 in 3 public subnets, 3 Availability Zones)
                       └─► 🐱 Tomcat server 3 ┘          all inside one VPC
```

Free-tier notes: CodeBuild gives 100 build-min/month (a run takes roughly 6-10 min), 1 CodePipeline V1 pipeline, CodeDeploy on EC2 and CodeArtifact (2 GB) are free. The ALB, public IPv4 addresses and running 3 instances 24/7 are NOT fully free: `terraform destroy` after class.

## Monitoring (branch `cloudwatch0-dashboard`)

CloudWatch dashboard `tomcat-demo-servers` (CPU, network, disk, status checks per server + ALB health/requests/5xx/latency) and one CPU alarm per server (> 90% for 2 x 5 min) that emails via SNS.

`terraform apply` (alerts go to the `alert_email` variable, default `bjsuprith@gmail.com`), then click **Confirm subscription** in the email AWS sends. Dashboard link: `dashboard_url` output.

## Tomcat logs in CloudWatch (branch `cloudwatch-agent-installation`)

The CloudWatch agent is installed on each server through SSM (no server rebuild) and ships `/opt/tomcat/logs/*` (catalina.out, catalina, localhost, access, manager, host-manager) to `tomcat1loggroup`, `tomcat2loggroup`, `tomcat3loggroup`. Logs are kept 7 days. View: Console > CloudWatch > Logs > Log groups.
