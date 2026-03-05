namespace ExeWatch.Models;

public sealed class Breadcrumb
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public BreadcrumbType Type { get; set; } = BreadcrumbType.Custom;
    public string Category { get; set; } = "custom";
    public string Message { get; set; } = "";
    public Dictionary<string, object>? Data { get; set; }
}
