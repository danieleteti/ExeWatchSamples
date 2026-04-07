namespace ExeWatch.Config;

public sealed class ExeWatchConfig
{
    public string ApiKey { get; set; } = "";
    public string CustomerId { get; set; } = "";
    internal string Endpoint { get; set; } = Constants.DefaultEndpoint;
    public int BufferSize { get; set; } = Constants.DefaultBufferSize;
    public int FlushIntervalMs { get; set; } = Constants.DefaultFlushIntervalMs;
    public int RetryIntervalMs { get; set; } = Constants.DefaultRetryIntervalMs;
    public string StoragePath { get; set; } = "";
    public double SampleRate { get; set; } = Constants.DefaultSampleRate;
    public string AppVersion { get; set; } = "";
    public int GaugeSamplingIntervalSec { get; set; } = Constants.DefaultGaugeSamplingIntervalSec;
    public int MaxPendingAgeDays { get; set; } = Constants.DefaultMaxPendingAgeDays;
    public List<KeyValuePair<string, string>> InitialCustomDeviceInfo { get; set; } = [];

    /// <summary>
    /// When true, the username portion of DeviceId is replaced with its SHA-1 hash.
    /// e.g., "mario.rossi@PC01" becomes "a1b2c3d4...@PC01".
    /// Useful for GDPR compliance in Active Directory environments.
    /// </summary>
    public bool AnonymizeDeviceId { get; set; }

    public ExeWatchConfig()
    {
    }

    public ExeWatchConfig(string apiKey, string customerId)
    {
        ApiKey = apiKey;
        CustomerId = customerId;
    }
}
