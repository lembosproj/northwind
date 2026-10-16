# Northwind Charts

The Helm blueprints the Lembos sample organisation is built from. Two charts, matching the two
`BlueprintProvisionerType.Helm` entries the Orchestrator seeds:

| Chart | Blueprint | Version | Type |
| --- | --- | --- | --- |
| `web-service` | `platform/helm-web-service` | 2.6.0 | Component |
| `worker` | `platform/helm-worker` | 1.10.0 | Component |

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
  stamp: eu-west
  specVersion: "1.4.0"
image:
  repository: ghcr.io/lembosproj/northwind/apps/order-api
  digest: ""            # pinned artifact digest; wins over tag when set
  tag: latest
replicas: 2             # the spec's
ports:                  # the spec's
  - { name: http, port: 8080, protocol: http, isPublic: true }
resourceBindings:       # one per resource the component depends on, keyed by a handle
  ordersDb:
    endpoint: northwind-prod-eu-west-ordering-orders-db.local:5432
    secretRef: northwind/prod/eu-west/ordering/orders-db
upstreams:              # one per component it calls: a host (called over HTTP on 80) or a URL
  orderApi: ordering-order-api-eu-west.northwind-prod-eu-west.svc.cluster.local
config: {}              # the spec's settings, as environment variables
sizeClass: small        # drives requests/limits; defaults to the destination's tier
```

`resourceBindings` carries a **secret reference, never a secret value** — the path a workload resolves at
start-up. A chart that took a password as a value would put it in the release's stored manifest.

Both are filled from what a component **depends on**: a spec answers each binding from its resource's `endpoint` and
`secret_ref` outputs, and each upstream from the called component's `clusterEndpoint` — the platform reads them where
the component runs. The charts render them the same way:

| Value | Environment variable |
| --- | --- |
| `resourceBindings.<handle>.endpoint` | `<HANDLE>_ENDPOINT` |
| `resourceBindings.<handle>.secretRef` | `<HANDLE>_SECRET_REF`, and `<HANDLE>_URL` from the secret of that name, when present |
| `upstreams.<name>` | `UPSTREAM_<NAME>` — a host is prefixed `http://` |

A handle and a name are camelCase (`ordersDb`, `orderApi`) and become SCREAMING_SNAKE (`ORDERS_DB`, `ORDER_API`).
A web service's Service answers callers on port 80, at its first public port, so a caller needs only the host.

## How Lembos resolves these

From **the OCI registry**. A seeded `BlueprintVersion` points at the chart's package and a version, and pins the
manifest digest the push produced:

```text
location   oci://ghcr.io/lembosproj/northwind/charts
package    web-service
reference  2.6.0
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
git tag charts/web-service/v2.6.0 && git push origin charts/web-service/v2.6.0
```
