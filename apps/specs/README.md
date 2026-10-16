# Northwind API contracts

One directory per API in the Lembos sample catalog, one file per published `ApiSpecVersion`, named for
its version tag. The path is the API's qualified name, so `ordering/orders-api` version `3.2.0` is
`specs/ordering/orders-api/3.2.0.yaml`.

| API | Type | Versions |
| --- | --- | --- |
| `ordering/orders-api` | OpenAPI | 3.1.0, 3.2.0 |
| `ordering/order-events` | AsyncAPI | 2.0.0 |
| `checkout/checkout-api` | OpenAPI | 1.8.0 |

**`orders-api` carries two versions on purpose.** An `Api` whose whole history is one version cannot
demonstrate the thing the model exists for — a consumer integrated against 3.1.0 needs to see what it
agreed to after 3.2.0 lands. 3.2.0 adds `cancellationReason` and deprecates `Order.notes`; the diff is
small and visible, which is what makes it useful as a fixture.

## How these reach the platform

A seeded `ApiSpecVersion` carries the document's **`Url`** rather than its content, so the catalogue names
where the contract is kept instead of holding a second copy that drifts from the first:
`https://raw.githubusercontent.com/lembosproj/northwind/refs/heads/main/apps/specs/{api}/{version}.{ext}`

`raw.githubusercontent.com` serves `Access-Control-Allow-Origin: *`, which the browser-side explorer
needs; a spec host without it renders an empty frame while the URL is perfectly correct.
