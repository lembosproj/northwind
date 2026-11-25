# A managed Postgres server and its database: the Azure twin of ../../aws/postgres, kept to the minimum. Reached over
# the public endpoint through a firewall that admits the environment's cluster alone, so it needs no private network.

locals {
  # What a size class means for Postgres on Azure. The platform team owns this table.
  sizing = {
    small  = { sku = "B_Standard_B1ms", storage_mb = 32768 }
    medium = { sku = "GP_Standard_D2ds_v5", storage_mb = 131072 }
    large  = { sku = "GP_Standard_D4ds_v5", storage_mb = 524288 }
  }
  size = local.sizing[var.size_class]

  database = replace(replace(var.name, "/", "_"), "-", "_")

  # Retention is a stage decision, as on AWS.
  backup_retention = can(regex("prod", var.environment)) ? 30 : 7
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = local.identifier
  location                      = data.azurerm_resource_group.environment.location
  resource_group_name           = data.azurerm_resource_group.environment.name
  version                       = "16"
  sku_name                      = local.size.sku
  storage_mb                    = local.size.storage_mb
  administrator_login           = "lembos"
  administrator_password        = random_password.admin.result
  backup_retention_days         = local.backup_retention
  public_network_access_enabled = true
  tags                          = local.tags

  # Azure picks a zone and may move the server between them; asking for one back would replace it.
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "cluster" {
  name             = "cluster"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = data.azurerm_public_ip.outbound.ip_address
  end_ip_address   = data.azurerm_public_ip.outbound.ip_address
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = local.database
  server_id = azurerm_postgresql_flexible_server.this.id
}

# The connection string lands in the environment's vault and only its path leaves this module.
resource "azurerm_key_vault_secret" "connection" {
  name         = local.secret_name
  key_vault_id = data.azurerm_key_vault.environment.id
  value = format("postgresql://%s:%s@%s:5432/%s?sslmode=require",
    azurerm_postgresql_flexible_server.this.administrator_login,
    random_password.admin.result,
    azurerm_postgresql_flexible_server.this.fqdn,
  azurerm_postgresql_flexible_server_database.this.name)
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
