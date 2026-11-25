output "resource_id" {
  value = aws_elasticache_replication_group.this.replication_group_id
}

output "endpoint" {
  description = "The primary. Writes go here."
  value       = local.endpoint
}

output "port" {
  value = aws_elasticache_replication_group.this.port
}

output "secret_ref" {
  value = aws_secretsmanager_secret.connection.name
}

output "reader_endpoint" {
  description = "The reader endpoint, which only exists once the size class adds a replica."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}
