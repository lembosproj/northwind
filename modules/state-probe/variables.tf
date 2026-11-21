variable "note" {
  description = "What the state records. A new note makes the next run change the state rather than only read it."
  type        = string
  default     = "Kept by Lembos."
}
