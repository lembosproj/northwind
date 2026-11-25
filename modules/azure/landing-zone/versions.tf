# Declared here and configured by the root module Lembos writes for every run, with the subscription of the target it
# runs in, so the same module runs against the local emulator and a real subscription.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
  }
}
