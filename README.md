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

## 📖 2. Concepts you will meet (glossary)

| Term | Plain-English meaning | Where it appears |
|---|---|---|
| 🧱 **Terraform** | Describe infrastructure as code; Terraform makes AWS match it | every `.tf` file |
| 🧩 **Module** | A reusable folder of Terraform code with inputs and outputs | `modules/*` |
| 🧠 **State file** | Terraform's memory of what it created | stored in S3 |
| 🔒 **State locking** | Stops two people applying at once | `use_lockfile = true` in `versions.tf` |
| 🌐 **VPC / subnet** | Your private network / a slice of it in one data centre | `modules/vpc` |
| 🚪 **Internet gateway + route table** | The door to the internet and the road map that uses it | `modules/vpc` |
| 🧱🔥 **Security group** | A virtual firewall around a server or load balancer | `modules/tomcat_instances`, `modules/alb` |
| 🖥️ **EC2 / AMI / user data** | A virtual server / its OS image / script run at first boot | `modules/tomcat_instances` |
| 🪪 **IAM role** | The permissions a service or server is allowed to use | many places, always least privilege |
| ⚖️ **ALB** | Load balancer: one URL, traffic spread over the servers, health checks | `modules/alb` |
| 🎁 **WAR** | Packaged Java web app that Tomcat can run | built by Maven |
| 🔄 **CI/CD** | Continuous Integration / Delivery: automatic build, test, deploy on every change | `modules/cicd` |
| 🚀 **CodePipeline** | The orchestrator that runs the stages in order | `modules/cicd/main.tf` |
| 🏭 **CodeBuild + buildspec** | A temporary build machine + the list of commands it runs | `modules/cicd/buildspecs` |
| 📦 **CodeArtifact** | AWS artifact manager: stores versioned packages and proxies Maven Central | `modules/cicd/main.tf` |
| 🚚 **CodeDeploy + appspec** | Copies the WAR onto servers and runs hook scripts | `modules/cicd/deploy` |
| 🛡️ **SAST / SCA** | Scan your code for insecure patterns / scan your libraries for known CVEs | Semgrep / Trivy in `scan.yml` |
| 💨 **Smoke test** | Quick check that the deployed app basically works | `test.yml` |

## 📁 3. Repository layout

```
.
├── bootstrap/                  ONE-TIME: creates the S3 bucket that stores Terraform state
├── versions.tf                 Terraform/provider versions + S3 backend (state location)
├── main.tf                     Root module: connects all modules together
├── variables.tf                Inputs you can change (region, repo, instance type ...)
├── outputs.tf                  URLs and IDs printed after apply
└── modules/
    ├── vpc/                    VPC, 3 public subnets, internet gateway, route table
    ├── tomcat_instances/       3 EC2 servers + firewall + IAM role
    │   └── user_data.sh.tftpl      first-boot script: install Java 21, Tomcat, CodeDeploy agent
    ├── alb/                    Load balancer, target group, listener
    └── cicd/                   The pipeline
        ├── main.tf                 GitHub connection, CodeArtifact, CodeBuild, CodeDeploy, CodePipeline, IAM
        ├── buildspecs/             Commands for each build stage
        │   ├── scan.yml                Semgrep + Trivy
        │   ├── build.yml               Maven build + automatic versioning
        │   ├── publish.yml             Upload WAR to CodeArtifact
        │   └── test.yml                Smoke test through the ALB
        └── deploy/                 CodeDeploy instructions (uploaded to S3, added to each build)
            ├── appspec.yml.tftpl       What to copy and which hooks to run
            └── *.sh.tftpl              before_install / after_install / validate scripts
```

Every file now has comments at the top (what it is and why) and next to the important lines. Read `main.tf` first, then follow each `module` into its folder.

## ✅ 4. Prerequisites

- An AWS account and the **AWS CLI** with a profile that can create VPC, EC2, ELB, IAM, S3, CodePipeline, CodeBuild, CodeDeploy, CodeArtifact and CodeConnections resources. This repo uses the profile name `jenkins-infra` in `main.tf` and `versions.tf`; change it to yours (or remove the `profile` lines and use `export AWS_PROFILE=<name>`).
- **Terraform 1.10 or newer** (needed for S3 native locking).
- A **GitHub** repository with a Maven WAR project (the default is `Suprith25/Java-mini-project`). See [Using your own Java project](#-8-using-your-own-java-project).

## 🪜 5. Step-by-step

### 🪣 Step 1 - Create the state bucket (once)
Terraform needs somewhere to store its state, and that place must exist before the main project runs.
```bash
cd bootstrap
terraform init
terraform apply -var bucket_name=<globally-unique-name>
cd ..
```
This creates a private, encrypted, versioned S3 bucket.

### 🎯 Step 2 - Point the project at the bucket
In `versions.tf` set `bucket = "<your bucket name>"` (and your `profile`). The variable `artifact_bucket_name` in `variables.tf` should be the same bucket: the pipeline stores its files in separate folders of it.

### 🏗️ Step 3 - Build the infrastructure
```bash
terraform init      # downloads the AWS provider, connects to the S3 backend
terraform plan      # shows what WILL be created; read it
terraform apply     # type "yes"; takes about 5 minutes
```
Always run `git pull` and check your branch (`git branch --show-current`) first: Terraform builds whatever the *current files* describe.

### 🔗 Step 4 - Authorize the GitHub connection (manual, once)
Terraform creates the connection in a **PENDING** state; AWS requires a human to approve it.
1. Console (region **ap-south-1**) → **Developer Tools → Settings → Connections**.
2. Open `tomcat-demo-github` → **Update pending connection**.
3. **Install a new app** → choose your GitHub account → select the Java repository → **Connect**.
4. The status must read **Available**.

The installed GitHub App is also what notifies AWS about pushes. If it is only *authorized* but not *installed*, the repo can be cloned but the pipeline will **not** start automatically.

### ▶️ Step 5 - Run the pipeline the first time
CodePipeline → `tomcat-demo-pipeline` → **Release change**. After this, every `git push` to the watched branch starts it automatically. Watch the six stages turn green.

### 🌍 Step 6 - Open the application
```bash
terraform output
```
| Output | What to open |
|---|---|
| `alb_url` | `/hello.html` through the load balancer (refresh: server 1, 2, 3 take turns) |
| `app_url` | Your deployed app, e.g. `.../sample/` |
| `tomcat_urls` | Each server directly on port 8080 |
| `app_url` + `version.txt` | e.g. `.../sample/version.txt` shows the deployed version, such as `1.0.7` |

### ✨ Step 7 - Make a change and watch CI/CD work
Edit the Java project (for example the text in `HelloServlet.java`), commit and push to the watched branch. Within about 30 seconds CodePipeline starts; at the end `version.txt` shows a new version and your change is live.

### 🧹 Step 8 - Clean up (to avoid charges)
```bash
terraform destroy
```
The state bucket is not managed here, so it stays. Delete the `deploy-assets/` and `tomcat-demo-pipeline/` folders in it by hand if you want it empty (never delete the state file while resources exist).

## ⚙️ 6. How the pipeline works

| # | Stage | Tool | What happens | Fails when |
|---|---|---|---|---|
| 1 | 📥 **Source** | CodeStar connection | Clones the repo on every push to the branch | Connection not authorized / app not installed |
| 2 | 🛡️ **CodeScan** | CodeBuild: Semgrep + Trivy | Semgrep checks your Java code for insecure patterns; Trivy checks libraries for known vulnerabilities and leaked secrets | A CRITICAL finding (configurable) |
| 3 | 🔨 **Build** | CodeBuild: Maven | Computes the version, compiles, runs tests, packages the WAR, assembles the deployment bundle | Compile error or failing test |
| 4 | 📦 **Publish** | CodeBuild: CodeArtifact | Stores the exact WAR with its version number | Upload or permission error |
| 5 | 🚚 **Deploy** | CodeDeploy | Copies the WAR to all 3 servers at once; Tomcat unpacks it; a script confirms it answers; automatic rollback on failure | Servers not ready, agent not running |
| 6 | 🧪 **Test** | CodeBuild: curl | Calls the ALB and requires the new version number plus working pages | Wrong version or broken page |

🔢 **Automatic versioning.** The WAR version is `app_major_minor` + CodeBuild's build number, so builds are `1.0.1`, `1.0.2`, `1.0.3` ... Change `app_major_minor` (for example to `1.1`) for a minor or major release. The version is written into the pom (workspace only) and into `version.txt` inside the WAR, and the stored package is `sample-<version>.war`.

🚦 **Deployment strategy.** In-place, all servers at once (`CodeDeployDefault.AllAtOnce`, no ALB draining). It is the fastest option; the app is briefly unavailable (about a minute) while Tomcat reloads. For zero downtime change the deployment group to `OneAtATime` with `WITH_TRAFFIC_CONTROL`; deployments then take a few minutes longer.

## 🔐 7. Security notes

- 🔑 **Least privilege IAM:** each service role may only touch what it needs; the pipeline roles can reach only their own folders of the shared bucket, never the state file.
- 🙈 **Secrets never in git:** state files, `.tfvars` and the Terraform cache are git-ignored. The real state lives encrypted in S3.
- 🔍 **Scans before deploy:** Semgrep and Trivy run before anything is built.
- ⚠️ **Demo shortcuts (not for production):** ports 22 and 8080 are open to the whole internet; servers have public IPs; traffic is plain HTTP; there is no WAF or HTTPS. Production would put servers in private subnets, allow 8080 only from the ALB, use SSM instead of SSH, and add an HTTPS listener with an ACM certificate.

## ☕ 8. Using your own Java project

The pipeline works with any repository that:
- has a Maven `pom.xml` (set `app_dir` to its folder, `.` if it is in the root),
- builds a **WAR** with `<finalName>` equal to `war_name`,
- targets **Java 21** and **Tomcat 10** (`jakarta.*` imports, not `javax.*`).

Then run `terraform apply -var github_repo=<owner>/<repo> -var app_dir=<folder> -var war_name=<finalName>`. No deployment files are needed in the app repo; they live in `modules/cicd/deploy`.

## 💰 9. Free-tier and cost

| Item | Cost |
|---|---|
| 🚀 CodePipeline (one V1 pipeline), CodeStar connection | ✅ free |
| 🏭 CodeBuild (small) | ✅ 100 build-minutes per month free (a run takes roughly 6 to 10 minutes) |
| 🚚 CodeDeploy on EC2 | ✅ free |
| 📦 CodeArtifact | ✅ 2 GB and 100k requests free |
| 🪣 S3 and CloudWatch Logs | ✅ small, inside the free allowance (7-day log retention, 14-day artifact expiry) |
| 🖥️ **EC2 `t3.micro` x3** ⚠️ | free tier gives 750 hours **total**: three servers running all month exceed it |
| ⚖️ **ALB and public IPv4 addresses** 💸 | **not free**; roughly $0.025/hour for the ALB |

🧯 Run `terraform destroy` after each session. Use `-var instance_type=t2.micro` on older accounts where `t3.micro` is not free-tier eligible.

## 🛠️ 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Source stage fails | GitHub connection still **Pending** | Step 4 |
| Pushes do not start the pipeline (manual **Release change** works) | The GitHub App is *authorized* but not *installed* on the repo | Install it from the connection page (Step 4); check github.com/settings/installations |
| ALB returns **502** | No healthy server. Usually Tomcat did not install: the boot script's download from `archive.apache.org` timed out and `set -e` stopped it | Check `aws ec2 get-console-output --instance-id <id> --latest`. Branch `fix-tomcat-download` switches to Maven Central with retries and a checksum, and falls back to the Apache archive |
| ALB 502/503 for the first minutes after apply | Servers are still booting / health checks have not passed | Wait 3 to 5 minutes |
| `/sample/` returns 404 | The pipeline has not deployed yet (new servers start without the WAR) | **Release change** |
| `scan` stage: Trivy install fails | A pinned Trivy version was removed from GitHub releases | Update the version in `buildspecs/scan.yml` |
| Build: `AccessDenied ... s3:ListBucket` | CodeBuild role lacked list permission on the deploy-assets folder | Already granted in `modules/cicd/main.tf` |
| `terraform destroy` fails: CodeArtifact repo "used as an upstream" (409) | AWS releases the link a little late | Re-run destroy, or delete the repo with `aws codeartifact delete-repository` |
| `terraform apply` tries to **destroy** the pipeline | You are on a branch or an old checkout without the `cicd` module | `git pull`, switch to the right branch, read `terraform plan` before `apply` |
| `no such host` during apply | Your internet or DNS dropped | Re-run `apply`; if a state upload failed, look for `errored.tfstate` and run `terraform state push errored.tfstate` |

## 🌿 Branches

| Branch | Adds |
|---|---|
| `main` | The merged result of the pull requests from the branches below (check which PRs were merged) |
| `code-pipeline` (this README) | VPC, Tomcat servers, ALB and the CI/CD pipeline |
| `cloudwatch0-dashboard` | CloudWatch dashboard for the 3 servers and CPU > 90% email alarms |
| `cloudwatch-agent-installation` | CloudWatch agent that ships Tomcat logs to `tomcat1loggroup`, `tomcat2loggroup`, `tomcat3loggroup` |
| `fix-tomcat-download` | More reliable Tomcat download in the boot script |
