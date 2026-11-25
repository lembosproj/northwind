# A managed Redis cache: the Azure twin of ../../aws/redis, kept to the minimum. Azure Managed Redis, because Azure
# no longer creates the older Azure Cache for Redis. Reached over TLS with its access key: Managed Redis has no IP
# firewall rule, and a private endpoint would need a subnet the landing zone does not make.

locals {
  # What a size class means for Redis on Azure. The platform team owns this table.
  sizing = {
    small  = { sku = "Balanced_B0", high_availability = false }
    medium = { sku = "Balanced_B1", high_availability = true }
    large  = { sku = "Balanced_B3", high_availability = true }
  }
  size = local.sizing[var.size_class]

  # Managed Redis listens on one port, over TLS.
  port = 10000

  # Azure caps a Managed Redis name and its region's display name at 62 characters together, and a region's name runs
  # to some 30, so the placement's name is cut shorter here than elsewhere, keeping a hash so it stays unique.
  redis_name = length(local.placement) <= 30 ? local.placement : "${trimsuffix(substr(local.placement, 0, 21), "-")}-${substr(md5(local.placement), 0, 8)}"
}

resource "azurerm_managed_redis" "this" {
  name                      = local.redis_name
  location                  = data.azurerm_resource_group.environment.location
  resource_group_name       = data.azurerm_resource_group.environment.name
  sku_name                  = local.size.sku
  high_availability_enabled = local.size.high_availability
  public_network_access     = "Enabled"
  tags                      = local.tags

  default_database {
    # One endpoint for the whole database, so a client that speaks no cluster protocol connects as to one server.
    clustering_policy                  = "EnterpriseCluster"
    eviction_policy                    = "VolatileLRU"
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}

resource "azurerm_key_vault_secret" "connection" {
  name         = local.secret_name
  key_vault_id = data.azurerm_key_vault.environment.id
  value = format("rediss://:%s@%s:%d",
    azurerm_managed_redis.this.default_database[0].primary_access_key,
    azurerm_managed_redis.this.hostname,
  local.port)
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
