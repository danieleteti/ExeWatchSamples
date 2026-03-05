namespace ExeWatch.Internal;

internal sealed class FileQueue
{
    private readonly string _storagePath;
    private readonly InternalLogger _logger;
    private int _fileCounter;

    public FileQueue(string storagePath, InternalLogger logger)
    {
        _storagePath = storagePath;
        _logger = logger;
        Directory.CreateDirectory(_storagePath);
    }

    public void Enqueue(string content, string extension)
    {
        try
        {
            var counter = Interlocked.Increment(ref _fileCounter);
            var fileName = $"{DateTime.UtcNow:yyyyMMdd_HHmmssfff}_{counter}_{Environment.CurrentManagedThreadId}{extension}";
            var filePath = Path.Combine(_storagePath, fileName);

            // Write to temp file first, then rename for atomicity
            var tempPath = filePath + ".tmp";
            File.WriteAllText(tempPath, content);
            File.Move(tempPath, filePath);
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | FileQueue.Enqueue failed: {ex.Message}");
        }
    }

    public List<string> GetPendingFiles(string extension)
    {
        try
        {
            return Directory.GetFiles(_storagePath, $"*{extension}")
                .OrderBy(f => f)
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    public List<string> GetAllPendingFiles()
    {
        try
        {
            var files = new List<string>();
            files.AddRange(Directory.GetFiles(_storagePath, $"*{Constants.LogFileExtension}"));
            files.AddRange(Directory.GetFiles(_storagePath, $"*{Constants.DeviceFileExtension}"));
            files.AddRange(Directory.GetFiles(_storagePath, $"*{Constants.MetricFileExtension}"));
            files.Sort(StringComparer.Ordinal);
            return files;
        }
        catch
        {
            return [];
        }
    }

    public bool MarkAsSending(string filePath, out string sendingPath)
    {
        sendingPath = filePath + Constants.SendingExtension;
        try
        {
            File.Move(filePath, sendingPath);
            return true;
        }
        catch
        {
            sendingPath = "";
            return false;
        }
    }

    public void DeleteFile(string filePath)
    {
        try { File.Delete(filePath); }
        catch { }
    }

    public void RestoreFromSending(string sendingPath)
    {
        try
        {
            if (!File.Exists(sendingPath)) return;
            var originalPath = sendingPath[..^Constants.SendingExtension.Length];
            File.Move(sendingPath, originalPath);
        }
        catch { }
    }

    public void RestoreAllSendingFiles()
    {
        try
        {
            var sendingFiles = Directory.GetFiles(_storagePath, $"*{Constants.SendingExtension}");
            foreach (var file in sendingFiles)
                RestoreFromSending(file);

            if (sendingFiles.Length > 0)
                _logger.Log($"RECOVERY | Restored {sendingFiles.Length} .sending files from previous session");
        }
        catch { }
    }

    public void PurgeExpiredFiles(int maxAgeDays)
    {
        if (maxAgeDays <= 0) return;

        try
        {
            var cutoff = DateTime.UtcNow.AddDays(-maxAgeDays);
            int deleted = 0;

            foreach (var file in GetAllPendingFiles())
            {
                var fi = new FileInfo(file);
                if (fi.CreationTimeUtc < cutoff)
                {
                    File.Delete(file);
                    deleted++;
                }
            }

            if (deleted > 0)
                _logger.Log($"PURGE | Deleted {deleted} expired files (older than {maxAgeDays} days)");
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | PurgeExpiredFiles failed: {ex.Message}");
        }
    }

    public string ReadFile(string filePath)
    {
        return File.ReadAllText(filePath);
    }
}
