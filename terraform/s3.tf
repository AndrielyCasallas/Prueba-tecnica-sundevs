########################################
# Sufijo aleatorio para un nombre de bucket único globalmente
########################################
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "results" {
  bucket        = "${local.name_prefix}-results-${random_id.bucket_suffix.hex}"
  force_destroy = true # permite destruir el stack aunque el bucket tenga objetos (entorno de prueba)

  tags = {
    Name = "${local.name_prefix}-results"
  }
}

########################################
# Block Public Access en las 4 configuraciones
########################################
resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

########################################
# Versionado habilitado
########################################
resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

########################################
# Cifrado en reposo (SSE-S3) - buena práctica
########################################
resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

########################################
# Bucket policy.
#
# El bucket no tiene acceso público gracias a Block Public Access. El acceso
# de datos se concede explícitamente al rol de Lambda y se evita cualquier
# Deny de objetos con NotPrincipal: ese patrón puede bloquear el refresh de
# Terraform o una sesión asumida de IAM aunque exista un Allow.
########################################
data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowLambdaRoleAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.results.arn}/results/*"]
  }

  statement {
    sid       = "AllowLambdaListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "results" {
  bucket = aws_s3_bucket.results.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  # La policy depende del block public access para evitar conflicto al aplicar
  depends_on = [aws_s3_bucket_public_access_block.results]
}
