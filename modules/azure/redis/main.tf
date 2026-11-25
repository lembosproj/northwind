# A managed Redis cache: the Azure twin of ../../aws/redis, kept to the minimum. Azure Cache for Redis, the offer the
# local emulator runs; reached over TLS through a firewall that admits the environment's cluster alone.

locals {
  # What a size class means for Redis on Azure. The platform team owns this table.
  sizing = {
    small  = { sku = "Basic", family = "C", capacity = 0 }
    medium = { sku = "Standard", family = "C", capacity = 1 }
    large  = { sku = "Premium", family = "P", capacity = 1 }
  }
  size = local.sizing[var.size_class]
}

resource "azurerm_redis_cache" "this" {
  name                 = local.identifier
  location             = data.azurerm_resource_group.environment.location
  resource_group_name  = data.azurerm_resource_group.environment.name
  sku_name             = local.size.sku
  family               = local.size.family
  capacity             = local.size.capacity
  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"
  tags                 = local.tags
}

resource "azurerm_redis_firewall_rule" "cluster" {
  name                = "cluster"
  redis_cache_name    = azurerm_redis_cache.this.name
  resource_group_name = data.azurerm_resource_group.environment.name
  start_ip            = data.azurerm_public_ip.outbound.ip_address
  end_ip              = data.azurerm_public_ip.outbound.ip_address
}

resource "azurerm_key_vault_secret" "connection" {
  name         = local.secret_name
  key_vault_id = data.azurerm_key_vault.environment.id
  value = format("rediss://:%s@%s:%d",
    azurerm_redis_cache.this.primary_access_key,
    azurerm_redis_cache.this.hostname,
  azurerm_redis_cache.this.ssl_port)
  tags = local.tags
}

# The slot's workloads read this secret and no other in the vault.
resource "azurerm_role_assignment" "slot_reads" {
  count                = length(data.azurerm_user_assigned_identity.slot)
  scope                = azurerm_key_vault_secret.connection.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_user_assigned_identity.slot[0].principal_id
  principal_type       = "ServicePrincipal"
}
