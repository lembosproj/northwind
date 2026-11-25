# Northwind Terraform Modules

The Terraform blueprints the Lembos sample organisation is built from, one folder per cloud. The two clouds take the
same inputs and give the same outputs, so a spec reads a resource the same way wherever it stands:

| Module | Blueprint | Version | Type |
| --- | --- | --- | --- |
| `aws/landing-zone` | `aws/landing-zone` | 1.0.0 | Environment |
| `aws/namespace` | the slot level of `aws/landing-zone` | 1.0.0 | Environment |
| `aws/postgres` | `aws/postgres` | 1.0.0 | Resource |
| `aws/redis` | `aws/redis` | 1.0.0 | Resource |
| `azure/landing-zone` | `azure/landing-zone` | 1.0.2 | Environment |
| `azure/namespace` | the slot level of `azure/landing-zone` | 1.0.1 | Environment |
| `azure/postgres` | `azure/postgres` | 1.0.1 | Resource |
| `azure/redis` | `azure/redis` | 1.0.1 | Resource |

Each version is an OpenTofu module package in the registry —
`ghcr.io/lembosproj/northwind/modules/{cloud}/{module}:{version}`, one zip layer holding the module — and the seeded
BlueprintVersion pins its manifest digest. Terraform never reads the registry: the worker fetches the package at
that digest and hands Terraform a directory.

To publish, tag `modules/{cloud}/{module}/v{version}` and push the tag; `.github/workflows/modules.yml` zips the
module, pushes it with ORAS, and lists the digest in the run summary. **Never re-push a published version** — the
pinned digest would stop matching, which the platform reports as a mismatch rather than running the new bytes.

## The stage vocabulary

Every module taking a `stage` takes `dev`, `test`, `staging` or `prod`. Those are `EnvironmentStage`'s own
values, not their display names: the platform resolves `environment.stage` to the canonical value,
so a module validating `Production` refuses every real run with a message about a vocabulary nobody sent.

## The variable contract

Every **resource** module takes the same five inputs. The blueprint answers each of them from what Lembos
knows about the run, so a resource's spec has nothing it must supply:

| Variable | Answered by |
| --- | --- |
| `name` | the Resource's qualified name, e.g. `ordering/orders-db` — `resource.qualifiedName` |
| `size_class` | the tier the destination publishes — `environment.outputs.tier` — which a spec may move |
| `environment` | the Environment's name — `environment.name` |
| `slot` | the slot the instance occupies — `environment.slot.name` |
| `tags` | the blueprint, merged into the provider's tags |

**What a size class means is decided per module, in its `locals`.** That is deliberate: `small` for
Postgres is a different decision from `small` for Redis, and the developer declaring the need should not
have to know either.

A module may take more than these five, but each extra input needs a default: a run is only sure to pass
the five. `aws/postgres` takes one more:

| Variable | Answered by |
| --- | --- |
| `snapshot_before_destroy` | the Resource's retention — `retention.snapshotBeforeDestroy` — false when the blueprint does not bind it |

When it is true, destroying or replacing the instance first takes a snapshot named `{identifier}-final`. The
name is the same each time for one placement, so delete that snapshot before the placement is destroyed with
a snapshot again.

Every resource module returns the same four outputs:

| Output | Meaning |
| --- | --- |
| `resource_id` | the provider's identifier, recorded as provisioning output |
| `endpoint` | where the workload connects |
| `port` | the port, where the resource has one |
| `secret_ref` | **the vault path holding the credential — never the credential** |

`secret_ref` is the contract that keeps a secret out of Terraform state and out of the Orchestrator. It is
what a chart's `resourceBindings.<handle>.secretRef` is set from.

## The Environment modules, and the two levels they sit at

An Environment module produces **somewhere to run** rather than something that runs, so it takes an
environment, a slot and a stage rather than the resource contract above. There are two levels of it, and
the difference is what is shared:

- **`aws/landing-zone`** is a destination's *foundation*: network, identity, cluster, ingress. It is shared
  by every slot resolving to the same placement — two slots differing only in country share one, two
  differing in region do not, because a VPC and a cluster are both regional. Its outputs are the
  `environment.outputs.*` vocabulary everything else reads.
- **`aws/namespace`** is what one slot *is* on top of that: a namespace with its own quota, its own
  network policy and its own service account. It is the level that is not shared, which is what makes a
  slot a boundary rather than a naming convention.

`aws/namespace` reads its cluster from the foundation — `cluster_name`, `cluster_endpoint`,
`cluster_ca` — rather than being configured with one. A slot sits on the landing zone its environment
resolved to, and naming a second here is how the two come to disagree about which cluster the slot is on.

It is also the one module that **configures a provider itself**, against the rule below. The reason is that
its `kubernetes` provider cannot be configured by a root module: what it points at is a cluster that does
not exist until the foundation has run, and arrives here as an input. The `aws` provider it also uses
follows the ordinary rule.

## The Azure modules, and what they find by name

`azure/landing-zone` and `azure/namespace` are the same two levels on Azure: a resource group, a network, an AKS
cluster, a vault and a fixed outbound address per environment; a namespace, its quota and policy, and an identity per
slot. The slot's `workload` service account signs in as that identity through workload identity, and the charts run as
it (`identity` in [../charts/README.md](../charts/README.md)).

An Azure resource needs its environment's resource group, vault and cluster address, and the slot's identity, where an
AWS one needs nothing of its environment. Asking for them as inputs would break the five-input contract, so the
landing zone gives each a name made from the environment, and `azure/postgres` and `azure/redis` find them by it:

| What | Name |
| --- | --- |
| The resource group, the cluster | the environment, `northwind/azure` → `northwind-azure` |
| The vault | `kv-` and 16 characters of a hash of the environment |
| The cluster's outbound address | `{group}-outbound` |
| The slot's identity | `{group}-{slot}-workload` |

Each keeps its connection string in the vault under its `secret_ref` path with dashes for slashes, and grants the
slot's identity read on that one secret. `secret_ref` is the same path as on AWS, so a binding reads it the same way.

## Trying where state is kept

`state-probe` is not seeded. It builds one `terraform_data` resource and needs no provider, so its run writes a
state file and reaches nothing else. Use it to try a state backend, such as state in an Azure subscription, without
building anything that costs money.

Point a blueprint at it by its Git source: this repository, a ref, and the path `modules/state-probe`. Its
`probe_id` output is made on the first run and read back from the state on every later run. A different id means the
state was lost. Give `note` a new value to make the next run change the state rather than only read it.

## Running against Floci

Modules declare required providers but **do not configure them** — the root module does, which is what
lets the same module run against Floci locally and a real account elsewhere. Lembos writes that root module for
every run, with the endpoints of the target it runs in, so Floci is reached the same way a real account is.

The Azure emulator stores what it does not run. Two landing zone inputs say so, as `aws/landing-zone`'s
`irsa_enabled` does: `workload_identity_enabled` (no issuer, no Key Vault provider in its k3s cluster) and
`entra_auth_enabled` (its cluster takes no Entra token, so the platform reaches it with the kubeconfig kept in the
vault). Both default to true, which is what a real subscription takes. The emulator also records a PostgreSQL
database without making it, so a workload there creates its database itself.
