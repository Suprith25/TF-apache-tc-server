data "aws_caller_identity" "current" {}

locals {
  artifact_bucket_name = var.artifact_bucket_name
  pipeline_prefix      = "${var.project_name}-pipeline" # folder CodePipeline uses inside the bucket
}

provider "aws" {
  region  = var.region
  profile = "jenkins-infra"
}

module "vpc" {
  source = "./modules/vpc"

  name                = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
}

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

module "alb" {
  source = "./modules/alb"

  name         = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.public_subnet_ids
  instance_ids = module.tomcat.instance_ids
}

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
