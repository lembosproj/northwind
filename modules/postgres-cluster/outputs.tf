output "resource_id" {
  description = "The provider identifier, recorded as a provisioning output."
  value       = aws_db_instance.this.identifier
}

output "endpoint" {
  description = "Where the workload connects."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "secret_ref" {
  description = "The path holding the connection string. Never the connection string itself."
  value       = aws_secretsmanager_secret.connection.name
}

output "read_endpoint" {
  description = "The read replica, when the size class provisions one."
  value       = length(aws_db_instance.replica) > 0 ? aws_db_instance.replica[0].address : null
}
