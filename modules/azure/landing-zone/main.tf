# The substrate an Azure environment sits on: a resource group, a network, a cluster, a vault for the secrets its
# resources make, and a fixed address the cluster reaches out from. The Azure twin of ../../aws/landing-zone, kept to
# the minimum a slot and the sample's resources need.
#
# Built once per environment and shared by every slot in it: each slot is a namespace on this cluster, built by
# ../namespace. Nothing here is named after a slot.
#
# The resource modules beside this one find what they need here by name, not by input, so they keep the five inputs
# every resource module takes (../../README.md). The names below are that agreement: change one only together with
# ../postgres and ../redis.

data "azurerm_client_config" "current" {}

locals {
  # northwind/azure builds northwind-azure.
  slug = lower(replace(var.name, "/", "-"))

  # Globally unique and at most 24 characters, so taken from a hash of the environment's name: the same name always
  # gives the same vault, which is how the resource modules find it.
  key_vault_name = "kv-${substr(sha1(var.name), 0, 16)}"

  sizing = {
    dev     = { vm_size = "Standard_B2s", node_count = 1 }
    test    = { vm_size = "Standard_B2s", node_count = 1 }
    staging = { vm_size = "Standard_D2s_v5", node_count = 2 }
    prod    = { vm_size = "Standard_D4s_v5", node_count = 3 }
  }
  size = merge(
    local.sizing[var.stage],
    var.node_vm_size == null ? {} : { vm_size = var.node_vm_size },
    var.node_count == null ? {} : { node_count = var.node_count },
  )

  # Azure refuses a / in a tag's name, so these are lembos-…, where the AWS modules' are lembos.dev/….
  tags = merge(var.tags, {
    "lembos-environment" = var.name
  })
}

resource "azurerm_resource_group" "this" {
  name     = local.slug
  location = var.location
  tags     = local.tags
}

# ── Network ──

resource "azurerm_virtual_network" "this" {
  name                = local.slug
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.cidr_block]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.cidr_block, 4, 0)]
}

# The one address the cluster reaches out from, so a resource's firewall can admit the cluster and nothing else. The
# resource modules read it by this name.
resource "azurerm_public_ip" "outbound" {
  name                = "${local.slug}-outbound"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# ── Cluster ──

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${local.slug}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# The nodes join the subnet, and the load balancer takes the outbound address, both in this group.
resource "azurerm_role_assignment" "cluster_network" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.slug
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.slug
  kubernetes_version  = var.kubernetes_version
  tags                = local.tags

  oidc_issuer_enabled       = var.workload_identity_enabled
  workload_identity_enabled = var.workload_identity_enabled

  default_node_pool {
    name           = "system"
    vm_size        = local.size.vm_size
    node_count     = local.size.node_count
    vnet_subnet_id = azurerm_subnet.nodes.id

    # A new VM size moves the nodes to a pool of this name and back, rather than replacing the whole cluster and
    # everything the slots built in it.
    temporary_name_for_rotation = "rotation"
  }

  # Node auto-provisioning off: the node pool above is the cluster's size.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  # Cilium enforces the slots' network policies (../namespace).
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"

    load_balancer_profile {
      outbound_ip_address_ids = [azurerm_public_ip.outbound.id]
    }
  }

  # The ingress controller AKS runs itself, so a component's ingress needs nothing installed first. Its class is the
  # ingress_class output.
  web_app_routing {
    dns_zone_ids = []
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.workload_identity_enabled ? [1] : []
    content {
      secret_rotation_enabled = true
    }
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.entra_auth_enabled ? [1] : []
    content {
      azure_rbac_enabled = true
      tenant_id          = data.azurerm_client_config.current.tenant_id
    }
  }

  depends_on = [azurerm_role_assignment.cluster_network]
}

# Whoever builds the environment reaches the cluster: the slots' namespaces are made with this, and so is the
# platform's token exchange.
resource "azurerm_role_assignment" "deployer_cluster" {
  count                = var.entra_auth_enabled ? 1 : 0
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Secrets ──

# Where the environment's resources keep their connection strings, read by the slots' identities only (../namespace,
# ../postgres, ../redis). Authorised by Azure RBAC, so access is granted per secret rather than per vault.
resource "azurerm_key_vault" "this" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.stage == "prod"
  tags                       = local.tags
}

# Whoever builds the environment writes its secrets, and so do the resource modules, which run as the same principal.
resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
