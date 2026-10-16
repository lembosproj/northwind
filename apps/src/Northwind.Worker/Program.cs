using Northwind.Runtime;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddHostedService<ConsumerService>();
builder.Build().Run();

/// <summary>
/// Stands in for any queue or stream consumer. It consumes nothing; what it demonstrates is the
/// shape — identity reported on start, its dependencies asked whether they answer, work logged on a loop,
/// and a shutdown that finishes the message in flight rather than dropping it.
/// </summary>
internal sealed class ConsumerService(ILogger<ConsumerService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(15);

    /// <summary>How many polls between asking the dependencies again — about once a minute.</summary>
    private const int ProbeEvery = 4;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var identity = WorkloadIdentity.FromEnvironment();
        var bindings = ResourceBindings.FromEnvironment();
        var upstreams = Upstreams.FromEnvironment();

        logger.LogInformation("Consumer {Identity} started with {Bindings} binding(s) and {Upstreams} upstream(s).",
            identity, bindings.Count, upstreams.Count);

        foreach (var binding in bindings.Where(binding => !binding.IsConfigured))
            logger.LogWarning("Binding {Handle} says nowhere to connect; work needing it will fail.", binding.Handle);

        using var http = new HttpClient();
        var probe = new DependencyProbe(http);
        var polls = 0;

        while (!stoppingToken.IsCancellationRequested)
        {
            if (polls++ % ProbeEvery == 0)
                await ReportDependenciesAsync(probe, upstreams, bindings, stoppingToken);

            logger.LogInformation("Polled. component={Component} spec={SpecVersion} stamp={Stamp}",
                identity.Component, identity.SpecVersion, identity.Stamp);

            try
            {
                await Task.Delay(Interval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                // Shutdown, not a fault. Falling through lets the loop condition end it cleanly.
            }
        }

        logger.LogInformation("Consumer {Identity} stopped.", identity);
    }

    /// <summary>Each dependency's answer, in the log — a worker has no endpoint to be asked on.</summary>
    private async Task ReportDependenciesAsync(
        DependencyProbe probe, IReadOnlyList<Upstream> upstreams, IReadOnlyList<ResourceBinding> bindings, CancellationToken ct)
    {
        try
        {
            foreach (var check in await probe.CheckAsync(upstreams, bindings, ct))
            {
                if (check.Reachable)
                    logger.LogInformation("Dependency {Kind} {Name} at {Target} answered in {Milliseconds} ms.",
                        check.Kind, check.Name, check.Target, check.Milliseconds);
                else
                    logger.LogWarning("Dependency {Kind} {Name} at {Target} did not answer: {Problem}.",
                        check.Kind, check.Name, check.Target, check.Problem);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // Shutting down while asking; nothing to report.
        }
    }
}
