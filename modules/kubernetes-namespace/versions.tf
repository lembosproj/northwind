# Two providers, and only one of them is configured by the root.
#
# `aws` follows the rule the rest of this repository follows: declared here, configured by the root module,
# which is what lets the same module run against Floci locally and a real account elsewhere.
#
# `kubernetes` is the exception, and it is configured in main.tf. The reason is that its configuration is
# not something a root module could supply: it is the cluster this stamp resolved to, which does not exist
# until the environment's landing zone has run and is passed in here as `cluster_endpoint` and `cluster_ca`.
# A root written before the foundation ran would have nothing to put in the block.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}
