########################################
# Empaquetado de la Lambda
#
# El runtime de Lambda ya incluye boto3, pero NO redis-py. Instalamos la
# dependencia en un directorio de build y empaquetamos todo en un zip, de modo
# que `terraform apply` sea autosuficiente (un solo comando).
########################################
locals {
  lambda_src_dir   = "${path.module}/../lambda"
  lambda_build_dir = "${path.module}/.build/lambda"
}

# Instala dependencias y copia el código fuente al directorio de build.
# Se re-ejecuta si cambian handler.py o requirements.txt.
resource "null_resource" "lambda_build" {
  triggers = {
    handler_sha = filesha256("${local.lambda_src_dir}/handler.py")
    reqs_sha    = filesha256("${local.lambda_src_dir}/requirements.txt")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      rm -rf "${local.lambda_build_dir}"
      mkdir -p "${local.lambda_build_dir}"
      cp "${local.lambda_src_dir}/handler.py" "${local.lambda_build_dir}/"
      python3 -m pip install \
        --platform manylinux2014_x86_64 \
        --target "${local.lambda_build_dir}" \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        -r "${local.lambda_src_dir}/requirements.txt"
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = "${path.module}/.build/lambda.zip"

  depends_on = [null_resource.lambda_build]
}

########################################
# Log group de la Lambda (retención controlada)
########################################
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-processor"
  retention_in_days = var.log_retention_days
}

########################################
# Rol IAM de la Lambda
########################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permisos mínimos: logs, ENIs para VPC, y acceso al bucket de resultados.
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid    = "VpcEni"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"] # requerido por el servicio Lambda para gestionar ENIs
  }

  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

########################################
# Función Lambda (dentro de la VPC, subnets privadas)
########################################
resource "aws_lambda_function" "processor" {
  function_name = "${local.name_prefix}-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  architectures = ["x86_64"]
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST        = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT        = tostring(var.redis_port)
      S3_BUCKET         = aws_s3_bucket.results.bucket
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
    aws_elasticache_cluster.redis,
  ]
}
