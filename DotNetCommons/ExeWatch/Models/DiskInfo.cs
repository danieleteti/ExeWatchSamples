namespace ExeWatch.Models;

internal sealed class DiskInfo
{
    public string Drive { get; set; } = "";
    public string VolumeName { get; set; } = "";
    public string FileSystem { get; set; } = "";
    public long TotalBytes { get; set; }
    public long FreeBytes { get; set; }
    public string DriveType { get; set; } = "";
}
