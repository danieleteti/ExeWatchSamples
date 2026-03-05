namespace ExeWatch.Config;

internal sealed class ServerConfig
{
    public int Version { get; set; }
    public int FlushIntervalMs { get; set; } = Constants.DefaultFlushIntervalMs;
    public int BatchSize { get; set; } = Constants.DefaultBufferSize;
    public double SamplingRate { get; set; } = Constants.DefaultSampleRate;
    public int MaxMessageLength { get; set; } = Constants.DefaultMaxMessageLength;
    public LogLevel MinLevel { get; set; } = LogLevel.Debug;
    public bool Enabled { get; set; } = true;
}
