using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

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

    /// <summary>
    /// The code that stands for a user name: <see cref="KeyedCode"/> with the key of this machine. The same
    /// function, with the same result, as the Delphi, DLL and Python SDKs: the same user on the same
    /// machine gives the same code in all of them.
    /// </summary>
    public static string AnonymizeUsername(string username) => KeyedCode(GetDeviceKey(), username);

    /// <summary>
    /// The code that stands for a host name. What follows the first dot is left out: "srv01" and
    /// "srv01.example.com" are one machine, and runtimes report either.
    /// </summary>
    public static string AnonymizeHostname(string hostname)
    {
        var dot = string.IsNullOrEmpty(hostname) ? -1 : hostname.IndexOf('.');
        return AnonymizeUsername(dot > 0 ? hostname[..dot] : hostname);
    }

    /// <summary>
    /// The first 8 hex digits of HMAC-SHA256(key, name), the name in UTF-8 with its ASCII letters in
    /// lower case; "anonymous" for an empty name. Without the key the code says nothing about the name.
    /// </summary>
    public static string KeyedCode(byte[] key, string name)
    {
        if (string.IsNullOrEmpty(name))
            return "anonymous";
        var message = System.Text.Encoding.UTF8.GetBytes(name);
        // On the bytes, and for ASCII only: every language gives the same result, whatever its idea of case.
        for (var i = 0; i < message.Length; i++)
            if (message[i] >= 0x41 && message[i] <= 0x5A)
                message[i] += 0x20;
        var mac = System.Security.Cryptography.HMACSHA256.HashData(key, message);
        return Convert.ToHexString(mac, 0, 4).ToLowerInvariant();
    }

    /// <summary>
    /// A device id with both halves coded. Coding only the user name would still give the login away
    /// when the host name embeds it (e.g. host "ALICE-PC" contains user "alice").
    /// </summary>
    public static string AnonymizeDeviceId(string username, string hostname)
        => $"{AnonymizeUsername(username)}@{AnonymizeHostname(hostname)}";

    /// <summary>
    /// 32 hex digits, as the operating system writes it. An image that never had its first boot holds the word
    /// "uninitialized" there: the same key on every machine made from it, known to everybody.
    /// </summary>
    internal static bool IsLinuxMachineId(string value)
        => value.Length == 32 && value.All(Uri.IsHexDigit);

    /// <summary>The machine id of the operating system, empty where there is none.</summary>
    public static string GetMachineId()
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                // The 64-bit view: the 32-bit one, where a 32-bit process on 64-bit Windows is sent, has no MachineGuid.
                using var hklm = Microsoft.Win32.RegistryKey.OpenBaseKey(
                    Microsoft.Win32.RegistryHive.LocalMachine, Microsoft.Win32.RegistryView.Registry64);
                using var key = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
                return (key?.GetValue("MachineGuid") as string ?? "").Trim();
            }
            if (OperatingSystem.IsLinux())
            {
                foreach (var file in new[] { "/etc/machine-id", "/var/lib/dbus/machine-id" })
                {
                    try
                    {
                        var id = File.ReadAllText(file).Trim();
                        if (IsLinuxMachineId(id)) return id;
                    }
                    catch
                    {
                        // not there, not readable: the next one
                    }
                }
            }
        }
        catch
        {
            // no machine id: the key file is used
        }
        return "";
    }

    // The key of a process that has neither a machine id nor a file it can write: it lasts as long as the process.
    private static readonly string VolatileDeviceKey = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");

    /// <summary>
    /// The key of the codes: the machine id the operating system keeps (MachineGuid on Windows,
    /// /etc/machine-id on Linux); where there is none, a random value written once in a folder of the user.
    /// It is never sent and never logged.
    /// </summary>
    public static byte[] GetDeviceKey()
    {
        var id = GetMachineId();
        if (id.Length == 0)
            id = DeviceKeyFromFile();
        return System.Text.Encoding.UTF8.GetBytes(id);
    }

    // The key in the file, empty when the file is not there or holds no key. A key is 32 to 1024
    // printable ASCII characters, with the spaces, tabs and line ends around them left out: the same
    // rule, on the same bytes, as the Delphi and Python SDKs. A file of zeros, which a crash can leave,
    // is not a key. Opened without denying anything to the others: on Windows a file that somebody is
    // giving its name to, in that instant, would not open, and would be taken for a file with no key.
    private static string ReadDeviceKey(string file)
    {
        try
        {
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            var buffer = new byte[4096];
            var count = stream.ReadAtLeast(buffer, buffer.Length, throwOnEndOfStream: false);
            var key = System.Text.Encoding.Latin1.GetString(buffer, 0, count).Trim(' ', '\t', '\r', '\n');
            return key.Length is >= 32 and <= 1024 && key.AsSpan().IndexOfAnyExceptInRange('!', '~') < 0 ? key : "";
        }
        catch
        {
            return "";
        }
    }

    [DllImport("libc", EntryPoint = "link")]
    private static extern int LinkFile([MarshalAs(UnmanagedType.LPUTF8Str)] string existing,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string created);

    // Gives the draft the name of the key file, false when that name is taken. On Windows a move
    // does it. Elsewhere the move of the runtime looks first and renames after, and a rename takes
    // the place of what is there: a hard link refuses.
    private static bool GiveName(string draft, string file)
    {
        try
        {
            if (!OperatingSystem.IsWindows())
                return LinkFile(draft, file) == 0;
            File.Move(draft, file);
            return true;
        }
        catch (Exception e) when (e is IOException or DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }

    // A file that cannot be written leaves the key of the process: the codes then change at every start,
    // and that is the price of not sending a name. newKey is the key to write where there is none:
    // the one of this process, unless a test stands for several processes at once.
    internal static string DeviceKeyFromFile(string? folder = null, string? newKey = null)
    {
        newKey ??= VolatileDeviceKey;
        try
        {
            // ~/.exewatch/device.key, the same file the Delphi and Python SDKs use.
            folder ??= OperatingSystem.IsWindows()
                ? Path.GetDirectoryName(Path.GetDirectoryName(GetDefaultStoragePath("k")))!
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".exewatch");
            var file = Path.Combine(folder, "device.key");
            var key = ReadDeviceKey(file);
            if (key.Length > 0)
                return key;
            Directory.CreateDirectory(folder);
            // Written whole under another name, then given its name in one step: processes that start
            // together never read half a key.
            var draft = file + "." + Guid.NewGuid().ToString("N");
            try
            {
                var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
                if (!OperatingSystem.IsWindows())
                    options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
                using (var stream = new FileStream(draft, options))
                {
                    stream.Write(System.Text.Encoding.ASCII.GetBytes(newKey));
                    stream.Flush(true);         // on the disk before it has its name: a power cut leaves no empty key file
                }
                // Refused when the file is there: the first one wins. A file left empty or cut short by
                // a crash, or a place with no hard links: the draft takes its place. A good key written
                // by somebody else in the meantime stays.
                if (!GiveName(draft, file) && ReadDeviceKey(file).Length == 0)
                    File.Move(draft, file, true);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // not written, or not put in place: what the file holds now decides
            }
            finally
            {
                try
                {
                    File.Delete(draft);         // no error when the move took it away
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException)
                {
                    // a draft that stays behind is not a reason to give up the key in the file
                }
            }
            key = ReadDeviceKey(file);
            if (key.Length > 0)
                return key;
        }
        catch
        {
            // not readable, not writable: the key of the process
        }
        return newKey;
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

    // Each app gets its own subdirectory based on the API key prefix so that
    // two apps running concurrently on the same machine cannot pick up each
    // other's queued files from the shared LocalAppData tree.
    //
    // NOTE: rotating the API key while the app is running orphans any files
    // buffered under the old prefix. Call WaitForSending before rotating a
    // key in a long-running process; orphaned files are purged by max-age.
    //
    // "default" is only reached if apiKey is empty, which ExeWatchClient
    // rejects at initialization — it is a safety net so the path always has
    // a terminal subdirectory.
    public static string GetDefaultStoragePath(string apiKey = "")
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var prefix = string.IsNullOrEmpty(apiKey) ? "default" : apiKey[..Math.Min(16, apiKey.Length)];
        return Path.Combine(localAppData, "ExeWatch", "pending", prefix);
    }

    public static string GenerateSessionId()
    {
        return Guid.NewGuid().ToString("N")[..16];
    }

    /// <summary>
    /// 16-hex random id for nested timing traces (trace_id / span_id).
    /// Mirrors the session-id scheme: a GUID with separators stripped,
    /// first 16 chars.
    /// </summary>
    public static string GenerateId16()
    {
        return Guid.NewGuid().ToString("N")[..16];
    }
}
