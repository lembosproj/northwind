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
