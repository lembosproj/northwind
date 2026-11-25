# What a deployment into this slot reads, as environment.outputs.*. The first four are the contract every module here
# answers to.

output "resource_id" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "endpoint" {
  description = "The API server this namespace lives on. Public, though read from the sensitive kubeconfig."
  value       = nonsensitive(local.access.host)
}

output "port" {
  description = "Carried in the endpoint."
  value       = null
}

output "secret_ref" {
  description = "Nothing: a slot keeps no secret. Its identity signs in through the cluster's issuer."
  value       = null
}

output "namespace" {
  description = "What a deployment into this slot is applied to."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_account" {
  description = "What every component placed here runs as: the charts' identity.serviceAccount."
  value       = kubernetes_service_account_v1.this.metadata[0].name
}

output "client_id" {
  description = "The slot identity's client id, the charts' identity.azure.clientId. Empty without workload identity."
  value       = local.workload_identity ? azurerm_user_assigned_identity.workload[0].client_id : ""
}

output "tenant_id" {
  description = "The charts' identity.azure.tenantId."
  value       = local.workload_identity ? azurerm_user_assigned_identity.workload[0].tenant_id : ""
}
