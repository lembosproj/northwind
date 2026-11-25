# The second of two substrate levels: what one slot is on the cluster ../landing-zone built. The cluster is read from
# the foundation through `environment.outputs.*`, never configured here, so a slot cannot name a cluster its
# environment did not resolve to.

variable "cluster_name" {
  description = "The cluster this namespace is made on, from environment.outputs.cluster_name."
  type        = string
}

variable "resource_group" {
  description = "Where the cluster and its environment's identities live, from environment.outputs.resource_group."
  type        = string
}

variable "oidc_issuer" {
  description = <<-EOT
    The cluster's OIDC issuer, from environment.outputs.oidc_issuer. Empty where the landing zone has no workload
    identity (the local emulator): the slot then makes no identity, and its service account signs in as nothing.
  EOT
  type        = string
  default     = ""
}

variable "name" {
  description = "The namespace. One per slot, named for the environment and the slot, so two slots never collide."
  type        = string
}

variable "slot" {
  description = <<-EOT
    The slot's own name, environment.slot.name. The slot's identity is named after it, which is how the resource
    modules placed in this slot find the identity to give their secrets to. Defaults to the namespace's name.
  EOT
  type        = string
  default     = ""
}

variable "stage" {
  description = "dev, test, staging or prod. What governance matches on."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "stage must be dev, test, staging or prod."
  }
}

variable "labels" {
  description = "The slot's dimensions, rendered as labels so a placement decision is legible on the cluster."
  type        = map(string)
  default     = {}
}

variable "quota" {
  description = "What this slot may consume of the cluster it shares."
  type = object({
    requests_cpu    = optional(string, "4")
    requests_memory = optional(string, "8Gi")
    limits_cpu      = optional(string, "8")
    limits_memory   = optional(string, "16Gi")
    pods            = optional(number, 40)
  })
  default = {}
}

variable "allowed_namespaces" {
  description = "Which other namespaces may reach this one, by name. Empty: only itself and the ingress controller."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Platform-supplied labels, merged into the Azure resources this makes."
  type        = map(string)
  default     = {}
}

variable "instance_marks" {
  description = <<-EOT
    The instance's marks, lembos-instance and lembos-instance-type, merged into the tags of everything this makes.
    The platform hands them over as instance.marks, because azurerm has no tags for every resource.
  EOT
  type        = map(string)
  default     = {}
}
