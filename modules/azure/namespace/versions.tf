# Two providers, and only one of them is configured by the root, as in ../../aws/namespace.
#
# `azurerm` is configured by the root module Lembos writes for the run. `kubernetes` is configured in main.tf, because
# what it points at is the cluster this slot resolved to, which exists only once the environment's landing zone has run.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}
