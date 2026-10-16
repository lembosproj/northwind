namespace Northwind.Runtime;

/// <summary>
/// Who this process is, in the platform's terms, read from the environment the deployment set.
/// </summary>
/// <remarks>
/// Declared once and shared by all three container archetypes, because the Execution Agent reads
/// observed state the same way whichever blueprint produced the workload. Spelled per app they would
/// drift, and a stamp reported under two different keys is a runtime instance that cannot be matched
/// to the one that was asked for.
/// </remarks>
public sealed record WorkloadIdentity(
    string Component,
    string Environment,
    string Stamp,
    string SpecVersion)
{
    /// <summary>Reads the identity a Lembos deployment injects. Unset values read as "unknown".</summary>
    /// <remarks>
    /// Unknown rather than empty or a throw: a workload started outside the platform — on a laptop, in a
    /// test — is a legitimate way to run these, and one that refused to start without a stamp would make
    /// the archetypes undebuggable. Reporting "unknown" is also the honest observed state, and it will
    /// not match any desired state, so the instance shows as drifted rather than as agreeing by accident.
    /// </remarks>
    public static WorkloadIdentity FromEnvironment() => new(
        Read("LEMBOS_COMPONENT"),
        Read("LEMBOS_ENVIRONMENT"),
        Read("LEMBOS_STAMP"),
        Read("LEMBOS_SPEC_VERSION"));

    private static string Read(string key)
    {
        var value = System.Environment.GetEnvironmentVariable(key);
        return string.IsNullOrWhiteSpace(value) ? "unknown" : value;
    }

    public override string ToString() =>
        $"{Component}@{SpecVersion} in {Environment}/{Stamp}";
}
