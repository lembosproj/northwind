# What a deployment into this stamp reads, as environment.outputs.*. The first four are the contract every
# module here answers to, so anything reading a provisioning's outputs reads them the same way.

output "resource_id" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "endpoint" {
  description = "The API server this namespace lives on, carried through from the foundation so a deployment reads one place."
  value       = var.cluster_endpoint
}

output "port" {
  description = "Carried in the endpoint, so null rather than a second copy that could disagree with it."
  value       = null
}

output "secret_ref" {
  description = "Where the namespace's service-account coordinates are kept. Never a token."
  value       = aws_secretsmanager_secret.service_account.name
}

output "namespace" {
  description = "What a deployment into this stamp is applied to."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_account" {
  description = "The identity workloads here run as. An IRSA role trusts it by this name and the namespace above."
  value       = kubernetes_service_account_v1.this.metadata[0].name
}
