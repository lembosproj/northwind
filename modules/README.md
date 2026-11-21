# Northwind Terraform Modules

The Terraform blueprints the Lembos sample organisation is built from, one per
`BlueprintProvisionerType.Terraform` entry the Orchestrator seeds:

| Module | Blueprint | Version | Type |
| --- | --- | --- | --- |
| `postgres-cluster` | `platform/postgres-cluster` | 3.5.0 | Resource |
| `redis-cache` | `platform/redis-cache` | 2.1.0 | Resource |
| `aws-landing-zone` | `platform/aws-landing-zone` | 2.0.0 | Environment |
| `kubernetes-namespace` | the slot level of `platform/aws-landing-zone` | 1.4.0 | Environment |

Each version is an OpenTofu module package in the registry —
`ghcr.io/lembosproj/northwind/modules/{module}:{version}`, one zip layer holding the module — and the seeded
BlueprintVersion pins its manifest digest. Terraform never reads the registry: the worker fetches the package at
that digest and hands Terraform a directory.

To publish, tag `modules/{module}/v{version}` and push the tag; `.github/workflows/modules.yml` zips the module,
pushes it with ORAS, and lists the digest in the run summary. **Never re-push a published version** — the pinned
digest would stop matching, which the platform reports as a mismatch rather than running the new bytes.

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
the five. `postgres-cluster` takes one more:

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

- **`aws-landing-zone`** is a destination's *foundation*: network, identity, cluster, ingress. It is shared
  by every slot resolving to the same placement — two slots differing only in country share one, two
  differing in region do not, because a VPC and a cluster are both regional. Its outputs are the
  `environment.outputs.*` vocabulary everything else reads.
- **`kubernetes-namespace`** is what one slot *is* on top of that: a namespace with its own quota, its own
  network policy and its own service account. It is the level that is not shared, which is what makes a
  slot a boundary rather than a naming convention.

`kubernetes-namespace` reads its cluster from the foundation — `cluster_name`, `cluster_endpoint`,
`cluster_ca` — rather than being configured with one. A slot sits on the landing zone its environment
resolved to, and naming a second here is how the two come to disagree about which cluster the slot is on.

It is also the one module that **configures a provider itself**, against the rule below. The reason is that
its `kubernetes` provider cannot be configured by a root module: what it points at is a cluster that does
not exist until the foundation has run, and arrives here as an input. The `aws` provider it also uses
follows the ordinary rule.

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
