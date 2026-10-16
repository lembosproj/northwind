namespace Northwind.Runtime;

/// <summary>A component this workload calls, by the name its spec gave it.</summary>
/// <param name="Name">As its variable spells it — <c>ORDER_API</c> for <c>UPSTREAM_ORDER_API</c>.</param>
/// <param name="Url">Where it is called: the called component's host as the platform resolved it, over HTTP.</param>
public sealed record Upstream(string Name, Uri Url);

public static class Upstreams
{
    /// <summary>What every upstream's variable starts with, which is what keeps it apart from a resource binding.</summary>
    public const string Prefix = "UPSTREAM_";

    /// <summary>Every upstream the environment names. One whose value is not a URL is left out and logged by the caller.</summary>
    public static IReadOnlyList<Upstream> FromEnvironment() =>
    [
        .. System.Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .Select(entry => (Key: entry.Key.ToString() ?? string.Empty, Value: entry.Value?.ToString()))
            .Where(entry => entry.Key.StartsWith(Prefix, StringComparison.Ordinal) && entry.Key.Length > Prefix.Length)
            .Select(entry => Uri.TryCreate(entry.Value, UriKind.Absolute, out var url)
                ? new Upstream(entry.Key[Prefix.Length..], url)
                : null)
            .OfType<Upstream>()
            .OrderBy(upstream => upstream.Name, StringComparer.Ordinal)
    ];
}
