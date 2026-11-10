using System.Text;
using ExeWatch.Models;

namespace ExeWatch.Platform;

/// <summary>
/// A folder that identifies the user (the profile, the application data) and the token that stands
/// in for it when AnonymizeDeviceId is on, e.g. ("[USERPROFILE]", @"C:\Users\bob").
/// </summary>
internal readonly record struct PathRoot(string Token, string Value);

internal static class PathScrubber
{
    // A shorter value is a drive ("C:\"), the filesystem root or noise: replacing it would damage
    // the text instead of hiding a person.
    private const int MinRootLength = 4;

    /// <summary>Windows paths ignore case, the others do not.</summary>
    public static bool PathsAreCaseSensitive => !OperatingSystem.IsWindows();

    /// <summary>
    /// The folders of the current user that appear in paths: USERPROFILE, APPDATA, LOCALAPPDATA and
    /// TEMP on Windows, HOME elsewhere. Empty values are left out.
    /// </summary>
    public static List<PathRoot> GetUserPathRoots()
    {
        var roots = new List<PathRoot>();

        void Add(string token, string variable)
        {
            var value = Environment.GetEnvironmentVariable(variable);
            if (!string.IsNullOrEmpty(value))
                roots.Add(new PathRoot(token, value));
        }

        if (OperatingSystem.IsWindows())
        {
            Add("[USERPROFILE]", "USERPROFILE");
            Add("[APPDATA]", "APPDATA");
            Add("[LOCALAPPDATA]", "LOCALAPPDATA");
            Add("[TEMP]", "TEMP");
            Add("[TEMP]", "TMP");
        }
        else
        {
            Add("[HOME]", "HOME");
            // A removable disk is mounted under the login's own folder: /media/<login>, /run/media/<login>.
            var login = Environment.UserName;
            if (!string.IsNullOrEmpty(login) && login != "unknown")
            {
                roots.Add(new PathRoot("[MEDIA]", "/media/" + login));
                roots.Add(new PathRoot("[MEDIA]", "/run/media/" + login));
            }
        }
        return roots;
    }

    /// <summary>
    /// Replaces, anywhere in the text, a path that starts with one of the roots by its token (longest
    /// root first). The root has to end at a separator, at a delimiter or at the end of the text, and
    /// not start in the middle of a name. '/' and '\' are the same separator.
    /// </summary>
    public static string Scrub(string text, IReadOnlyList<PathRoot> roots, bool caseSensitive)
    {
        if (string.IsNullOrEmpty(text) || roots.Count == 0)
            return text;
        var comparison = caseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;

        // The usable roots, without repeated values, longest first.
        var usable = new List<(string Value, string Token)>();
        foreach (var root in roots)
        {
            var value = root.Value.Replace('/', '\\').TrimEnd('\\');
            if (value.Length < MinRootLength || string.IsNullOrEmpty(root.Token))
                continue;
            if (usable.Exists(u => string.Equals(u.Value, value, comparison)))
                continue;
            usable.Add((value, root.Token));
        }
        if (usable.Count == 0)
            return text;
        usable.Sort((a, b) => b.Value.Length.CompareTo(a.Value.Length));

        // The comparison runs on a copy with the same length as the text, so an index in one is an index in the other.
        var normalized = text.Replace('/', '\\');
        var result = new StringBuilder(text.Length);
        var i = 0;
        while (i < text.Length)
        {
            var matched = false;
            // A name does not start in the middle of another: 'xC:\Users\bob', '/mnt/home/bob'.
            if (i == 0 || !IsNameChar(normalized[i - 1]))
            {
                foreach (var (value, token) in usable)
                {
                    var end = i + value.Length;
                    if (end > text.Length || string.Compare(normalized, i, value, 0, value.Length, comparison) != 0)
                        continue;
                    // ... and it does not end in the middle of one: 'bobby', 'bob.old', 'bob~1'.
                    if (end < text.Length && IsNameChar(normalized[end]))
                        continue;
                    result.Append(token);
                    i = end;
                    matched = true;
                    break;
                }
            }
            if (!matched)
            {
                result.Append(text[i]);
                i++;
            }
        }
        return result.ToString();
    }

    /// <summary>
    /// Removes what names a person: user folders in the paths and the command line become their tokens,
    /// local IP addresses and volume names are dropped, and a mount point under the user's folders gets its token.
    /// </summary>
    public static void Anonymize(HardwareInfo hardware, IReadOnlyList<PathRoot> roots, bool caseSensitive)
    {
        hardware.ExecutablePath = Scrub(hardware.ExecutablePath, roots, caseSensitive);
        hardware.WorkingDirectory = Scrub(hardware.WorkingDirectory, roots, caseSensitive);
        hardware.CommandLine = Scrub(hardware.CommandLine, roots, caseSensitive);
        // A private address says where the person is; nothing in the diagnosis needs it.
        hardware.LocalIpAddresses = [];
        // A volume label is whatever its owner typed: "BOBS DISK".
        foreach (var disk in hardware.Disks)
        {
            disk.VolumeName = "";
            var drive = Scrub(disk.Drive, roots, caseSensitive);
            // What follows the media folder is the disk's label ("/media/bob/BOBS DISK"): it goes too.
            disk.Drive = drive.StartsWith("[MEDIA]", StringComparison.Ordinal) ? "[MEDIA]" : drive;
        }
    }

    // A character that can be part of a file or folder name. '/' and '\' are not: they end a name.
    private static bool IsNameChar(char c)
        => char.IsLetterOrDigit(c) || c is '_' or '.' or '-' or '~';
}
