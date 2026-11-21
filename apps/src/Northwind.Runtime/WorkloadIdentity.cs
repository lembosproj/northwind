namespace Northwind.Runtime;

/// <summary>
/// Who this process is, in the platform's terms, read from the environment the deployment set.
/// </summary>
/// <remarks>
/// Declared once and shared by every archetype, so a log line or a request names the placement that
/// answered it in the same words whichever chart deployed the workload.
/// </remarks>
public sealed record WorkloadIdentity(
    string Component,
    string Environment,
    string Slot)
{
    /// <summary>Reads the identity a Lembos deployment injects. Unset values read as "unknown".</summary>
    /// <remarks>
    /// Unknown rather than empty or a throw: a workload started outside the platform — on a laptop, in a
    /// test — is a legitimate way to run these, and one that refused to start without a slot would make
    /// the archetypes hard to debug.
    /// </remarks>
    public static WorkloadIdentity FromEnvironment() => new(
        Read("LEMBOS_COMPONENT"),
        Read("LEMBOS_ENVIRONMENT"),
        Read("LEMBOS_SLOT"));

    private static string Read(string key)
    {
        var value = System.Environment.GetEnvironmentVariable(key);
        return string.IsNullOrWhiteSpace(value) ? "unknown" : value;
    }

    public override string ToString() =>
        $"{Component} in {Environment}/{Slot}";
}
