# No provider at all: the module builds nothing outside its own state, so a run of it tries where its state is kept and
# nothing else. terraform_data is built into Terraform from 1.4 and into every OpenTofu release.
terraform {
  required_version = ">= 1.4.0"
}
