# The contract every resource module takes. See ../README.md — Lembos passes these without knowing
# which module it is calling, so a module that adds a required input here becomes unschedulable.

variable "name" {
  description = "The Resource's qualified name, e.g. ordering/orders-db."
  type        = string
}

variable "size_class" {
  description = "Relative sizing from the ResourceNeed: small, medium or large."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.size_class)
    error_message = "size_class must be small, medium or large."
  }
}

variable "environment" {
  description = "The Environment's qualified name, e.g. northwind/prod."
  type        = string
}

variable "stamp" {
  description = "The Stamp this instance occupies, e.g. eu-west."
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Platform-supplied labels, merged into the provider's tags."
  type        = map(string)
  default     = {}
}

variable "engine_version" {
  description = "Postgres major version. Pinned by the blueprint rather than chosen per resource."
  type        = string
  default     = "16.4"
}
