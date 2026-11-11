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
    /// On by default. Nothing that names a person leaves the machine:
    /// - Username and Hostname are sent as a code of 8 hex characters each, the same two codes
    ///   DeviceId is made of: "mario.rossi@PC01" becomes "a1b2c3d4@0f1e2d3c";
    /// - in the executable path, the working directory and the command line, a folder that belongs to
    ///   the user (USERPROFILE, APPDATA, LOCALAPPDATA, TEMP; HOME elsewhere) is replaced by its name
    ///   between square brackets: "[USERPROFILE]\app\app.exe";
    /// - local IP addresses and volume names are not sent;
    /// - the same folders are replaced in the message and the stack trace of the exceptions the SDK reports.
    /// A code is HMAC-SHA256 of the name with a key the SDK never sends (the machine id of the
    /// operating system or, where there is none, a random value kept in a file on the machine), so the
    /// same user on the same machine gives the same code as long as that key is there, and whoever
    /// has only the code cannot go back to the name, not even by trying names. Names of other people inside
    /// command line arguments and the text of your own log messages are not touched. Set to false to
    /// send everything as it is.
    /// </summary>
    public bool AnonymizeDeviceId { get; set; } = true;

    public ExeWatchConfig()
    {
    }

    public ExeWatchConfig(string apiKey, string customerId)
    {
        ApiKey = apiKey;
        CustomerId = customerId;
    }
}
