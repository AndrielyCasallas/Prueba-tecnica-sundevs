########################################
# Subnet Group de ElastiCache apuntando a las subnets privadas
########################################
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-redis-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-redis-subnets"
  }
}

########################################
# ElastiCache Redis (nodo único, sin acceso público)
########################################
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = var.redis_port

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  # Mantenimiento y snapshots mínimos (entorno de prueba, nodo económico)
  snapshot_retention_limit = 0

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}
