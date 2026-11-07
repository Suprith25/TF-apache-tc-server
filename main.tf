provider "aws" {
  region = var.region
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
}

module "alb" {
  source = "./modules/alb"

  name         = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.public_subnet_ids
  instance_ids = module.tomcat.instance_ids
}
