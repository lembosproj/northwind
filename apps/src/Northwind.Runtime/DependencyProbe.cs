using System.Diagnostics;
using System.Net.Sockets;

namespace Northwind.Runtime;

/// <summary>Whether one dependency answered, how fast, and why not.</summary>
/// <param name="Kind"><c>upstream</c> or <c>resource</c>.</param>
/// <param name="Target">What was asked: the upstream's URL, or the resource's endpoint. Never a credential.</param>
public sealed record DependencyCheck(string Kind, string Name, string? Target, bool Reachable, long? Milliseconds, string? Problem);

/// <summary>
/// Asks each dependency whether it is there: an upstream's <c>/healthz</c>, a resource's endpoint by opening a
/// connection to it.
/// </summary>
/// <remarks>
/// <b>What this is for.</b> A component's dependencies are wired by the platform — a resource's endpoint and secret
/// path, an upstream's host, each read from what that dependency published where this runs. Probing them is how the
/// wiring is seen working end to end, from inside the workload, rather than inferred from a value having arrived.
/// <para>
/// Informational, never readiness: a dependency being down is a fact about the dependency, and failing this pod's
/// readiness for it would take a healthy workload out of service and hide which one was broken.
/// </para>
/// </remarks>
public sealed class DependencyProbe(HttpClient http)
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(2);

    public async Task<IReadOnlyList<DependencyCheck>> CheckAsync(
        IEnumerable<Upstream> upstreams, IEnumerable<ResourceBinding> bindings, CancellationToken ct)
    {
        var checks = upstreams.Select(upstream => CheckUpstreamAsync(upstream, ct))
            .Concat(bindings.Select(binding => CheckResourceAsync(binding, ct)));

        return await Task.WhenAll(checks);
    }

    private async Task<DependencyCheck> CheckUpstreamAsync(Upstream upstream, CancellationToken ct)
    {
        var url = new Uri(upstream.Url, "/healthz");
        var clock = Stopwatch.StartNew();

        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(Timeout);

            using var response = await http.GetAsync(url, timeout.Token);

            return new DependencyCheck("upstream", upstream.Name, upstream.Url.ToString(), response.IsSuccessStatusCode,
                clock.ElapsedMilliseconds, response.IsSuccessStatusCode ? null : $"answered {(int)response.StatusCode}");
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException)
        {
            return new DependencyCheck("upstream", upstream.Name, upstream.Url.ToString(), false, null,
                error is OperationCanceledException ? "no answer in time" : error.Message);
        }
    }

    private static async Task<DependencyCheck> CheckResourceAsync(ResourceBinding binding, CancellationToken ct)
    {
        if (binding.Endpoint is not { } endpoint || !TrySplit(endpoint, out var host, out var port))
        {
            return new DependencyCheck("resource", binding.Handle, binding.Endpoint, false, null,
                binding.Endpoint is null ? "no endpoint was given" : "the endpoint is not host:port");
        }

        var clock = Stopwatch.StartNew();

        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(Timeout);

            using var socket = new TcpClient();
            await socket.ConnectAsync(host, port, timeout.Token);

            return new DependencyCheck("resource", binding.Handle, endpoint, true, clock.ElapsedMilliseconds, null);
        }
        catch (Exception error) when (error is SocketException or OperationCanceledException)
        {
            return new DependencyCheck("resource", binding.Handle, endpoint, false, null,
                error is OperationCanceledException ? "no answer in time" : error.Message);
        }
    }

    private static bool TrySplit(string endpoint, out string host, out int port)
    {
        var colon = endpoint.LastIndexOf(':');
        host = colon > 0 ? endpoint[..colon] : string.Empty;
        port = 0;

        return colon > 0 && int.TryParse(endpoint[(colon + 1)..], out port) && port is > 0 and <= 65535;
    }
}
