# The contract every resource module takes (../../README.md). Lembos passes these without knowing which module it is
# calling, so this module asks for nothing else: what it needs of its environment it finds by name (../landing-zone).

variable "name" {
  description = "The Resource's qualified name, e.g. ordering/orders-db."
  type        = string
}

variable "size_class" {
  description = "Relative sizing: small, medium or large."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.size_class)
    error_message = "size_class must be small, medium or large."
  }
}

variable "environment" {
  description = "The Environment's qualified name, e.g. northwind/azure."
  type        = string
}

variable "slot" {
  description = "The slot this instance occupies, e.g. default."
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Platform-supplied labels, merged into the resource's tags."
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
