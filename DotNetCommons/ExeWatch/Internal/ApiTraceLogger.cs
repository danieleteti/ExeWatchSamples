namespace ExeWatch.Internal;

internal sealed class ApiTraceLogger
{
    private readonly string _filePath;
    private readonly object _lock = new();
    private int _writeCount;

    public ApiTraceLogger(string storagePath)
    {
        _filePath = Path.Combine(storagePath, Constants.ApiTraceFile);
    }

    public void Log(string method, string url, int statusCode, long elapsedMs, string? detail = null)
    {
        try
        {
            lock (_lock)
            {
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {method} {url} | {elapsedMs}ms | HTTP {statusCode}";
                if (detail != null)
                    line += $" | {detail}";

                Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
                File.AppendAllText(_filePath, line + Environment.NewLine);

                _writeCount++;
                if (_writeCount >= Constants.ApiTraceCheckInterval)
                {
                    _writeCount = 0;
                    RotateIfNeeded();
                }
            }
        }
        catch { }
    }

    public void CleanOld()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var fi = new FileInfo(_filePath);
            if ((DateTime.Now - fi.LastWriteTime).TotalHours > Constants.ApiTraceMaxAgeHours)
                File.Delete(_filePath);

            var oldPath = _filePath + ".old";
            if (File.Exists(oldPath))
            {
                var oldFi = new FileInfo(oldPath);
                if ((DateTime.Now - oldFi.LastWriteTime).TotalHours > Constants.ApiTraceMaxAgeHours)
                    File.Delete(oldPath);
            }
        }
        catch { }
    }

    private void RotateIfNeeded()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var fi = new FileInfo(_filePath);
            if (fi.Length > Constants.ApiTraceMaxSize)
            {
                var oldPath = _filePath + ".old";
                if (File.Exists(oldPath)) File.Delete(oldPath);
                File.Move(_filePath, oldPath);
            }
        }
        catch { }
    }
}
