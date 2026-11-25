# Providers are required but not configured: the root module owns that, which is what lets the same
# module run against Floci locally and a real account elsewhere.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
    # random generates the master credential, which never leaves this module in plaintext.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}
