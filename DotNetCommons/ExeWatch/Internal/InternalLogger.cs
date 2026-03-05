namespace ExeWatch.Internal;

internal sealed class InternalLogger
{
    private readonly string _filePath;
    private readonly object _lock = new();

    public InternalLogger(string storagePath)
    {
        _filePath = Path.Combine(storagePath, Constants.InternalLogFile);
    }

    public void Log(string message)
    {
        try
        {
            lock (_lock)
            {
                var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} | {message}";
                Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
                File.AppendAllText(_filePath, line + Environment.NewLine);
                TrimIfNeeded();
            }
        }
        catch { }
    }

    public void CleanOldLogs()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var fi = new FileInfo(_filePath);
            if ((DateTime.Now - fi.LastWriteTime).TotalDays > Constants.InternalLogMaxAgeDays)
                File.Delete(_filePath);
        }
        catch { }
    }

    private void TrimIfNeeded()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var lines = File.ReadAllLines(_filePath);
            if (lines.Length > Constants.InternalLogMaxLines)
            {
                var trimmed = lines[^Constants.InternalLogMaxLines..];
                File.WriteAllLines(_filePath, trimmed);
            }
        }
        catch { }
    }
}
