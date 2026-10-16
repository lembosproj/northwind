# The environment.outputs.* vocabulary. Every one of these is something a component blueprint reads to wire
# itself into this destination — which is the whole reason an environment publishes anything at all.
#
# Nothing here is an ExecutionTarget. The cluster this builds is a realisation output of the environment
# instance that asked for it, reached through the account credential that built it; a run does not register
# somewhere new to run.

# ── The resource-module contract, so anything reading a provisioning output reads this one the same way ──

output "resource_id" {
  value = aws_eks_cluster.this.name
}

output "endpoint" {
  description = "The API server. What a deployment connects to."
  value       = aws_eks_cluster.this.endpoint
}

output "port" {
  description = "Carried in the endpoint, so null rather than a second copy that could disagree with it."
  value       = null
}

output "secret_ref" {
  description = "Where the kubeconfig is kept. Never the kubeconfig itself."
  value       = aws_secretsmanager_secret.kubeconfig.name
}

# ── Network ──

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Where nodes and anything they run belong."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Where load balancers belong, and nothing else."
  value       = aws_subnet.public[*].id
}

output "node_security_group_id" {
  description = "What a resource opens to when it wants to be reachable from this environment's workloads."
  value       = aws_security_group.node.id
}

# ── Cluster ──

output "region" {
  description = "Where the cluster is, which every slot's Kubernetes target is reached in."
  value       = var.region
}

output "cluster_name" {
  description = "What `aws eks get-token` is called with, which is how a deployment authenticates."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca" {
  description = "The API server's CA, base64-encoded. Public, so it travels as a value rather than a reference."
  value       = try(aws_eks_cluster.this.certificate_authority[0].data, null)
}

output "oidc_issuer" {
  description = <<-EOT
    What binds a workload identity to this cluster. Null where the cluster publishes no issuer, which is
    an emulator rather than an account — see `irsa_enabled`.
  EOT
  value       = try(aws_eks_cluster.this.identity[0].oidc[0].issuer, null)
}

output "oidc_provider_arn" {
  description = <<-EOT
    What an IRSA role trusts. Every role scoped to this cluster names it, and it is null where there is no
    provider to name — see `irsa_enabled`.
  EOT
  value       = try(aws_iam_openid_connect_provider.this[0].arn, null)
}

output "irsa_role_arns" {
  description = "The roles the in-cluster controllers assume, by the service account each is bound to."
  value       = { for name, role in aws_iam_role.irsa : name => role.arn }
}

# ── Ingress ──

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "For an alias record pointing at this load balancer from another zone."
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "hosted_zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "ingress_domain" {
  description = <<-EOT
    The zone this environment publishes under. A component's ingress host is built from it, which is what
    lets one template — `{component}.{environment.outputs.ingress_domain}` — hold in every environment.
  EOT
  value       = local.domain
}

output "kubeconfig_secret_ref" {
  description = "The path holding the kubeconfig. Never the kubeconfig itself."
  value       = aws_secretsmanager_secret.kubeconfig.name
}
