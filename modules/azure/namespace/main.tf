# What one slot is on the cluster its environment built: a namespace with its own quota, network policy and identity.
# The Azure twin of ../../aws/namespace; the slot's Kubernetes objects are the same, and its identity is Azure's.
#
# The identity is a user-assigned managed identity trusting this namespace's `workload` service account through the
# cluster's OIDC issuer. It holds no role here: each resource placed in the slot grants it read on its own secret
# (../postgres, ../redis), so a slot's workloads read what is theirs and nothing else in the vault.

locals {
  slot = var.slot != "" ? var.slot : var.name

  # The name the resource modules look the identity up by. Change only together with ../postgres and ../redis.
  identity_name = "${var.cluster_name}-${local.slot}-workload"

  workload_identity = var.oidc_issuer != ""

  labels = merge(var.labels, {
    "app.kubernetes.io/managed-by" = "lembos"
    "lembos.dev/slot"              = var.name
    "lembos.dev/stage"             = var.stage
  })

  # As on AWS: production and staging name their callers; below them a namespace talks to anything in the cluster.
  restricted = var.stage == "prod" || var.stage == "staging"

  # The admin credential where the cluster signs in with Entra, else the one kubeconfig the cluster has (the emulator).
  access = length(data.azurerm_kubernetes_cluster.this.kube_admin_config) > 0 ? data.azurerm_kubernetes_cluster.this.kube_admin_config[0] : data.azurerm_kubernetes_cluster.this.kube_config[0]
}

data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group
}

data "azurerm_resource_group" "this" {
  name = var.resource_group
}

# Read per run from the cluster with the subscription credential that built it, and never stored by the slot.
provider "kubernetes" {
  host                   = local.access.host
  cluster_ca_certificate = base64decode(local.access.cluster_ca_certificate)
  client_certificate     = base64decode(local.access.client_certificate)
  client_key             = base64decode(local.access.client_key)
}

# ── The slot ──

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.name
    labels = local.labels
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "slot"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "pods"            = var.quota.pods
    }
  }
}

# Without a default every pod inherits, a container that declares nothing escapes the quota above.
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "defaults"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# ── Who may reach in ──

resource "kubernetes_network_policy_v1" "ingress" {
  count = local.restricted ? 1 : 0

  metadata {
    name      = "slot-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {}
      }
    }

    dynamic "ingress" {
      for_each = var.allowed_namespaces

      content {
        from {
          namespace_selector {
            match_labels = {
              "kubernetes.io/metadata.name" = ingress.value
            }
          }
        }
      }
    }

    # AKS's web app routing runs its controller in app-routing-system, not kube-system.
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "app-routing-system"
          }
        }
      }
    }
  }
}

# ── Who it runs as ──

resource "azurerm_user_assigned_identity" "workload" {
  count               = local.workload_identity ? 1 : 0
  name                = local.identity_name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = var.resource_group
  # Azure refuses a / in a tag's name; the Kubernetes labels above keep lembos.dev/slot.
  tags = merge(var.tags, { "lembos-slot" = var.name })
}

resource "azurerm_federated_identity_credential" "workload" {
  count                     = local.workload_identity ? 1 : 0
  name                      = var.name
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer
  subject                   = "system:serviceaccount:${var.name}:workload"
}

# What every component placed in the slot runs as (identity.serviceAccount in the charts). Annotated with the slot
# identity's client id, which is what the AKS webhook reads to sign a pod in as it.
resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = "workload"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
    annotations = local.workload_identity ? {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload[0].client_id
    } : {}
  }
}
