locals {
  ca_domain = "${var.name}-domain"
  ca_repo   = "${var.name}-releases"
}

# ---------------- Source connection (authorize once in the console) ----------------
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

# ---------------- Pipeline artifacts: reuse the existing (state) bucket, own folders only ----------------
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
resource "aws_codeartifact_domain" "this" {
  domain = local.ca_domain
}

resource "aws_codeartifact_repository" "maven_central" {
  repository = "${var.name}-maven-central"
  domain     = aws_codeartifact_domain.this.domain

  external_connections {
    external_connection_name = "public:maven-central"
  }
}

resource "aws_codeartifact_repository" "releases" {
  repository = local.ca_repo
  domain     = aws_codeartifact_domain.this.domain

  upstream {
    repository_name = aws_codeartifact_repository.maven_central.repository
  }
}

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

# ---------------- CodeBuild projects: scan / build / test ----------------
locals {
  projects = {
    scan  = "buildspecs/scan.yml"
    build = "buildspecs/build.yml"
    test  = "buildspecs/test.yml"
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
resource "aws_cloudwatch_log_group" "codebuild" {
  for_each          = local.projects
  name              = "/aws/codebuild/${var.name}-${each.key}"
  retention_in_days = 7
}

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

resource "aws_codedeploy_app" "this" {
  name             = "${var.name}-app"
  compute_platform = "Server"
}

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
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
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
