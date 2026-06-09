using System.Diagnostics;

namespace ExeWatch.Models;

internal sealed class TimingEntry
{
    public long StartTicks { get; set; } = Stopwatch.GetTimestamp();
    public string Tag { get; set; } = "";
    public Dictionary<string, object>? Metadata { get; set; }

    // Nested timing traces — filled only for spans inside an active StartTrace.
    // ParentSpanId "" marks the root (the backend maps it to NULL).
    public string SpanId { get; set; } = "";
    public string TraceId { get; set; } = "";
    public string ParentSpanId { get; set; } = "";
}
