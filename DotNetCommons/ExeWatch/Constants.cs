namespace ExeWatch;

public static class Constants
{
    // Version
    public const string SdkVersion = "0.4.0";
    public const string SdkPlatform = "dotnet";
    public const string ApiVersion = "v1";

    public const string DefaultEndpoint = "https://exewatch.com";

    // Buffer & Transmission
    public const int DefaultBufferSize = 100;
    public const int DefaultFlushIntervalMs = 5000;
    public const int DefaultRetryIntervalMs = 30000;
    public const double DefaultSampleRate = 1.0;

    // File Extensions
    public const string LogFileExtension = ".ewlog";
    public const string DeviceFileExtension = ".ewdevice";
    public const string MetricFileExtension = ".ewmetric";
    public const string SendingExtension = ".sending";

    // Limits
    public const int MaxBreadcrumbs = 20;
    public const int MaxPendingTimings = 100;
    public const int MaxRegisteredGauges = 20;
    public const int DefaultMaxPendingAgeDays = 7;

    // Metrics
    public const int DefaultGaugeSamplingIntervalSec = 30;
    public const int MinGaugeSamplingIntervalSec = 10;
    public const int MetricFlushIntervalMs = 30000;

    // Internal Logging
    public const string InternalLogFile = "exewatch_sdk.log";
    public const int InternalLogMaxLines = 1000;
    public const int InternalLogMaxAgeDays = 7;
    public const string ApiTraceFile = "exewatch_api_trace.log";
    public const long ApiTraceMaxSize = 10 * 1024 * 1024; // 10 MB
    public const int ApiTraceMaxAgeHours = 12;
    public const int ApiTraceCheckInterval = 100;

    // Default message length
    public const int DefaultMaxMessageLength = 50000;

    // Valid API key prefixes
    public static readonly string[] ValidApiKeyPrefixes =
    [
        "ew_win_", "ew_lin_", "ew_mac_", "ew_and_", "ew_ios_", "ew_desk_"
    ];

    // Rejected API key prefixes
    public static readonly string[] RejectedApiKeyPrefixes = ["ew_web_"];
}
