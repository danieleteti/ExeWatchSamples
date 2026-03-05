namespace ExeWatch.Models;

internal sealed class DeviceInfo
{
    public string DeviceId { get; set; } = "";
    public string Hostname { get; set; } = "";
    public string Username { get; set; } = "";
    public string OsType { get; set; } = "windows";
    public string OsVersion { get; set; } = "";
    public string AppBinaryVersion { get; set; } = "";
    public string AppVersion { get; set; } = "";
    public string SdkVersion { get; set; } = Constants.SdkVersion;
    public string TimezoneOffset { get; set; } = "";
}
