namespace ExeWatch.Models;

internal sealed class MonitorInfo
{
    public int Index { get; set; }
    public string Name { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public int BitsPerPixel { get; set; }
    public bool Primary { get; set; }
}
