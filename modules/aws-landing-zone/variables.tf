# The landing zone an environment declares once and every slot in it shares.
#
# An Environment blueprint's own level, so it takes the environment and nothing about any one slot. Unlike
# eks-cluster it builds the whole substrate — network, identity, cluster and ingress — which is what an
# environment needs before anything can be deployed into it.

variable "name" {
  description = "The Environment's qualified name, e.g. northwind/prod."
  type        = string
}

variable "stage" {
  description = <<-EOT
    dev, test, staging or prod. What governance matches on, and what sizing follows.

    These are EnvironmentStage's own values, not their display names. The platform resolves
    `context.environment.stage` to the canonical value — `prod`, not `Production` — so a module validating
    the display names refuses every real run with a message about a vocabulary nobody sent.
  EOT
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "stage must be dev, test, staging or prod."
  }
}

variable "region" {
  description = <<-EOT
    Where it is built. The environment's answer rather than the account's: an account spans regions. One
    region per environment, because a VPC and a cluster are both regional and every slot shares them — an
    estate in two regions is two environments.
  EOT
  type        = string
  default     = "eu-west-1"
}

variable "cidr_block" {
  description = "The VPC's address space. Wide enough for the subnets below to be carved out of it."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = <<-EOT
    How many zones to spread across. Two is the floor, because an EKS control plane will not come up in
    one and an environment that cannot survive a zone is not a production environment.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 4
    error_message = "availability_zones must be between 2 and 4."
  }
}

variable "kubernetes_version" {
  description = "Pinned by the blueprint rather than chosen per environment, so a fleet stays on one version."
  type        = string
  default     = "1.31"
}

variable "ingress_domain" {
  description = <<-EOT
    The zone this environment publishes under, e.g. de.northwind.example. Becomes the hosted zone and the
    wildcard record pointing at the load balancer, and is what a component's ingress host is built from.
  EOT
  type        = string
  default     = ""
}

variable "irsa_enabled" {
  description = <<-EOT
    Whether to build the cluster's OIDC provider and the IRSA roles that trust it.

    True everywhere it can be, which is every real account: EKS always publishes an OIDC issuer, and
    without the provider nothing in the cluster can assume a role without a static credential.

    It exists because an emulator does not publish one. The issuer is read off the cluster after it is
    created, so a module cannot decide this for itself — on a first plan the attribute is still unknown,
    which is not something a `count` can be derived from, and on the plan after an emulated apply it is a
    known empty list that fails the whole plan on an index rather than on anything to do with the run. An
    input is the only form of this question that can be answered before the cluster exists.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
