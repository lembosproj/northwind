# azure/landing-zone

The substrate an Azure environment sits on: a resource group, a network, an AKS cluster, a vault for the secrets its
resources make, and a fixed address the cluster reaches out from. An **Environment** blueprint, named by an
`EnvironmentVersion` as its foundation; the Azure twin of [../../aws/landing-zone](../../aws/landing-zone/README.md),
kept to the minimum the slots and the sample's resources need.

Built once per environment and shared by every slot in it. Each slot is a namespace on this cluster, built by the
blueprint's slot level, [../namespace](../namespace). Nothing here is named after a slot: `northwind/azure` builds the
resource group and the cluster `northwind-azure`.

## What it builds

| | |
| --- | --- |
| Network | A virtual network and the nodes' subnet; pods use Cilium's overlay |
| Outbound | One static public address the cluster reaches out from, which a resource's firewall admits |
| Cluster | AKS with Azure CNI powered by Cilium, one node pool sized by stage, and AKS's own ingress controller (web app routing) |
| Identity | The cluster's managed identity; the OIDC issuer and workload identity for the slots' identities |
| Secrets | A Key Vault authorised by Azure RBAC, and the Key Vault provider that copies a secret into a slot |
| Access | Azure RBAC on the cluster for whoever builds it; no kubeconfig is stored |

## Why it takes its region

The `azurerm` provider has no region of its own to read, so `location` is an input, answered by the environment
version. One region per environment: the network and the cluster are both regional.

## The names the resource modules find

The resource modules keep the five inputs every resource module takes, so they find what they need here by a name
made from the environment: the resource group, the vault (`kv-` and a hash of the environment's name), the outbound
address (`{group}-outbound`), and the slot's identity. The table is in [../../README.md](../../README.md); change a
name only together with [../postgres](../postgres) and [../redis](../redis).

## Against the emulator

The local Azure emulator runs the cluster (k3s) and stores the rest. Two inputs say what it cannot do, as the AWS
landing zone's `irsa_enabled` does, because the module cannot tell the emulator from a subscription before the
cluster exists:

- `workload_identity_enabled = false`: its cluster has no OIDC issuer and no Key Vault provider, so a slot makes no
  identity, and a component runs as the slot's service account and signs in as nothing.
- `entra_auth_enabled = false`: its cluster takes no Entra token, so the platform asks Resource Manager for the
  cluster's admin credential each time it reaches it (`AksAdminCredentialExchange`). On a real subscription the platform
  asks Entra for a token to the cluster instead (`AksEntraTokenExchange`). Neither is stored.

Network security rules, routing and role assignments are stored and not enforced there, so a run proves the recipe
applies, the state is kept and the outputs are produced, not that traffic is held to the firewall.
