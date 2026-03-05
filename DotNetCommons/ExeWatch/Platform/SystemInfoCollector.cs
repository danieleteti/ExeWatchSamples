using System.Diagnostics;
using System.Runtime.InteropServices;
using ExeWatch.Models;
using Microsoft.Win32;

namespace ExeWatch.Platform;

internal static class SystemInfoCollector
{
    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    public static HardwareInfo Collect()
    {
        var info = new HardwareInfo
        {
            CpuArchitecture = PlatformHelper.GetCpuArchitecture(),
            ExecutablePath = PlatformHelper.GetExecutablePath(),
            WorkingDirectory = PlatformHelper.GetWorkingDirectory(),
            CommandLine = PlatformHelper.GetCommandLine(),
            LocalIpAddresses = PlatformHelper.GetLocalIpAddresses(),
            Timezone = PlatformHelper.GetTimezoneName(),
            SystemLanguage = PlatformHelper.GetSystemLanguage(),
            SystemLocale = PlatformHelper.GetSystemLocale(),
            RuntimeVersion = PlatformHelper.GetRuntimeVersion(),
            CpuLogicalProcessors = Environment.ProcessorCount
        };

        CollectMemory(info);
        CollectCpu(info);
        CollectDisks(info);
        CollectMonitors(info);
        CollectBootTime(info);
        CollectAppVersionInfo(info);

        return info;
    }

    private static void CollectMemory(HardwareInfo info)
    {
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                var memStatus = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
                if (GlobalMemoryStatusEx(ref memStatus))
                {
                    info.TotalPhysicalMemory = (long)memStatus.ullTotalPhys;
                    info.AvailablePhysicalMemory = (long)memStatus.ullAvailPhys;
                }
            }
        }
        catch { }
    }

    private static void CollectCpu(HardwareInfo info)
    {
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                using var key = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
                if (key != null)
                {
                    info.CpuName = key.GetValue("ProcessorNameString")?.ToString()?.Trim() ?? "";
                }

                // Count physical cores via registry
                int coreCount = 0;
                using var cpuKey = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor");
                if (cpuKey != null)
                    coreCount = cpuKey.GetSubKeyNames().Length;

                // Physical cores approximation: logical / 2 for hyperthreaded
                // But registry subkeys give us logical count too, so use Environment.ProcessorCount
                info.CpuCores = coreCount > 0 ? coreCount : Environment.ProcessorCount;
            }
        }
        catch { }
    }

    private static void CollectDisks(HardwareInfo info)
    {
        try
        {
            foreach (var drive in DriveInfo.GetDrives())
            {
                if (!drive.IsReady) continue;
                info.Disks.Add(new DiskInfo
                {
                    Drive = drive.Name.TrimEnd('\\'),
                    VolumeName = drive.VolumeLabel,
                    FileSystem = drive.DriveFormat,
                    TotalBytes = drive.TotalSize,
                    FreeBytes = drive.AvailableFreeSpace,
                    DriveType = drive.DriveType switch
                    {
                        System.IO.DriveType.Fixed => "Fixed",
                        System.IO.DriveType.Removable => "Removable",
                        System.IO.DriveType.Network => "Network",
                        System.IO.DriveType.CDRom => "CDRom",
                        System.IO.DriveType.Ram => "RamDisk",
                        _ => "Unknown"
                    }
                });
            }
        }
        catch { }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    private const uint MONITORINFOF_PRIMARY = 1;

    private static void CollectMonitors(HardwareInfo info)
    {
        try
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return;

            int index = 0;
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
            {
                var mi = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
                if (GetMonitorInfo(hMonitor, ref mi))
                {
                    info.Monitors.Add(new MonitorInfo
                    {
                        Index = index,
                        Name = mi.szDevice,
                        Width = mi.rcMonitor.Right - mi.rcMonitor.Left,
                        Height = mi.rcMonitor.Bottom - mi.rcMonitor.Top,
                        BitsPerPixel = 0, // not available via EnumDisplayMonitors
                        Primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0
                    });
                }
                index++;
                return true;
            }, IntPtr.Zero);
        }
        catch { }
    }

    private static void CollectBootTime(HardwareInfo info)
    {
        try
        {
            var uptime = TimeSpan.FromMilliseconds(Environment.TickCount64);
            info.SystemBootTime = DateTime.UtcNow - uptime;
        }
        catch { }
    }

    private static void CollectAppVersionInfo(HardwareInfo info)
    {
        try
        {
            var exePath = PlatformHelper.GetExecutablePath();
            if (!string.IsNullOrEmpty(exePath) && File.Exists(exePath))
            {
                var fvi = FileVersionInfo.GetVersionInfo(exePath);
                info.AppVersionInfo = new AppVersionInfo
                {
                    FileVersion = fvi.FileVersion ?? "",
                    ProductVersion = fvi.ProductVersion ?? "",
                    ProductName = fvi.ProductName ?? "",
                    CompanyName = fvi.CompanyName ?? "",
                    FileDescription = fvi.FileDescription ?? "",
                    InternalName = fvi.InternalName ?? "",
                    OriginalFilename = fvi.OriginalFilename ?? "",
                    LegalCopyright = fvi.LegalCopyright ?? ""
                };
            }
        }
        catch { }
    }

    public static string GetAppBinaryVersion()
    {
        try
        {
            var exePath = PlatformHelper.GetExecutablePath();
            if (!string.IsNullOrEmpty(exePath) && File.Exists(exePath))
            {
                var fvi = FileVersionInfo.GetVersionInfo(exePath);
                if (!string.IsNullOrEmpty(fvi.FileVersion))
                    return fvi.FileVersion;
                if (!string.IsNullOrEmpty(fvi.ProductVersion))
                    return fvi.ProductVersion;
            }
        }
        catch { }
        return "not available";
    }
}
