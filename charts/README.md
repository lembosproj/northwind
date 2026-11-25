# Northwind Charts

The Helm blueprints the Lembos sample organisation's components are built from, one per
`BlueprintProvisionerType.Helm` entry the Orchestrator seeds. The same two on every cloud: what differs between AWS and
Azure is what the slot gives them (`identity` below), not the chart. Where they run is built by the Terraform modules in
[../modules](../modules/README.md).

| Chart | Blueprint | Version | Type |
| --- | --- | --- | --- |
| `service` | `kubernetes/service` | 1.0.3 | Component |
| `worker` | `kubernetes/worker` | 1.0.3 | Component |

The chart is named for what it deploys and the blueprint for how: `helm-` says which provisioner a blueprint uses,
which is the catalog's question, and is noise in a registry that only holds charts.

**Chart versions are load-bearing.** They are the `VersionTag` the seeded BlueprintVersion pins, and the
coordinate a deployment resolves. Changing one here without changing the seed makes a published version
unresolvable — which is a real state the platform models, but not one to reach by accident.

## The values contract

The component charts take the **same** values shape, because Lembos renders it from a
spec version and does not know which chart it is feeding:

```yaml
lembos:                 # who this is, resolved by the deployment workflow
  component: ordering/order-api
  environment: northwind/prod
  slot: eu-west
image:
  repository: ghcr.io/lembosproj/northwind/apps/order-api
  digest: ""            # pinned artifact digest; wins over tag when set
  tag: latest
replicas: 2             # the spec's
ports:                  # the spec's
  - { name: http, port: 8080, protocol: http, isPublic: true }
resourceBindings:       # one per resource the component depends on, keyed by a handle
  ordersDb:
    endpoint: northwind-prod-eu-west-ordering-orders-db.local
    port: 5432
    secretRef: northwind/prod/eu-west/ordering/orders-db
upstreams:              # one per component it calls: a host (called over HTTP on 80) or a URL
  orderApi: ordering-order-api-eu-west.northwind-prod-eu-west.svc.cluster.local
config: {}              # the spec's settings, as environment variables
sizeClass: small        # drives requests/limits; defaults to the destination's tier
```

`resourceBindings` carries a **secret reference, never a secret value** — the path a workload resolves at
start-up. A chart that took a password as a value would put it in the release's stored manifest.

Both are filled from what a component **depends on**: a spec answers each binding from its resource's `endpoint`,
`port` and `secret_ref` outputs, and each upstream from the called component's `clusterEndpoint` — the platform reads them where
the component runs. The charts render them the same way:

| Value | Environment variable |
| --- | --- |
| `resourceBindings.<handle>.endpoint` | `<HANDLE>_ENDPOINT`, as `host:port` where the endpoint is a bare host and a port is given |
| `resourceBindings.<handle>.port` | `<HANDLE>_PORT` |
| `resourceBindings.<handle>.secretRef` | `<HANDLE>_SECRET_REF`, and `<HANDLE>_URL` from the secret of that name, when present |
| `upstreams.<name>` | `UPSTREAM_<NAME>` — a host is prefixed `http://` |

`values.schema.json` declares every value, with its type: it is what a blueprint version imports as its inputs, so
what the schema leaves out would be guessed from `values.yaml`, and an enum such as `sizeClass` would be lost. Helm
checks every render against it, so a value outside it is refused before anything is applied.

A handle and a name are camelCase (`ordersDb`, `orderApi`) and become SCREAMING_SNAKE (`ORDERS_DB`, `ORDER_API`).
A service's Service answers callers on port 80, at its first public port, so a caller needs only the host.

## Who the pods sign in as

The component charts take one more value, `identity`, which a blueprint answers from the slot it deploys into. Empty,
the chart makes a service account of its own and the pods sign in as nothing, which is every slot with no cloud
identity behind it: the local cluster and the emulators.

| Value | What it does |
| --- | --- |
| `identity.serviceAccount` | Runs as the slot's service account (`workload`, which each namespace module makes) |
| `identity.azure.clientId`, `tenantId` | Signs the pods in through Azure workload identity, as the slot's identity |
| `identity.azure.keyVault` | With `clientId`: a `SecretProviderClass` copies each binding's secret from the vault into the Secret `<HANDLE>_URL` is read from, through AKS's Key Vault provider. The pods mount it at `SECRETS_DIRECTORY`, where the app reads a URL the Secret does not have yet |

So on Azure a workload connects with the same variables as anywhere else, and its connection string never passes
through the platform or the release's values.

## How Lembos resolves these

From **the OCI registry**. A seeded `BlueprintVersion` points at the chart's package and a version, and pins the
manifest digest the push produced:

```text
location   oci://ghcr.io/lembosproj/northwind/charts
package    service
reference  1.0.1
digest     sha256:…
```

The worker resolves the reference to a manifest digest before downloading anything, so a version whose tag was
pushed again reports a digest mismatch rather than quietly running different bytes. **Never re-push a published
version** — cut a new one.

## Publishing

Tag `charts/{chart}/v{version}` and push the tag. `.github/workflows/charts.yml` packages the chart at the tag's
version — not `Chart.yaml`'s, so a deprecated line or a release candidate cut from an older commit carries the number
its tag says — and pushes it with Helm 3.16.2, the tool version the blueprints declare. The run summary lists the
digest the seed pins.

```shell
git tag charts/service/v1.0.1 && git push origin charts/service/v1.0.1
```
