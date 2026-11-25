# Declared here and configured by the root module Lembos writes for the run, so the module runs unchanged against the
# local emulator and a real subscription.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}
