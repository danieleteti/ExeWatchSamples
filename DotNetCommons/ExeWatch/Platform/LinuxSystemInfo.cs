using System.Globalization;

namespace ExeWatch.Platform;

/// <summary>
/// What a Linux machine says about itself in /proc. The same files and the same fields the Python SDK
/// reads, so the two report one machine the same way. The parsers take text and run anywhere.
/// </summary>
internal static class LinuxSystemInfo
{
    // Mounts that are the kernel talking to itself, not a disk: the same list as the Python SDK.
    private static readonly HashSet<string> PseudoFileSystems = new(StringComparer.Ordinal)
    {
        "proc", "sysfs", "devtmpfs", "tmpfs", "devpts", "cgroup", "cgroup2", "pstore", "securityfs",
        "debugfs", "hugetlbfs", "mqueue", "fusectl", "binfmt_misc", "autofs", "tracefs", "configfs",
        "efivarfs", "bpf", "nsfs", "fuse.snapfuse",
    };

    public static bool IsPseudoFileSystem(string fileSystem) => PseudoFileSystems.Contains(fileSystem);

    /// <summary>MemTotal and MemAvailable of /proc/meminfo, in bytes. 0 for what is missing or unreadable.</summary>
    public static (long Total, long Available) ParseMemInfo(string text)
    {
        long total = 0, available = 0;
        foreach (var line in text.Split('\n'))
        {
            if (line.StartsWith("MemTotal:", StringComparison.Ordinal))
                total = KiloBytes(line);
            else if (line.StartsWith("MemAvailable:", StringComparison.Ordinal))
                available = KiloBytes(line);
        }
        return (total, available);
    }

    /// <summary>The first "model name" and the first "cpu cores" of /proc/cpuinfo. Empty and 0 when absent (ARM has neither).</summary>
    public static (string Name, int Cores) ParseCpuInfo(string text)
    {
        var name = "";
        var cores = 0;
        foreach (var line in text.Split('\n'))
        {
            if (name.Length == 0 && line.StartsWith("model name", StringComparison.Ordinal))
                name = Value(line);
            else if (cores == 0 && line.StartsWith("cpu cores", StringComparison.Ordinal))
                int.TryParse(Value(line), NumberStyles.Integer, CultureInfo.InvariantCulture, out cores);
        }
        return (name, cores);
    }

    public static (long Total, long Available) ReadMemory() => ParseMemInfo(ReadOrEmpty("/proc/meminfo"));

    public static (string Name, int Cores) ReadCpu() => ParseCpuInfo(ReadOrEmpty("/proc/cpuinfo"));

    private static string ReadOrEmpty(string path)
    {
        try { return File.ReadAllText(path); }
        catch { return ""; }
    }

    private static string Value(string line)
    {
        var colon = line.IndexOf(':');
        return colon < 0 ? "" : line[(colon + 1)..].Trim();
    }

    // "MemTotal:       16384000 kB" -> bytes
    private static long KiloBytes(string line)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2 && long.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var kb)
            ? kb * 1024
            : 0;
    }
}
