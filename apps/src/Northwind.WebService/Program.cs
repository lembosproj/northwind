using Northwind.Runtime;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient<DependencyProbe>();
var app = builder.Build();

var identity = WorkloadIdentity.FromEnvironment();
var bindings = ResourceBindings.FromEnvironment();
var upstreams = Upstreams.FromEnvironment();

app.Logger.LogInformation("Starting {Identity} with {Bindings} resource binding(s) and {Upstreams} upstream(s).",
    identity, bindings.Count, upstreams.Count);

// Liveness is about the process, readiness is about its dependencies, and conflating them is how a
// workload with an unreachable database gets restarted forever instead of reported unhealthy.
app.MapGet("/healthz", () => Results.Ok(new { status = "alive" }));

// Ready once every binding says where its resource is — wired, not reachable: a dependency being down is
// reported on /dependencies, and taking this pod out of service for it would hide which one was broken.
app.MapGet("/readyz", () =>
{
    var unconfigured = bindings.Where(binding => !binding.IsConfigured).Select(binding => binding.Handle).ToArray();

    return unconfigured.Length == 0
        ? Results.Ok(new { status = "ready" })
        : Results.Json(new { status = "unready", unconfigured }, statusCode: 503);
});

// What the platform reads to learn observed state. Reporting the spec version is the whole point:
// a pod that exists proves something is running, not that the right thing is.
app.MapGet("/identity", () => Results.Ok(new
{
    identity.Component,
    identity.Environment,
    identity.Stamp,
    identity.SpecVersion,
    Bindings = bindings.Select(ResourceBindings.Describe),
    Upstreams = upstreams.Select(upstream => new { upstream.Name, Url = upstream.Url.ToString() })
}));

// Whether what this depends on answers now, asked from inside the workload — the wiring seen working end to end.
app.MapGet("/dependencies", async (DependencyProbe probe, CancellationToken ct) =>
{
    var checks = await probe.CheckAsync(upstreams, bindings, ct);

    return Results.Ok(new
    {
        identity.Component,
        Reachable = checks.All(check => check.Reachable),
        Checks = checks
    });
});

app.MapGet("/", () => Results.Ok(new { service = identity.Component, version = identity.SpecVersion }));

app.Run();
