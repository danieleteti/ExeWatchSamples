using System.Diagnostics;

namespace ExeWatch.Models;

internal sealed class TimingEntry
{
    public long StartTicks { get; set; } = Stopwatch.GetTimestamp();
    public string Tag { get; set; } = "";
    public Dictionary<string, object>? Metadata { get; set; }
}
