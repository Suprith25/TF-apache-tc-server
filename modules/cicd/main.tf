# 🚀 modules/cicd/main.tf - the whole CI/CD pipeline on AWS
#
#    GitHub --push--> CodePipeline
#         Source -> CodeScan -> Build -> Publish -> Deploy -> Test
#
#   Source    CodeStar connection clones the repo
#   CodeScan  CodeBuild: Semgrep (code) + Trivy (dependencies, secrets)
#   Build     CodeBuild: Maven compile/test/package, sets version 1.0.<build>
#   Publish   CodeBuild: stores the versioned WAR in CodeArtifact
#   Deploy    CodeDeploy: copies the WAR to all Tomcat servers
#   Test      CodeBuild: smoke test through the ALB, checks the new version
#
# Sections below: connection, S3 artifacts, CodeArtifact, IAM, CodeBuild, CodeDeploy,
# pipeline. Every AWS service needs an IAM ROLE, because services cannot do anything
# until you explicitly allow it.

# Names for the CodeArtifact domain and repository, reused below.
locals {
  ca_domain = "${var.name}-domain"
  ca_repo   = "${var.name}-releases"
}

# ---------------- Source connection (authorize once in the console) ----------------
# Link between AWS and GitHub (it uses the "AWS Connector for GitHub" app).
# Terraform can only create it as PENDING. Open it in the console and click
# "Update pending connection" once, installing the app on your repository.
# The same app also sends push events, which is what auto-triggers the pipeline.
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

# ---------------- Pipeline artifacts: reuse the existing (state) bucket, own folders only ----------------
# Look up the existing bucket (do not create a new one). Pipeline files are kept in their own folders.
data "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket_name
}

locals {
  pipeline_name = "${var.name}-pipeline"
  # CodePipeline writes under "<pipeline name>/"; deploy files live under "deploy-assets/".
  # The Terraform state lives under other keys and is NOT reachable by these roles.
  pipeline_objects = "${data.aws_s3_bucket.artifacts.arn}/${local.pipeline_name}/*"
  asset_objects    = "${data.aws_s3_bucket.artifacts.arn}/deploy-assets/*"
}

# keep the shared bucket small: expire old pipeline artifacts
# Housekeeping: delete pipeline artifacts after 14 days so the bucket stays small and free.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = data.aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-pipeline-artifacts"
    status = "Enabled"
    filter {
      prefix = "${local.pipeline_name}/"
    }
    expiration {
      days = 14
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# ---------------- CodeArtifact (artifact manager for versioned WARs) ----------------
# CodeArtifact = AWS's artifact manager (like Nexus/Artifactory). A domain groups repositories.
resource "aws_codeartifact_domain" "this" {
  domain = local.ca_domain
}

# Proxy repository connected to the public Maven Central. Maven downloads dependencies through it.
resource "aws_codeartifact_repository" "maven_central" {
  repository = "${var.name}-maven-central"
  domain     = aws_codeartifact_domain.this.domain

  external_connections {
    external_connection_name = "public:maven-central"
  }
}

# Our own repository: stores the versioned WARs. Its "upstream" is the proxy above,
# so one URL serves both our packages and public dependencies.
resource "aws_codeartifact_repository" "releases" {
  repository = local.ca_repo
  domain     = aws_codeartifact_domain.this.domain

  upstream {
    repository_name = aws_codeartifact_repository.maven_central.repository
  }
}

# CodeBuild role. Each statement = one narrow permission:
#  - write its own logs   - read/write pipeline folder in S3   - read the deploy files
#  - get a CodeArtifact token, read dependencies, publish packages
# ---------------- IAM: CodeBuild ----------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.name}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.name}-*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = [local.pipeline_objects]
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [local.asset_objects]
  }
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [data.aws_s3_bucket.artifacts.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["deploy-assets/*", "deploy-assets"]
    }
  }
  statement {
    actions   = ["codeartifact:GetAuthorizationToken"]
    resources = [aws_codeartifact_domain.this.arn]
  }
  statement {
    actions = [
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:ReadFromRepository",
      "codeartifact:PublishPackageVersion",
      "codeartifact:PutPackageMetadata",
    ]
    resources = [
      aws_codeartifact_repository.releases.arn,
      aws_codeartifact_repository.maven_central.arn,
      "arn:aws:codeartifact:${var.region}:${var.account_id}:package/${local.ca_domain}/*",
    ]
  }
  statement {
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["codeartifact.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codebuild" {
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# One CodeBuild project per job. for_each creates the 4 projects (scan, build, publish, test)
# from the map below; each one loads its commands from a file in ./buildspecs.
# Environment variables are how Terraform passes settings into the build scripts.
# ---------------- CodeBuild projects: scan / build / test ----------------
locals {
  projects = {
    scan    = "buildspecs/scan.yml"
    build   = "buildspecs/build.yml"
    publish = "buildspecs/publish.yml"
    test    = "buildspecs/test.yml"
  }
}

resource "aws_codebuild_project" "this" {
  for_each     = local.projects
  name         = "${var.name}-${each.key}"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL" # free tier: 100 build-min/month
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "ACCOUNT_ID"
      value = var.account_id
    }
    environment_variable {
      name  = "CA_DOMAIN"
      value = local.ca_domain
    }
    environment_variable {
      name  = "CA_REPO"
      value = local.ca_repo
    }
    environment_variable {
      name  = "MAJOR_MINOR"
      value = var.major_minor
    }
    environment_variable {
      name  = "TRIVY_SEVERITY"
      value = var.trivy_severity
    }
    environment_variable {
      name  = "TRIVY_EXIT_CODE"
      value = var.trivy_exit_code
    }
    environment_variable {
      name  = "APP_DIR"
      value = var.app_dir
    }
    environment_variable {
      name  = "WAR_NAME"
      value = var.war_name
    }
    environment_variable {
      name  = "ASSET_BUCKET"
      value = data.aws_s3_bucket.artifacts.bucket
    }
    environment_variable {
      name  = "APP_URL"
      value = var.app_url
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/${each.value}")
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }
}

# short retention keeps CloudWatch Logs inside the free 5 GB
# Build logs. Short retention keeps CloudWatch inside the free tier.
resource "aws_cloudwatch_log_group" "codebuild" {
  for_each          = local.projects
  name              = "/aws/codebuild/${var.name}-${each.key}"
  retention_in_days = 7
}

# The deployment instructions (appspec.yml and hook scripts) are uploaded to S3 by Terraform
# and copied into every build, so your Java repo does not need any deployment files.
# CodeDeploy appspec + hook scripts live here so the app repo needs no deploy files
locals {
  deploy_assets = {
    "appspec.yml"               = "appspec.yml.tftpl"
    "scripts/before_install.sh" = "before_install.sh.tftpl"
    "scripts/after_install.sh"  = "after_install.sh.tftpl"
    "scripts/validate.sh"       = "validate.sh.tftpl"
  }
}

resource "aws_s3_object" "deploy_assets" {
  for_each = local.deploy_assets
  bucket   = data.aws_s3_bucket.artifacts.id
  key      = "deploy-assets/${each.key}"
  content  = templatefile("${path.module}/deploy/${each.value}", { war_name = var.war_name })
}

# CodeDeploy copies the WAR onto the servers and runs the hook scripts.
# It needs a service role so it can look up the target instances.
# ---------------- CodeDeploy ----------------
data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${var.name}-codedeploy"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# Application = a named container for deployments ("Server" = EC2/on-premises).
resource "aws_codedeploy_app" "this" {
  name             = "${var.name}-app"
  compute_platform = "Server"
}

# Deployment group = WHICH servers and HOW.
#  - ec2_tag_set: target every instance tagged CodeDeployGroup=<project name>
#  - AllAtOnce: update all servers in parallel (fast, brief downtime is accepted)
#  - IN_PLACE / WITHOUT_TRAFFIC_CONTROL: replace the app on the same servers, no ALB draining
#  - auto rollback: redeploy the previous version if a deployment fails
resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.name}-tomcat"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.AllAtOnce" # all 3 servers in parallel

  ec2_tag_set {
    ec2_tag_filter {
      key   = "CodeDeployGroup"
      type  = "KEY_AND_VALUE"
      value = var.codedeploy_tag_value
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL" # no ALB drain/register waits
    deployment_type   = "IN_PLACE"
  }


  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

# CodePipeline role: may use the GitHub connection, store artifacts, start builds and create deployments.
# ---------------- IAM: CodePipeline ----------------
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${var.name}-pipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = [local.pipeline_objects]
  }
  statement {
    actions   = ["s3:GetBucketVersioning", "s3:GetBucketLocation"]
    resources = [data.aws_s3_bucket.artifacts.arn]
  }
  statement {
    actions = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [
      aws_codestarconnections_connection.github.arn,
      replace(aws_codestarconnections_connection.github.arn, "codestar-connections", "codeconnections"),
    ]
  }
  statement {
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [for p in aws_codebuild_project.this : p.arn]
  }
  statement {
    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetDeployment",
      "codedeploy:GetDeploymentConfig",
      "codedeploy:GetApplication",
      "codedeploy:GetApplicationRevision",
      "codedeploy:RegisterApplicationRevision",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

# The pipeline itself. A stage runs only after the previous one succeeds; any failure stops the run.
# Artifacts (files) are passed between stages by name: source_output, build_output.
# pipeline_type V1 is used because the first V1 pipeline is free.
# ---------------- The pipeline: Source -> Scan -> Build -> Deploy -> Test ----------------
resource "aws_codepipeline" "this" {
  name          = local.pipeline_name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V1" # V1: first active pipeline is free

  artifact_store {
    type     = "S3"
    location = data.aws_s3_bucket.artifacts.bucket
  }

  stage {
    # Stage 1 - SOURCE: clone the GitHub repo. DetectChanges = true means every push to the branch starts the pipeline.
    name = "Source"
    action {
      name             = "Clone"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
        DetectChanges    = "true" # every push to the branch triggers the pipeline
      }
    }
  }

  stage {
    # Stage 2 - CODE SCAN: security checks before anything is built. Fails on CRITICAL findings.
    name = "CodeScan"
    action {
      name            = "SAST-and-dependency-scan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.this["scan"].name
      }
    }
  }

  stage {
    # Stage 3 - BUILD: compile, test, package the WAR and give it a version.
    # namespace exposes the build's VERSION variable to later stages as BuildVariables.VERSION.
    name = "Build"
    action {
      name             = "Maven-build-version-publish"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "BuildVariables"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.this["build"].name
      }
    }
  }

  stage {
    # Stage 4 - PUBLISH: store the exact WAR in CodeArtifact so every version is kept and can be re-deployed.
    name = "Publish"
    action {
      name            = "Upload-WAR-to-CodeArtifact"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.this["publish"].name
      }
    }
  }

  stage {
    # Stage 5 - DEPLOY: CodeDeploy installs the WAR on all Tomcat servers.
    name = "Deploy"
    action {
      name            = "Deploy-to-Tomcat"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ApplicationName     = aws_codedeploy_app.this.name
        DeploymentGroupName = aws_codedeploy_deployment_group.this.deployment_group_name
      }
    }
  }

  stage {
    # Stage 6 - TEST: call the live ALB URL and confirm the new version is being served.
    # EXPECTED_VERSION receives the version produced in the Build stage.
    name = "Test"
    action {
      name            = "Smoke-test-via-ALB"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.this["test"].name
        EnvironmentVariables = jsonencode([
          { name = "EXPECTED_VERSION", value = "#{BuildVariables.VERSION}", type = "PLAINTEXT" }
        ])
      }
    }
  }
}
