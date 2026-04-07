using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace ExeWatch.Platform;

internal static class PlatformHelper
{
    public static string GetHostname()
    {
        try { return Environment.MachineName; }
        catch { return "unknown"; }
    }

    public static string GetUsername()
    {
        try { return Environment.UserName; }
        catch { return "unknown"; }
    }

    public static string GetDeviceId()
    {
        var hostname = GetHostname();
        var username = GetUsername();
        if (!string.IsNullOrEmpty(username) && !string.IsNullOrEmpty(hostname))
            return $"{username}@{hostname}";
        if (!string.IsNullOrEmpty(hostname))
            return hostname;
        return $"{username}@unknown";
    }

    public static string AnonymizeUsername(string username)
    {
        if (string.IsNullOrEmpty(username))
            return "anonymous";
        var bytes = System.Text.Encoding.UTF8.GetBytes(username);
        var hash = SHA1.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant()[..8];
    }

    public static string GetOsType()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return "windows";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return "linux";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return "macos";
        return "unknown";
    }

    public static string GetOsVersion()
    {
        try { return RuntimeInformation.OSDescription; }
        catch { return Environment.OSVersion.ToString(); }
    }

    public static string GetTimezoneOffset()
    {
        var offset = TimeZoneInfo.Local.GetUtcOffset(DateTime.UtcNow);
        var sign = offset >= TimeSpan.Zero ? "+" : "-";
        var abs = offset.Duration();
        return $"{sign}{abs.Hours:D2}:{abs.Minutes:D2}";
    }

    public static string GetTimezoneName()
    {
        try { return TimeZoneInfo.Local.StandardName; }
        catch { return ""; }
    }

    public static string GetCpuArchitecture()
    {
        return RuntimeInformation.OSArchitecture switch
        {
            Architecture.X64 => "x64",
            Architecture.X86 => "x86",
            Architecture.Arm64 => "ARM64",
            Architecture.Arm => "ARM",
            _ => RuntimeInformation.OSArchitecture.ToString()
        };
    }

    public static string GetSystemLanguage()
    {
        try { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName; }
        catch { return ""; }
    }

    public static string GetSystemLocale()
    {
        try { return CultureInfo.CurrentCulture.Name; }
        catch { return ""; }
    }

    public static string GetExecutablePath()
    {
        try { return Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName ?? ""; }
        catch { return ""; }
    }

    public static string GetWorkingDirectory()
    {
        try { return Environment.CurrentDirectory; }
        catch { return ""; }
    }

    public static string GetCommandLine()
    {
        try { return Environment.CommandLine; }
        catch { return ""; }
    }

    public static int GetCurrentProcessId()
    {
        try { return Environment.ProcessId; }
        catch { return 0; }
    }

    public static string GetRuntimeVersion()
    {
        return $".NET {RuntimeInformation.FrameworkDescription}";
    }

    public static List<string> GetLocalIpAddresses()
    {
        var result = new List<string>();
        try
        {
            var host = Dns.GetHostEntry(Dns.GetHostName());
            foreach (var ip in host.AddressList)
            {
                if (ip.AddressFamily == AddressFamily.InterNetwork)
                    result.Add(ip.ToString());
            }
        }
        catch { }
        return result;
    }

    public static string GetDefaultStoragePath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "ExeWatch", "pending");
    }

    public static string GenerateSessionId()
    {
        return Guid.NewGuid().ToString("N")[..16];
    }
}
