# Tomcat on EC2 (Terraform demo)

VPC module (VPC, 3 public subnets, IGW, route table) + tomcat module (3 free-tier EC2 instances running Apache Tomcat on :8080). State lives in S3 with native locking (`use_lockfile`, Terraform >= 1.10, no DynamoDB).

## Steps
1. Create the state bucket (once):
   `cd bootstrap && terraform init && terraform apply -var bucket_name=<unique-name>`
2. Put that name in `versions.tf` (`backend "s3"` -> `bucket`).
3. `terraform init && terraform apply`
4. Open the `tomcat_urls` outputs (give it ~2-3 min after apply for install). `/hello.html` shows the server name.
5. Teardown: `terraform destroy`, then destroy `bootstrap` (empty the bucket first).

Notes: `t3.micro` is free tier on newer accounts; use `-var instance_type=t2.micro` on older ones. SG opens 22/8080 to the world — demo only.
