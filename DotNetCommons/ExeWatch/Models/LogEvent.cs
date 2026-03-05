namespace ExeWatch.Models;

internal sealed class LogEvent
{
    public LogLevel Level { get; set; }
    public string Message { get; set; } = "";
    public string Tag { get; set; } = "main";
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public long ThreadId { get; set; }
    public int ProcessId { get; set; }
    public string SessionId { get; set; } = "";
    public Dictionary<string, object>? ExtraData { get; set; }
}
