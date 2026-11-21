output "probe_id" {
  description = "Made on the first run and read back from the state on every later one, so a new id means the state was lost."
  value       = terraform_data.probe.id
}
