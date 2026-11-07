# 🧭 main.tf - the ROOT module: wires every module together
#
# Think of this file as the "table of contents" of the infrastructure.
# Each "module" block calls a reusable folder under ./modules and passes inputs to it.
# A module's outputs feed the next module, which is how Terraform knows the order:
#
#    vpc  ->  tomcat (EC2 servers)  ->  alb (load balancer)  ->  cicd (pipeline)
#
# Terraform builds a dependency graph from these references and creates things in
# the right order (and in parallel where it is safe).

# A data source READS existing information instead of creating anything.
# This one returns the AWS account ID we are logged in to (used in IAM policies).
data "aws_caller_identity" "current" {}

# locals = named values computed once and reused (like constants/variables inside the file).
locals {
  artifact_bucket_name = var.artifact_bucket_name
  pipeline_prefix      = "${var.project_name}-pipeline" # folder CodePipeline uses inside the bucket
}

# The AWS provider: which region to build in and which CLI profile (credentials) to use.
provider "aws" {
  region  = var.region
  profile = "jenkins-infra"
}

# 1) NETWORK: VPC, public subnets, internet gateway, route table. See modules/vpc.
module "vpc" {
  source = "./modules/vpc"

  name                = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
}

# 2) SERVERS: 3 EC2 instances that install Apache Tomcat. See modules/tomcat_instances.
# The servers are placed in the subnets created by the vpc module.
module "tomcat" {
  source = "./modules/tomcat_instances"

  name           = var.project_name
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.public_subnet_ids
  instance_count = 3
  instance_type  = var.instance_type
  tomcat_version = var.tomcat_version

  region               = var.region
  artifact_bucket_name = local.artifact_bucket_name
  artifact_prefix      = local.pipeline_prefix
}

# 3) LOAD BALANCER: one public URL that spreads traffic over the 3 servers.
# See modules/alb. instance_ids comes from the tomcat module output.
module "alb" {
  source = "./modules/alb"

  name         = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.public_subnet_ids
  instance_ids = module.tomcat.instance_ids
}

# 4) CI/CD PIPELINE: CodePipeline + CodeBuild + CodeDeploy + CodeArtifact.
# Pulls code from GitHub, scans, builds, versions, publishes and deploys the WAR.
# See modules/cicd.
module "cicd" {
  source = "./modules/cicd"

  name                 = var.project_name
  region               = var.region
  account_id           = data.aws_caller_identity.current.account_id
  artifact_bucket_name = local.artifact_bucket_name

  github_repo   = var.github_repo
  github_branch = var.github_branch
  major_minor   = var.app_major_minor
  app_dir       = var.app_dir
  war_name      = var.war_name

  codedeploy_tag_value = var.project_name # matches the CodeDeployGroup tag on the instances
  app_url              = "http://${module.alb.alb_dns_name}"
}

module "monitoring" {
  source = "./modules/monitoring"

  name                    = var.project_name
  region                  = var.region
  instance_ids            = module.tomcat.instance_ids
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alert_email             = var.alert_email
  cpu_threshold           = var.cpu_alarm_threshold
}

module "cloudwatch_agent" {
  source = "./modules/cloudwatch_agent"

  name               = var.project_name
  instance_ids       = module.tomcat.instance_ids
  instance_role_name = module.tomcat.instance_role_name
}
