data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Usamos exactamente 2 AZs para las 2 subnets públicas y 2 privadas.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
