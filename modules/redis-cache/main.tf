# A managed Redis instance, sized from a t-shirt parameter.

locals {
  slug = replace(var.name, "/", "-")

  # One per placement. The same resource stands in every slot it is placed in, and a replication group's id is
  # unique per account and region — two slots of one environment share both, and so did every environment on Floci.
  # Cut to the 40 characters ElastiCache allows, with a hash of the whole so two long names still differ.
  placement = lower(join("-", [replace(var.environment, "/", "-"), var.stamp, local.slug]))
  group_id  = length(local.placement) <= 40 ? local.placement : "${trimsuffix(substr(local.placement, 0, 31), "-")}-${substr(md5(local.placement), 0, 8)}"

  sizing = {
    small  = { node_type = "cache.t4g.micro", replicas = 0, failover = false }
    medium = { node_type = "cache.t4g.medium", replicas = 1, failover = true }
    large  = { node_type = "cache.r7g.large", replicas = 2, failover = true }
  }
  size = local.sizing[var.size_class]

  secret_ref = "${var.environment}/${var.stamp}/${var.name}"

  tags = merge(var.tags, {
    "lembos.dev/resource"    = var.name
    "lembos.dev/environment" = var.environment
    "lembos.dev/stamp"       = var.stamp
  })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.group_id
  description          = "Lembos ${var.name} (${var.environment}, ${var.stamp})"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = local.size.node_type
  port           = 6379

  num_cache_clusters         = local.size.replicas + 1
  automatic_failover_enabled = local.size.failover
  multi_az_enabled           = local.size.failover

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true

  tags = local.tags
}

# Where clients connect. AWS gives a replication group with cluster mode off a primary endpoint and no configuration
# endpoint; an emulator such as Floci answers with the configuration endpoint alone. Either is the address writes go
# to, so the first one present is used — and none at all fails the apply rather than writing "rediss://:6379".
locals {
  endpoint = coalesce(
    aws_elasticache_replication_group.this.primary_endpoint_address,
    aws_elasticache_replication_group.this.configuration_endpoint_address,
  )
}

resource "aws_secretsmanager_secret" "connection" {
  name = local.secret_ref
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id = aws_secretsmanager_secret.connection.id
  secret_string = jsonencode({
    url = "rediss://${local.endpoint}:${aws_elasticache_replication_group.this.port}"
  })
}
