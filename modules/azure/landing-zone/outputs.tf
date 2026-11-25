# The contract every module here answers to, then what the slots and the resource modules read as environment.outputs.*.

output "resource_id" {
  value = azurerm_kubernetes_cluster.this.name
}

# The API server and its CA are public, but they arrive inside the cluster's kubeconfig, which is sensitive as a whole;
# so they are let out of it explicitly, and the credentials beside them are not.
output "endpoint" {
  description = "The cluster's API server."
  value       = nonsensitive(azurerm_kubernetes_cluster.this.kube_config[0].host)
}

output "port" {
  description = "Carried in the endpoint."
  value       = null
}

output "secret_ref" {
  description = "The vault secret holding the cluster's kubeconfig. Never the kubeconfig."
  value       = "${azurerm_key_vault.this.name}/${azurerm_key_vault_secret.kubeconfig.name}"
}

output "region" {
  description = "The region everything here is in, named as the AWS landing zone names its own."
  value       = azurerm_resource_group.this.location
}

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  value = nonsensitive(azurerm_kubernetes_cluster.this.kube_config[0].host)
}

output "cluster_ca" {
  description = "The API server's CA, base64-encoded. Public, so it travels as a value."
  value       = nonsensitive(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

output "oidc_issuer" {
  description = "Where the slots' identities trust their service accounts' tokens from. Empty without workload identity."
  value       = var.workload_identity_enabled ? azurerm_kubernetes_cluster.this.oidc_issuer_url : ""
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "kubeconfig_secret_ref" {
  description = "The vault secret holding the kubeconfig, for a target that cannot exchange a token."
  value       = "${azurerm_key_vault.this.name}/${azurerm_key_vault_secret.kubeconfig.name}"
}

output "outbound_ip" {
  description = "The one address the cluster reaches out from."
  value       = azurerm_public_ip.outbound.ip_address
}

output "ingress_class" {
  description = "The class of the ingress controller AKS runs (web app routing)."
  value       = "webapprouting.kubernetes.azure.com"
}

output "ingress_domain" {
  value = var.ingress_domain
}
