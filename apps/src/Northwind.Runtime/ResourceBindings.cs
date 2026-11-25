namespace Northwind.Runtime;

/// <summary>
/// The resources this workload was bound to, by the handle its spec declared.
/// </summary>
/// <param name="Handle">The spec's local name for the dependency, as its variables spell it — <c>ORDERS_DB</c>.</param>
/// <param name="Endpoint">Where the resource is reached, <c>host:port</c>, when the spec named it.</param>
/// <param name="Url">The connection string, when the platform mounted one from a secret.</param>
/// <param name="SecretRef">The path holding the credential, when the spec named it — never the credential.</param>
public sealed record ResourceBinding(string Handle, string? Endpoint, string? Url, string? SecretRef)
{
    /// <summary>
    /// Whether this binding says where its resource is. A secret path with nowhere to connect to is not enough.
    /// </summary>
    /// <remarks>
    /// An endpoint counts as well as a mounted URL: the URL comes from a Kubernetes secret only a provisioner that
    /// places one creates, and a binding that required it would leave every workload on the local emulator unready.
    /// </remarks>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Url) || !string.IsNullOrWhiteSpace(Endpoint);
}

public static class ResourceBindings
{
    private const string EndpointSuffix = "_ENDPOINT";
    private const string UrlSuffix = "_URL";
    private const string SecretRefSuffix = "_SECRET_REF";

    /// <summary>Where the chart mounts the slot's secrets, when the slot keeps them in a vault (the charts' identity).</summary>
    public const string SecretsDirectory = "SECRETS_DIRECTORY";

    /// <summary>
    /// Every binding the environment carries, from any of the three variables a binding renders.
    /// </summary>
    /// <remarks>
    /// The charts render a binding as <c>&lt;HANDLE&gt;_ENDPOINT</c> and <c>&lt;HANDLE&gt;_SECRET_REF</c>, and add
    /// <c>&lt;HANDLE&gt;_URL</c> from a secret where one was placed. The first two name a binding; a URL only joins one
    /// they named, because plenty of settings end in <c>_URL</c> and reading each as a database would report
    /// dependencies the workload does not have.
    /// <para>
    /// An upstream's variable starts with <c>UPSTREAM_</c> and is read by <see cref="Upstreams"/>, never here.
    /// </para>
    /// </remarks>
    public static IReadOnlyList<ResourceBinding> FromEnvironment()
    {
        var endpoints = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var urls = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var refs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (System.Collections.DictionaryEntry entry in System.Environment.GetEnvironmentVariables())
        {
            var key = entry.Key.ToString();
            var value = entry.Value?.ToString();
            if (key is null || string.IsNullOrWhiteSpace(value) || key.StartsWith(Upstreams.Prefix, StringComparison.Ordinal))
                continue;

            if (key.EndsWith(EndpointSuffix, StringComparison.Ordinal))
                endpoints[key[..^EndpointSuffix.Length]] = value;
            else if (key.EndsWith(SecretRefSuffix, StringComparison.Ordinal))
                refs[key[..^SecretRefSuffix.Length]] = value;
            else if (key.EndsWith(UrlSuffix, StringComparison.Ordinal))
                urls[key[..^UrlSuffix.Length]] = value;
        }

        return endpoints.Keys.Union(refs.Keys, StringComparer.OrdinalIgnoreCase)
            .OrderBy(handle => handle, StringComparer.OrdinalIgnoreCase)
            .Select(handle => new ResourceBinding(
                handle,
                endpoints.GetValueOrDefault(handle),
                urls.GetValueOrDefault(handle) ?? (refs.GetValueOrDefault(handle) is { } secretRef ? MountedUrl(secretRef) : null),
                refs.GetValueOrDefault(handle)))
            .ToList();
    }

    /// <summary>The URL a vault's provider wrote into the mounted volume for a binding's secret, if it did.</summary>
    /// <remarks>
    /// Where a slot keeps its secrets in a vault, the provider copies each one into the Secret <c>&lt;HANDLE&gt;_URL</c> is
    /// read from only while a pod mounts it. Environment variables are fixed when the container is made, so a pod that
    /// started before the copy existed would run without its URL until it restarted. The mounted file is there from the
    /// first start. It is named as the charts name the secret: the path, with dashes for its slashes, in lower case.
    /// </remarks>
    private static string? MountedUrl(string secretRef)
    {
        if (System.Environment.GetEnvironmentVariable(SecretsDirectory) is not { Length: > 0 } directory)
            return null;

        var path = Path.Combine(directory, secretRef.Replace('/', '-').ToLowerInvariant());

        try
        {
            return File.Exists(path) && File.ReadAllText(path).Trim() is { Length: > 0 } url ? url : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    /// A redacted view. The url is never reported — only that one arrived.
    /// </summary>
    /// <remarks>
    /// The identity endpoint exists to be read by anything that can reach the pod, so it must not become
    /// the one place a connection string with a password in it is served over plain HTTP.
    /// </remarks>
    public static object Describe(ResourceBinding binding) => new
    {
        binding.Handle,
        binding.IsConfigured,
        binding.Endpoint,
        binding.SecretRef,
        Url = string.IsNullOrWhiteSpace(binding.Url) ? null : "***"
    };
}
