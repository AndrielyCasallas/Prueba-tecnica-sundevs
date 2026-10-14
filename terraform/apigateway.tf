########################################
# HTTP API (API Gateway v2)
# Elegimos HTTP API sobre REST API por: menor costo (~70% más barato),
# menor latencia, CORS nativo e integración proxy con Lambda directa.
########################################
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "Endpoint HTTP público del servicio de procesamiento."

  # CORS habilitado para cualquier origen
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }
}

########################################
# Integración proxy con la Lambda (payload v2)
########################################
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.processor.invoke_arn
  payload_format_version = "2.0"
}

########################################
# Ruta POST /process
########################################
resource "aws_apigatewayv2_route" "process" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

########################################
# Log group de acceso de API Gateway
########################################
resource "aws_cloudwatch_log_group" "apigw_access" {
  name              = "/aws/apigateway/${local.name_prefix}-access"
  retention_in_days = var.log_retention_days
}

########################################
# Stage con auto-deploy, throttling y access logging
########################################
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  # Throttling a nivel de stage (rate limit + burst)
  default_route_settings {
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }

  # Logs de acceso en CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

########################################
# Permiso para que API Gateway invoque la Lambda
########################################
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
