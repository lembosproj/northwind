# What one stamp *is*, on the cluster its environment built.
#
# The landing zone is shared by every stamp resolving to the same placement — one VPC, one cluster, one
# ingress. This is the part that is not shared: a namespace with its own quota, its own network policy and
# its own identity, so that two stamps on one cluster are a boundary rather than a naming convention.
#
# Nothing here creates a cluster. If this module finds itself needing to, the environment named no
# foundation and the two levels have been confused.

locals {
  # A short-lived token, minted per run from the account credential that built the cluster. This is the
  # whole reason the platform does not store a kubeconfig: reaching a cluster is something the credential
  # that owns it can always do, so a second stored secret would be a second thing to rotate and leak.
  token = data.aws_eks_cluster_auth.this.token

  labels = merge(var.labels, {
    "app.kubernetes.io/managed-by" = "lembos"
    "lembos.dev/stamp"             = var.name
    "lembos.dev/stage"             = var.stage
  })

  # Production gets a policy that names its callers; below it, a namespace talks to anything in the
  # cluster. That is not laxity — a developer debugging across two namespaces in dev should not have to
  # publish a policy change to do it, and there is nothing in dev worth the isolation.
  restricted = var.stage == "prod" || var.stage == "staging"

  secret_ref = "${var.cluster_name}/${var.name}/service-account"
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = var.cluster_ca != "" ? base64decode(var.cluster_ca) : null
  token                  = local.token
}

# ── The slot ──

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.name
    labels = local.labels
  }
}

# What this stamp may consume of a cluster it shares. Without it one stamp's runaway deployment is every
# stamp's outage, which is the failure a shared cluster exists to be worth risking.
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "stamp"
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

# A default every pod inherits, so a container that declares nothing still counts against the quota above.
# Without this a quota is advisory: a namespace with unspecified pods admits them until the node fills.
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

# Denies everything not named below. Written as one policy rather than a deny-all plus allowances, because
# two policies are additive in Kubernetes and a reader has to hold both to know what is permitted.
resource "kubernetes_network_policy_v1" "ingress" {
  count = local.restricted ? 1 : 0

  metadata {
    name      = "stamp-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    # Itself, always. A namespace whose pods cannot reach each other is not isolated, it is broken.
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

    # The ingress controller, which lives outside this namespace and is how anything from outside the
    # cluster arrives. Omitted, a restricted stamp publishes nothing.
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
    }
  }
}

# Egress is deliberately not restricted, and that is a decision rather than an omission. A workload here
# reaches managed databases, object storage and third-party APIs by address, and a policy naming them would
# be a second copy of every resource binding in the catalog — one that goes stale silently the first time a
# resource is re-provisioned.

# ── Who it runs as ──

# The identity workloads in this namespace assume, bound to the cluster's OIDC issuer by the landing zone's
# provider. It carries no policy: what a component may do in the account is that component's decision, and
# granting it here would give every workload in the stamp the union of them.
resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = "workload"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
}

# The path, not the token. Recorded so a deployment into this stamp has one place to look for how to
# authenticate, and so that what leaves this module is a reference rather than a credential.
resource "aws_secretsmanager_secret" "service_account" {
  name = local.secret_ref
  tags = merge(var.tags, local.labels)
}

resource "aws_secretsmanager_secret_version" "service_account" {
  secret_id = aws_secretsmanager_secret.service_account.id

  secret_string = jsonencode({
    cluster         = var.cluster_name
    namespace       = kubernetes_namespace_v1.this.metadata[0].name
    service_account = kubernetes_service_account_v1.this.metadata[0].name
  })
}
