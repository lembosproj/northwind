# The second of two substrate levels. The environment's landing zone builds a cluster; this builds what one
# stamp *is* on that cluster — a namespace, its quota, its network policy, and the identity workloads in it
# run as.
#
# Every cluster input is read from the foundation through `environment.outputs.*` rather than configured
# here. A stamp sits on the landing zone its environment resolved to, and naming a second one would be how
# the two come to disagree about which cluster the stamp is on.

variable "cluster_name" {
  description = "The cluster this namespace is created on, from environment.outputs.cluster_name."
  type        = string
}

variable "cluster_endpoint" {
  description = "The cluster's API server, from environment.outputs.cluster_endpoint."
  type        = string
}

variable "cluster_ca" {
  description = <<-EOT
    The API server's certificate authority, base64-encoded, from environment.outputs.cluster_ca.

    Public, which is why it travels as a value rather than as a secret_ref. The credential this module
    actually authenticates with is a short-lived token minted below, and that never leaves the run.
  EOT
  type        = string
  default     = ""
}

variable "name" {
  description = <<-EOT
    The namespace. One per stamp, named for the destination and the slot — two stamps of one environment
    share a cluster whenever they resolve to the same placement, so a name derived from the environment
    alone would have them collide.
  EOT
  type        = string
}

variable "stage" {
  description = "dev, test, staging or prod. What governance matches on, and what sizing follows."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "stage must be dev, test, staging or prod."
  }
}

variable "labels" {
  description = <<-EOT
    The stamp's dimensions, rendered as labels so a placement decision is legible on the cluster itself.

    This is the whole reason a stamp is a boundary rather than a naming convention: `kubectl get ns -l
    lembos.dev/country=nl` answers "what is running for the Netherlands" without anybody having to know how
    the platform names things.
  EOT
  type        = map(string)
  default     = {}
}

variable "quota" {
  description = <<-EOT
    What this slot may consume of the cluster it shares.

    Supplied by the stamp, which is the level that knows: production's two regions are entitled to the same
    as each other and to more than a preview, and none of that is a fact about the landing zone underneath
    them.
  EOT
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
  description = <<-EOT
    Which other namespaces may reach this one, by name.

    Empty is the default a network policy should have: a namespace reaches itself and nothing else until
    somebody writes down what else it needs. The cluster's own DNS is always permitted, because a namespace
    that cannot resolve a name is not isolated, it is broken.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Platform-supplied labels, merged into the AWS resources this creates."
  type        = map(string)
  default     = {}
}
