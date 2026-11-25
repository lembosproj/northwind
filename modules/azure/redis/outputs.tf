output "resource_id" {
  description = "The provider identifier, recorded as a provisioning output."
  value       = azurerm_managed_redis.this.name
}

output "endpoint" {
  description = "Where the workload connects."
  value       = azurerm_managed_redis.this.hostname
}

output "port" {
  value = local.port
}

output "secret_ref" {
  description = "The path holding the connection string, as on AWS. Never the connection string itself."
  value       = local.secret_ref
}
