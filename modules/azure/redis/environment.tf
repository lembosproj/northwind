# What this resource finds of its environment, by the names ../landing-zone and ../namespace give them. Those names
# are the agreement that keeps the five inputs enough: change one only together with both modules.

locals {
  environment_slug = lower(replace(var.environment, "/", "-"))
  key_vault_name   = "kv-${substr(sha1(var.environment), 0, 16)}"
  identity_name    = "${local.environment_slug}-${var.slot}-workload"

  # The path the AWS modules keep a secret at, so a binding's secretRef reads the same on either cloud. Key Vault allows
  # no slash in a name, so the secret is that path with dashes, which is the name the charts derive from it.
  secret_ref  = "${var.environment}/${var.slot}/${var.name}"
  secret_name = lower(replace(local.secret_ref, "/", "-"))

  # One per placement, as on AWS: the same resource stands in every slot it is placed in, and the name is global.
  placement  = lower(join("-", [local.environment_slug, var.slot, replace(var.name, "/", "-")]))
  identifier = length(local.placement) <= 50 ? local.placement : "${trimsuffix(substr(local.placement, 0, 41), "-")}-${substr(md5(local.placement), 0, 8)}"

  # Azure refuses a / in a tag's name, so these are lembos-…, where the AWS modules' are lembos.dev/….
  tags = merge(var.tags, var.instance_marks, {
    "lembos-resource"    = var.name
    "lembos-environment" = var.environment
    "lembos-slot"        = var.slot
  })
}

data "azurerm_resource_group" "environment" {
  name = local.environment_slug
}

data "azurerm_key_vault" "environment" {
  name                = local.key_vault_name
  resource_group_name = local.environment_slug
}

# The slot's identity, where the slot has one: none on the local emulator, which has no workload identity. Listed rather
# than read directly, because reading a missing identity fails the run.
data "azurerm_resources" "slot_identity" {
  type                = "Microsoft.ManagedIdentity/userAssignedIdentities"
  name                = local.identity_name
  resource_group_name = local.environment_slug
}

data "azurerm_user_assigned_identity" "slot" {
  count               = length(data.azurerm_resources.slot_identity.resources) > 0 ? 1 : 0
  name                = local.identity_name
  resource_group_name = local.environment_slug
}
