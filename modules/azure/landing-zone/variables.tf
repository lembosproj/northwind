variable "name" {
  description = "The Environment's qualified name, e.g. northwind/azure. Everything here is named after it."
  type        = string
}

variable "stage" {
  description = <<-EOT
    dev, test, staging or prod: EnvironmentStage's own values, which the platform resolves `environment.stage` to.
    What sizing follows.
  EOT
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "stage must be dev, test, staging or prod."
  }
}

variable "node_vm_size" {
  description = <<-EOT
    The nodes' VM size, instead of the one the stage gives (dev and test Standard_B2s, staging Standard_D2s_v5, prod
    Standard_D4s_v5). Null keeps the stage's. For a region or subscription that does not offer the stage's size: a
    trial in germanywestcentral, for one, offers no B-series.
  EOT
  type        = string
  default     = null
}

variable "node_count" {
  description = <<-EOT
    How many nodes, instead of the stage's (dev and test 1, staging 2, prod 3). Null keeps the stage's. One 2-vCPU
    node cannot hold much more than AKS's own pods: its app routing alone asks for a whole vCPU.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.node_count == null || try(var.node_count >= 1, false)
    error_message = "node_count must be 1 or more, or null for the stage's."
  }
}

variable "location" {
  description = <<-EOT
    The Azure region, e.g. swedencentral. An input, unlike the AWS landing zone's region: the azurerm provider has no
    region of its own to read it from. One region per environment, because the network and the cluster are regional.
  EOT
  type        = string
}

variable "cidr_block" {
  description = "The virtual network's address space. The nodes' subnet is carved out of it; pods use an overlay."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "kubernetes_version" {
  description = "Pinned by the blueprint rather than chosen per environment, so a fleet stays on one version."
  type        = string
  default     = "1.33"
}

variable "ingress_domain" {
  description = "The zone this environment publishes under. Echoed as an output for a component's ingress host."
  type        = string
  default     = ""
}

variable "workload_identity_enabled" {
  description = <<-EOT
    Whether the cluster publishes an OIDC issuer for workload identity, and runs the Key Vault provider that copies a
    component's secrets into the cluster as the slot's identity.

    True on every real subscription. It exists because the local emulator stores both settings and runs neither: its
    k3s cluster has no issuer and no Key Vault provider, so a slot would make identities nothing can sign in as, and a
    pod that mounts the provider's volume would never start. As the AWS landing zone's irsa_enabled is, it is an input
    because the module cannot tell the emulator from a real subscription before the cluster exists.
  EOT
  type        = bool
  default     = true
}

variable "entra_auth_enabled" {
  description = <<-EOT
    Whether the cluster signs people and the platform in with Entra and authorises them with Azure RBAC, so the platform
    reaches a slot by exchanging its subscription credential for an Entra token to the cluster, as it does on EKS.

    True on every real subscription. False on the local emulator, whose k3s cluster accepts no Entra token: the platform
    then asks Resource Manager for the cluster's admin credential each time it reaches the cluster.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Platform-supplied labels, merged into every resource's tags."
  type        = map(string)
  default     = {}
}
