output "resource_id" {
  description = "The provider identifier, recorded as a provisioning output."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "endpoint" {
  description = "Where the workload connects."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  value = 5432
}

output "secret_ref" {
  description = "The path holding the connection string, as on AWS. Never the connection string itself."
  value       = local.secret_ref
}
