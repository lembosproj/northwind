# A module that keeps only its state. Its run writes a state file wherever its blueprint keeps state — with Lembos, in
# an S3 bucket, in a cluster or in Azure — so a backend can be tried without building anything or paying for it.

resource "terraform_data" "probe" {
  input = var.note
}
