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

## CI/CD with AWS CodePipeline (branch `code-pipeline`)

Source (GitHub: `Suprith25/Java-mini-project`) -> CodeScan (Semgrep SAST + Trivy deps/secrets) -> Build (Maven test + package, auto-version) -> Publish (versioned WAR to CodeArtifact) -> Deploy (CodeDeploy to all 3 Tomcats in parallel) -> Test (smoke test via ALB checks the new version).

Everything runs on AWS. A `git push` to the repo's `main` branch triggers the pipeline automatically. Nothing is built locally.

1. `terraform apply`
2. Console > Developer Tools > Settings > Connections: open the `github_connection_arn` connection and click **Update pending connection** (one-time).
3. Push a change to the Java repo; watch CodePipeline. App: `app_url` output (`/sample/`, `/sample/hello`, `/sample/version.txt`).
4. Versions: WAR = `app_major_minor` + build number (e.g. 1.0.7), stored in CodeArtifact as `sample-1.0.7.war`.

Free-tier notes: CodeBuild gives 100 build-min/month (a run takes roughly 6-10 min), 1 CodePipeline V1 pipeline, CodeDeploy on EC2 and CodeArtifact (2 GB) are free. The ALB, public IPv4 addresses and running 3 instances 24/7 are NOT fully free: `terraform destroy` after class.
