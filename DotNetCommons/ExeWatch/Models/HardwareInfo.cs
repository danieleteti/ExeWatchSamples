namespace ExeWatch.Models;

internal sealed class HardwareInfo
{
    public long TotalPhysicalMemory { get; set; }
    public long AvailablePhysicalMemory { get; set; }
    public string CpuName { get; set; } = "";
    public int CpuCores { get; set; }
    public int CpuLogicalProcessors { get; set; }
    public string CpuArchitecture { get; set; } = "";
    public List<DiskInfo> Disks { get; set; } = [];
    public List<MonitorInfo> Monitors { get; set; } = [];
    public string ExecutablePath { get; set; } = "";
    public string WorkingDirectory { get; set; } = "";
    public string CommandLine { get; set; } = "";
    public DateTime? SystemBootTime { get; set; }
    public List<string> LocalIpAddresses { get; set; } = [];
    public string Timezone { get; set; } = "";
    public string SystemLanguage { get; set; } = "";
    public string SystemLocale { get; set; } = "";
    public string RuntimeVersion { get; set; } = "";
    public AppVersionInfo? AppVersionInfo { get; set; }
    public Dictionary<string, object> Extra { get; set; } = [];
}
