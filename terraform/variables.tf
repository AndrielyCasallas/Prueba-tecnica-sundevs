variable "aws_region" {
  description = "Región de AWS donde se despliega el stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar y etiquetar todos los recursos."
  type        = string
  default     = "sre-data-processor"
}

variable "environment" {
  description = "Entorno lógico (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las 2 subnets públicas (una por AZ)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las 2 subnets privadas (una por AZ). Aquí viven Lambda y Redis."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "redis_node_type" {
  description = "Tipo de nodo de ElastiCache. cache.t3.micro es el más económico ampliamente disponible."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  description = "Puerto de Redis."
  type        = number
  default     = 6379
}

variable "cache_ttl_seconds" {
  description = "TTL en segundos para las keys que escribe la Lambda en Redis."
  type        = number
  default     = 60
}

variable "lambda_timeout" {
  description = "Timeout de la Lambda en segundos."
  type        = number
  default     = 15
}

variable "lambda_memory" {
  description = "Memoria de la Lambda en MB."
  type        = number
  default     = 256
}

variable "api_throttle_rate_limit" {
  description = "Rate limit (req/s en estado estable) del stage de API Gateway."
  type        = number
  default     = 50
}

variable "api_throttle_burst_limit" {
  description = "Burst limit (ráfaga de peticiones) del stage de API Gateway."
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "Retención de los log groups de CloudWatch."
  type        = number
  default     = 14
}
