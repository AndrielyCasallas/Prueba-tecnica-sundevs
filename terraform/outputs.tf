output "api_endpoint" {
  description = "URL base del HTTP API. La ruta del servicio es POST {api_endpoint}/process."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "process_url" {
  description = "URL completa lista para probar con curl."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/process"
}

output "s3_bucket_name" {
  description = "Bucket de resultados."
  value       = aws_s3_bucket.results.bucket
}

output "redis_endpoint" {
  description = "Endpoint del nodo Redis (solo accesible desde la VPC)."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda."
  value       = aws_lambda_function.processor.function_name
}

output "lambda_log_group" {
  description = "Log group de la Lambda en CloudWatch."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "vpc_id" {
  description = "ID de la VPC creada."
  value       = aws_vpc.main.id
}
