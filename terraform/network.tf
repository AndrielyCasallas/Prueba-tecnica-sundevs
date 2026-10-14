########################################
# VPC
########################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

########################################
# Internet Gateway (salida de las subnets públicas)
########################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

########################################
# Subnets públicas (2, una por AZ)
########################################
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

########################################
# Subnets privadas (2, mismas AZs) -> Lambda y Redis
########################################
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

########################################
# NAT Gateway (en una subnet pública) para la salida de Lambda
########################################
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

########################################
# Tabla de rutas pública -> IGW
########################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

########################################
# Tabla de rutas privada -> NAT (salida a internet sin exposición entrante)
########################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

########################################
# VPC Endpoint tipo Gateway para S3
# El tráfico Lambda -> S3 NO sale a internet: viaja por la red de AWS.
########################################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Asociado a la tabla de rutas privada: las subnets privadas resuelven
  # S3 por el endpoint en vez de por el NAT.
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

########################################
# Security Groups segmentados
########################################

# SG de Lambda: sin ingress (nadie inicia conexiones hacia Lambda),
# egress abierto para hablar con Redis, S3 (vía endpoint) y CloudWatch.
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "SG de la Lambda. Egress a Redis, S3 y CloudWatch."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Salida a cualquier destino (Redis, S3 endpoint, CloudWatch)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}

# SG de Redis: solo acepta tráfico en 6379 desde el SG de Lambda.
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "SG de Redis. Solo acepta 6379 desde el SG de Lambda."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-redis-sg"
  }
}

# Regla de ingress definida aparte para referenciar el SG de Lambda sin ciclos.
resource "aws_vpc_security_group_ingress_rule" "redis_from_lambda" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis solo acepta conexiones del SG de Lambda en 6379."
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "redis_egress" {
  security_group_id = aws_security_group.redis.id
  description       = "Egress permitido (respuestas)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
