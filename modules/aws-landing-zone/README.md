# aws-landing-zone

The substrate an environment sits on: a network, the identity to act in it, a cluster, and a way in from
outside. An **Environment** blueprint, named by an `EnvironmentVersion` as its foundation.

Built once per environment and shared by every slot in it — each slot is a namespace on this cluster, built by
the blueprint's slot level. Nothing here is named after a slot, so the cluster, the VPC and the kubeconfig secret
are named after the environment alone (`northwind/prod` builds `northwind-prod`).

## What it builds

| | |
| --- | --- |
| Network | VPC, public and private subnets across 2–4 zones, internet gateway, NAT (one per zone in production, one shared below it), route tables |
| Security | Security groups for the load balancer and the nodes, with the nodes reachable only from the load balancer and from each other |
| Identity | Cluster and node roles, an OIDC provider, and IRSA roles for the load balancer controller and external-dns |
| Cluster | EKS control plane and a managed node group, sized by stage |
| Ingress | An application load balancer, a default target group and listener, a private hosted zone, and a wildcard record pointing at the balancer |

## Why it takes a region rather than reading one

An account spans regions, so the region is the environment version's answer. It is one region per environment:
a VPC and an EKS cluster are both regional and every slot shares them, so an estate in two regions is two
environments. It is published as the `region` output, which is where each slot's Kubernetes target reads it.

## Against the emulator

Every control-plane call here succeeds against Floci, and the EKS cluster is real — it runs k3s in a
container with an IAM authentication webhook, so `aws eks get-token` and `kubectl` both work.

What is metadata only: NAT gateways route nothing, the load balancer has no data plane, and Route53 names
do not resolve. A run therefore proves the recipe applies, the state is kept, and the outputs are produced
— not that traffic flows. The difference is confined to the emulator: no variable here mentions it, because
the provider and the endpoints are the root module's business, which is what lets this run unchanged
against a real account.
