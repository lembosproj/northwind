output "resource_id" {
  description = "The provider identifier, recorded as a provisioning output."
  value       = azurerm_redis_cache.this.name
}

output "endpoint" {
  description = "Where the workload connects."
  value       = azurerm_redis_cache.this.hostname
}

output "port" {
  value = azurerm_redis_cache.this.ssl_port
}

output "secret_ref" {
  description = "The path holding the connection string, as on AWS. Never the connection string itself."
  value       = local.secret_ref
}
