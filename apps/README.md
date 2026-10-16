# Northwind Apps

The archetype workloads the Lembos sample organisation deploys. **Two apps cover every seeded component**,
because a component is not a distinct program — it is an instance of a blueprint, and there are two
component blueprints:

| App | Blueprint | Published as |
| --- | --- | --- |
| `Northwind.WebService` | `platform/helm-web-service` | `apps/order-api`, `apps/checkout-bff`, `apps/cart-service` |
| `Northwind.Worker` | `platform/helm-worker` | `apps/order-event-publisher` |

**A repository per component, and none per archetype.** A platform records an artifact as its bytes in one
repository, so two components cannot share one image. Each archetype is built once and that one build is pushed
into the repository of every component it serves, under `ghcr.io/lembosproj/northwind/` — one index, so the digest
is the same in each. Nothing deploys an archetype by its own name, so nothing is published under it.

## Publishing

Tag `apps/v{version}` and push the tag. `.github/workflows/apps.yml` builds both archetypes for `linux/amd64` and
`linux/arm64` and tags every component's image `{version}` and `sha-{commit}`; the run summary lists the digest the
seed pins.

`Northwind.Runtime` is the library both share.

That is the point rather than a shortcut. A platform does not care what a workload computes; it cares
which blueprint built it, which spec version it is running, and whether what is running matches what was
asked for.

## Why these report their own identity

Every app reads `LEMBOS_COMPONENT`, `LEMBOS_ENVIRONMENT`, `LEMBOS_STAMP` and `LEMBOS_SPEC_VERSION` from
its environment and reports them back — the web service on `/identity`, the others in structured logs.

**This is what makes drift observable.** `RuntimeInstance` records a desired state and an observed one,
and the gap between them is the platform's actual work. Without a workload that reports which spec
version it is actually running, observed state can only ever be inferred from the fact that a pod
exists — which cannot tell a successful deployment from a stale one that was never replaced.

`/readyz` fails while a resource binding says nowhere to connect, so an instance that was never wired reports
unready rather than ready. Health and drift are different axes, and this is the app half of keeping them apart.

## Dependencies

A component's dependencies arrive as environment variables the charts render from its spec, which reads them from
what each dependency published where the component runs. A workload never receives a credential as a value.

| Variable | What it is |
| --- | --- |
| `<HANDLE>_ENDPOINT` | where a resource it depends on is reached, `host:port` |
| `<HANDLE>_SECRET_REF` | the path its credential lives at, to resolve at start-up |
| `<HANDLE>_URL` | the connection string, from a Kubernetes secret — only where a provisioner placed one |
| `UPSTREAM_<NAME>` | a component it calls, as a URL |

`/readyz` fails while a binding says nowhere to connect — wired, not reachable. Whether each dependency answers now
is `/dependencies` on the web service, and a log line about once a minute on the worker: an upstream's `/healthz`,
a resource's endpoint by opening a connection. A dependency being down is reported there and never fails readiness,
which would take a healthy workload out of service and hide which dependency was broken.
