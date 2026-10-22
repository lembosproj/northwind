# Northwind

The software the Lembos sample organisation runs: the workloads, the Helm charts that deploy them, and the
Terraform modules that build where they run. One repository, so a change that crosses them — a chart taking the
dependencies an app reports — is one change.

| Directory | What | Published to |
| --- | --- | --- |
| [`apps/`](apps/README.md) | the two archetype workloads and the API contracts | `ghcr.io/lembosproj/northwind/apps/{component}` |
| [`charts/`](charts/README.md) | the component blueprints' charts | `oci://ghcr.io/lembosproj/northwind/charts/{chart}` |
| [`modules/`](modules/README.md) | the resource and environment blueprints' modules | `ghcr.io/lembosproj/northwind/modules/{module}` |

**The platform reads the registry, never this repository's history.** A seeded blueprint version names a package
and a version and pins the manifest digest the push produced, so what the seed depends on is that each package
exists at that digest. The repository is still where a reader is linked to see the source, and where the API
contracts are served from.

## Publishing

Every artifact is versioned by a tag that names it, because one repository holds all of them:

| Tag | Publishes |
| --- | --- |
| `apps/v{version}` | every component's image, `{version}` and `sha-{commit}` |
| `charts/{chart}/v{version}` | that chart at that version |
| `modules/{module}/v{version}` | that module at that version |

Push tags **one at a time**. GitHub starts no workflow for a push of more than three tags, so a bulk
`git push --tags` publishes nothing and says nothing.

Each run lists the digest it produced in its summary, which is the value the platform's seed pins. A published
version is never pushed again: its digest would change under the pin, which the platform reports as a mismatch.

## Registering builds with the platform

A push that changes an app also registers each component's image with a Lembos platform as that component's
artifact, through the platform's
[publish-artifact action](https://github.com/lembosproj/platform/tree/main/src/Integrations/GitHub/publish-artifact).
The build then shows on the component's **Artifacts** tab, with this repository, the commit, the ref and the run as
its provenance. The `register` job in `apps.yml` does it after the images are pushed. It is skipped when no
platform is configured, so a fork builds without one.

It signs in as one service account for the whole northwind GitHub organisation, which is one account per CI
system. An Administrator created it in the Portal under **Organization → Service accounts**:

| Setting | Value | Why |
| --- | --- | --- |
| Name | `northwind-github` | The CI system it serves |
| Owner | **Commerce Tribe** | The lowest group above the Ordering and Checkout squads, which own every component built here. Owning a group gives the account reach over its subtree |
| Role | **Maintainer** | Holds `infrastructure:artifacts:write`, and the reads the action makes |

Creating it downloaded `<client id>.pem` once. The repository (or the organisation) holds:

| Name | Type | Value |
| --- | --- | --- |
| `LEMBOS_CLIENT_ID` | secret | The account's client id |
| `LEMBOS_PRIVATE_KEY` | secret | The whole `.pem` file |
| `LEMBOS_IDENTITY_URL` | variable | The platform's Identity Server |
| `LEMBOS_ORCHESTRATOR_URL` | variable | The platform's Orchestrator API; unset, the `register` job is skipped |

A component owned outside Commerce Tribe, such as `platform/order-flow-monitor`, is out of the account's reach.
Building one here would need an owner group above both, or a second account.

## The versions the seed expects

| Package | Version | Seeded as |
| --- | --- | --- |
| `charts/web-service` | 2.2.0 | deprecated |
| `charts/web-service` | 2.3.0 | withdrawn and **never published** — the seed expects it to be missing |
| `charts/web-service` | 2.4.0 | deprecated |
| `charts/web-service` | 2.5.0-rc.1 | staged |
| `charts/web-service` | 2.6.0 | current |
| `charts/worker` | 1.9.0 | deprecated |
| `charts/worker` | 1.10.0 | current |
| `modules/postgres-cluster` | 3.3.1 | current |
| `modules/redis-cache` | 2.0.3 | current |
| `modules/aws-landing-zone` | 2.0.0 | current |
| `modules/kubernetes-namespace` | 1.3.0 | the landing zone's slot level |
| `apps/*` | 1.1.0 | each component's build |

The deprecated versions and the release candidate are the charts before they took a component's dependencies.

Packages must be **public**: the seed carries no source credential, so the platform fetches anonymously.
