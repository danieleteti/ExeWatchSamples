using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using ExeWatch.Config;
using ExeWatch.Internal;
using ExeWatch.Models;
using ExeWatch.Platform;
using ExeWatch.Serialization;

namespace ExeWatch;

public sealed class ExeWatchClient : IDisposable
{
    private readonly ExeWatchConfig _config;
    private readonly DeviceInfo _deviceInfo;
    private readonly InternalLogger _logger;
    private readonly ApiTraceLogger _apiTrace;
    private readonly FileQueue _fileQueue;
    private readonly HttpClient _httpClient;
    private readonly Thread _shipperThread;
    private readonly ManualResetEventSlim _shutdownEvent = new(false);
    private readonly ManualResetEventSlim _flushDoneEvent = new(false);
    private SamplerThread? _sampler;
    private readonly string _sessionId;
    private readonly int _processId;
    private volatile bool _shutdown;
    private bool _disposed;

    // Server config (written by shipper thread, read by Log method)
    private ServerConfig _serverConfig;
    private readonly object _serverConfigLock = new();
    private volatile int _configVersion;

    // Log buffer (written by Log method, read/cleared by shipper thread)
    private readonly List<LogEvent> _buffer = [];
    private readonly object _bufferLock = new();

    // Breadcrumbs (thread-local via thread ID)
    private readonly ConcurrentDictionary<int, List<Breadcrumb>> _breadcrumbs = new();

    // User identity
    private UserIdentity? _user;
    private readonly object _userLock = new();

    // Global tags
    private readonly Dictionary<string, string> _tags = [];
    private readonly object _tagsLock = new();

    // Custom device info
    private readonly Dictionary<string, string> _customDeviceInfo = [];
    private readonly object _customDeviceInfoLock = new();

    // Timing — stored per-thread so two threads using the same timing id
    // don't collide (StartTiming auto-closes duplicates). Outer key =
    // Environment.CurrentManagedThreadId; inner key = user-provided timing id.
    private readonly Dictionary<int, Dictionary<string, TimingEntry>> _timings = [];
    private readonly Dictionary<int, List<string>> _timingStacks = [];
    private readonly object _timingLock = new();

    // Metrics (written by RecordGauge/IncrementCounter, read/cleared by shipper thread)
    private readonly Dictionary<string, MetricAccumulator> _metrics = [];
    private readonly object _metricsLock = new();
    private DateTime _lastMetricFlush = DateTime.UtcNow;

    // State
    private volatile bool _enabled = true;
    private volatile bool _deviceInfoSent;

    // Callbacks
    public Action<string>? OnError { get; set; }
    public Action<int, int>? OnLogsSent { get; set; }
    public Action<bool, string>? OnDeviceInfoSent { get; set; }
    public Action<bool, string>? OnCustomDeviceInfoSent { get; set; }

    public bool Enabled { get => _enabled; set => _enabled = value; }
    public bool DeviceInfoSent => _deviceInfoSent;
    public string SessionId => _sessionId;
    public ExeWatchConfig Config => _config;

    public ExeWatchClient(ExeWatchConfig config)
    {
        ValidateApiKey(config.ApiKey);

        _config = config;
        _sessionId = PlatformHelper.GenerateSessionId();
        _processId = PlatformHelper.GetCurrentProcessId();

        // Storage path
        if (string.IsNullOrEmpty(_config.StoragePath))
            _config.StoragePath = PlatformHelper.GetDefaultStoragePath(_config.ApiKey);

        // Device info
        var hostname = PlatformHelper.GetHostname();
        var username = PlatformHelper.GetUsername();
        var deviceId = config.AnonymizeDeviceId
            ? $"{PlatformHelper.AnonymizeUsername(username)}@{hostname}"
            : PlatformHelper.GetDeviceId();
        _deviceInfo = new DeviceInfo
        {
            DeviceId = deviceId,
            Hostname = hostname,
            Username = username,
            OsType = PlatformHelper.GetOsType(),
            OsVersion = PlatformHelper.GetOsVersion(),
            AppBinaryVersion = SystemInfoCollector.GetAppBinaryVersion(),
            AppVersion = _config.AppVersion,
            SdkVersion = Constants.SdkVersion,
            TimezoneOffset = PlatformHelper.GetTimezoneOffset()
        };

        // Internal logging
        _logger = new InternalLogger(_config.StoragePath);
        _apiTrace = new ApiTraceLogger(_config.StoragePath);
        _logger.CleanOldLogs();
        _apiTrace.CleanOld();

        _logger.Log($"SDK STARTUP | Version={Constants.SdkVersion} | Platform={Constants.SdkPlatform} | SessionId={_sessionId}");

        // File queue
        _fileQueue = new FileQueue(_config.StoragePath, _logger);
        _fileQueue.RestoreAllSendingFiles();

        // Server config (initial defaults)
        _serverConfig = new ServerConfig
        {
            FlushIntervalMs = config.FlushIntervalMs,
            BatchSize = config.BufferSize,
            SamplingRate = config.SampleRate
        };

        // HTTP client (singleton, best practice)
        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.Add("X-API-Key", config.ApiKey);
        _httpClient.Timeout = TimeSpan.FromSeconds(30);

        // Shipper thread - direct access to buffer/metrics like Delphi SDK
        _shipperThread = new Thread(ShipperThreadExecute)
        {
            IsBackground = true,
            Name = "ExeWatch-Shipper"
        };
        _shipperThread.Start();

        // Initial custom device info
        foreach (var kvp in _config.InitialCustomDeviceInfo)
            _customDeviceInfo[kvp.Key] = kvp.Value;

        // Hook AppDomain unhandled exceptions
        AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;

        // Queue initial device info
        if (!string.IsNullOrEmpty(config.CustomerId))
            QueueDeviceInfo();

        // Log "Application started"
        LogStartup();
    }

    private static void ValidateApiKey(string apiKey)
    {
        if (string.IsNullOrEmpty(apiKey))
            throw new ArgumentException("API key is required", nameof(apiKey));

        foreach (var prefix in Constants.RejectedApiKeyPrefixes)
        {
            if (apiKey.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException($"API key prefix '{prefix}' is not allowed for .NET SDK", nameof(apiKey));
        }

        bool valid = false;
        foreach (var prefix in Constants.ValidApiKeyPrefixes)
        {
            if (apiKey.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                valid = true;
                break;
            }
        }

        if (!valid)
            throw new ArgumentException("Invalid API key format. Expected prefix: ew_win_, ew_lin_, ew_mac_, etc.", nameof(apiKey));
    }

    private void LogStartup()
    {
        var extraData = new Dictionary<string, object>
        {
            ["sdk_version"] = Constants.SdkVersion,
            ["sdk_platform"] = Constants.SdkPlatform,
            ["api_version"] = Constants.ApiVersion,
            ["session_id"] = _sessionId,
            ["runtime"] = PlatformHelper.GetRuntimeVersion()
        };

        Log(LogLevel.Info, "Application started", "exewatch", extraData);
    }

    // ================================================================
    // SHIPPER THREAD - runs on background thread, direct buffer access
    // Same pattern as Delphi TExeWatch.ShipperThreadExecute
    // ================================================================

    private void ShipperThreadExecute()
    {
        _logger.Log("SHIPPER | Thread started");

        var lastFlushTime = DateTime.UtcNow;
        var lastPurgeTime = DateTime.UtcNow;

        while (!_shutdown)
        {
            try
            {
                // 1. Determine wait time based on pending files
                var pendingFiles = _fileQueue.GetAllPendingFiles();
                int waitMs = pendingFiles.Count > 0
                    ? 100 // Quick retry when files pending
                    : GetEffectiveFlushInterval();

                // 2. Wait for shutdown signal or timeout
                _shutdownEvent.Wait(waitMs);

                if (_shutdown)
                {
                    // Final persist & send on shutdown
                    PersistBuffer();
                    PersistMetrics();
                    pendingFiles = _fileQueue.GetAllPendingFiles();
                    foreach (var file in pendingFiles)
                    {
                        if (!SendFileToServer(file))
                            break;
                    }
                    break;
                }

                // 3. Persist buffer if flush interval elapsed
                if (MillisecondsSince(lastFlushTime) >= GetEffectiveFlushInterval())
                {
                    PersistBuffer();
                    lastFlushTime = DateTime.UtcNow;
                }

                // 4. Persist metrics if interval elapsed (every 30s)
                if (MillisecondsSince(_lastMetricFlush) >= Constants.MetricFlushIntervalMs)
                {
                    PersistMetrics();
                    _lastMetricFlush = DateTime.UtcNow;
                }

                // 5. Purge expired files (hourly)
                if ((DateTime.UtcNow - lastPurgeTime).TotalHours >= 1)
                {
                    _fileQueue.PurgeExpiredFiles(_config.MaxPendingAgeDays);
                    lastPurgeTime = DateTime.UtcNow;
                }

                // 6. Send pending files (oldest first)
                pendingFiles = _fileQueue.GetAllPendingFiles();
                foreach (var file in pendingFiles)
                {
                    if (_shutdown) break;

                    if (!SendFileToServer(file))
                    {
                        // Send failed, wait before retrying
                        _shutdownEvent.Wait(Math.Min(_config.RetryIntervalMs, 5000));
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.Log($"ERROR | Shipper loop: {ex.Message}");
                _shutdownEvent.Wait(1000);
            }
        }

        _flushDoneEvent.Set();
        _logger.Log("SHIPPER | Thread stopped");
    }

    private int GetEffectiveFlushInterval()
    {
        lock (_serverConfigLock)
            return _serverConfig.FlushIntervalMs;
    }

    private static double MillisecondsSince(DateTime time)
    {
        return (DateTime.UtcNow - time).TotalMilliseconds;
    }

    /// <summary>
    /// Moves in-memory log buffer to disk file. Called from shipper thread.
    /// </summary>
    private void PersistBuffer()
    {
        List<LogEvent> events;
        lock (_bufferLock)
        {
            if (_buffer.Count == 0) return;
            events = new List<LogEvent>(_buffer);
            _buffer.Clear();
        }

        if (string.IsNullOrEmpty(_config.CustomerId)) return;

        try
        {
            var json = JsonPayloadBuilder.BuildLogBatch(_config.CustomerId, _deviceInfo, events);
            _fileQueue.Enqueue(json, Constants.LogFileExtension);
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | PersistBuffer failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Moves in-memory metric accumulators to disk file. Called from shipper thread.
    /// </summary>
    private void PersistMetrics()
    {
        List<MetricAccumulator> snapshot;
        lock (_metricsLock)
        {
            if (_metrics.Count == 0) return;
            snapshot = _metrics.Values.ToList();
            _metrics.Clear();
        }

        if (string.IsNullOrEmpty(_config.CustomerId)) return;

        try
        {
            var json = JsonPayloadBuilder.BuildMetricsBatch(_config.CustomerId, _deviceInfo, _sessionId, snapshot);
            _fileQueue.Enqueue(json, Constants.MetricFileExtension);
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | PersistMetrics failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Sends a pending file to the server. Returns true on success, false on failure.
    /// </summary>
    private bool SendFileToServer(string filePath)
    {
        if (!_fileQueue.MarkAsSending(filePath, out var sendingPath))
            return true; // File disappeared, not a send failure

        try
        {
            var content = _fileQueue.ReadFile(sendingPath);
            var extension = GetOriginalExtension(filePath);
            var url = GetEndpointUrl(extension);

            var sw = Stopwatch.StartNew();
            using var httpContent = new StringContent(content, Encoding.UTF8, "application/json");

            if (_configVersion > 0)
                httpContent.Headers.Add("X-Config-Version", _configVersion.ToString());

            var response = _httpClient.PostAsync(url, httpContent).GetAwaiter().GetResult();
            sw.Stop();

            var responseBody = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            var statusCode = (int)response.StatusCode;

            _apiTrace.Log("POST", url, statusCode, sw.ElapsedMilliseconds);

            if (response.IsSuccessStatusCode)
            {
                _fileQueue.DeleteFile(sendingPath);
                HandleSuccessResponse(responseBody, extension);
                return true;
            }
            else if (statusCode == 422)
            {
                _fileQueue.DeleteFile(sendingPath);
                _logger.Log($"VALIDATION ERROR | HTTP 422 for {Path.GetFileName(filePath)}: {responseBody}");
                OnError?.Invoke($"Validation error: {responseBody}");
                return true; // Not a retriable error
            }
            else if (statusCode == 429)
            {
                _fileQueue.DeleteFile(sendingPath);
                _logger.Log($"QUOTA | HTTP 429 for {Path.GetFileName(filePath)}");
                HandleSuccessResponse(responseBody, extension);
                return true;
            }
            else if (statusCode == 401 || statusCode == 403)
            {
                _fileQueue.RestoreFromSending(sendingPath);
                _logger.Log($"AUTH ERROR | HTTP {statusCode}: {responseBody}");
                OnError?.Invoke($"Authentication error: HTTP {statusCode}");
                return false;
            }
            else
            {
                _fileQueue.RestoreFromSending(sendingPath);
                _logger.Log($"SERVER ERROR | HTTP {statusCode} for {Path.GetFileName(filePath)}");
                OnError?.Invoke($"Server error: HTTP {statusCode}");
                return false;
            }
        }
        catch (Exception ex)
        {
            _fileQueue.RestoreFromSending(sendingPath);
            _logger.Log($"ERROR | Send failed: {ex.Message}");
            OnError?.Invoke($"Network error: {ex.Message}");
            return false;
        }
    }

    private void HandleSuccessResponse(string responseBody, string extension)
    {
        var config = JsonPayloadBuilder.ParseServerConfig(responseBody);
        if (config != null)
        {
            lock (_serverConfigLock) _serverConfig = config;
            _configVersion = config.Version;
        }

        var (accepted, rejected) = JsonPayloadBuilder.ParseIngestResponse(responseBody);

        if (extension == Constants.LogFileExtension)
            OnLogsSent?.Invoke(accepted, rejected);
        else if (extension == Constants.DeviceFileExtension)
        {
            _deviceInfoSent = true;
            OnDeviceInfoSent?.Invoke(true, "");
        }
    }

    private string GetEndpointUrl(string extension) => extension switch
    {
        Constants.DeviceFileExtension => $"{_config.Endpoint.TrimEnd('/')}/api/{Constants.ApiVersion}/ingest/device-info",
        Constants.MetricFileExtension => $"{_config.Endpoint.TrimEnd('/')}/api/{Constants.ApiVersion}/ingest/metrics",
        _ => $"{_config.Endpoint.TrimEnd('/')}/api/{Constants.ApiVersion}/ingest/logs"
    };

    private static string GetOriginalExtension(string filePath)
    {
        if (filePath.EndsWith(Constants.LogFileExtension)) return Constants.LogFileExtension;
        if (filePath.EndsWith(Constants.DeviceFileExtension)) return Constants.DeviceFileExtension;
        if (filePath.EndsWith(Constants.MetricFileExtension)) return Constants.MetricFileExtension;
        return Constants.LogFileExtension;
    }

    // ======== LOGGING ========

    public void Log(LogLevel level, string message, string tag = "main", Dictionary<string, object>? extraData = null)
    {
        if (_disposed || !_enabled) return;
        if (string.IsNullOrEmpty(message)) return;
        if (string.IsNullOrEmpty(_config.CustomerId)) return;

        ServerConfig serverConfig;
        lock (_serverConfigLock) serverConfig = _serverConfig;

        // Server-driven enabled check
        if (!serverConfig.Enabled && level < LogLevel.Error) return;

        // Min level filtering (errors always pass)
        if (level < LogLevel.Error && level < serverConfig.MinLevel) return;

        // Sampling (errors always pass)
        if (level < LogLevel.Error && !ShouldSample(serverConfig.SamplingRate))
            return;

        // Truncate message
        if (message.Length > serverConfig.MaxMessageLength)
            message = message[..serverConfig.MaxMessageLength] + "\r\n\r\n[MESSAGE TRUNCATED]";

        // Build extra_data
        var allExtra = new Dictionary<string, object>();

        // Add global tags
        lock (_tagsLock)
        {
            foreach (var kvp in _tags)
                allExtra[$"tag_{kvp.Key}"] = kvp.Value;
        }

        // Add user identity
        lock (_userLock)
        {
            if (_user != null && !_user.IsEmpty)
            {
                if (!string.IsNullOrEmpty(_user.Id)) allExtra["user_id"] = _user.Id;
                if (!string.IsNullOrEmpty(_user.Email)) allExtra["user_email"] = _user.Email;
                if (!string.IsNullOrEmpty(_user.Name)) allExtra["user_name"] = _user.Name;
            }
        }

        // Add breadcrumbs for error/fatal, then clear
        if (level >= LogLevel.Error)
        {
            var breadcrumbs = GetBreadcrumbsInternal();
            if (breadcrumbs.Count > 0)
            {
                allExtra["breadcrumbs"] = breadcrumbs;
                ClearBreadcrumbsInternal();
            }
        }

        // Merge caller's extra data
        if (extraData != null)
        {
            foreach (var kvp in extraData)
                allExtra[kvp.Key] = kvp.Value;
        }

        var evt = new LogEvent
        {
            Level = level,
            Message = message,
            Tag = tag,
            Timestamp = DateTime.UtcNow,
            ThreadId = Environment.CurrentManagedThreadId,
            ProcessId = _processId,
            SessionId = _sessionId,
            ExtraData = allExtra.Count > 0 ? allExtra : null
        };

        bool shouldPersist;
        lock (_bufferLock)
        {
            _buffer.Add(evt);
            shouldPersist = _buffer.Count >= serverConfig.BatchSize;
        }

        // Batch size reached: persist immediately (like Delphi SDK)
        if (shouldPersist)
            PersistBuffer();
    }

    public void Debug(string message, string tag = "main") => Log(LogLevel.Debug, message, tag);
    public void Info(string message, string tag = "main") => Log(LogLevel.Info, message, tag);
    public void Warning(string message, string tag = "main") => Log(LogLevel.Warning, message, tag);
    public void Error(string message, string tag = "main") => Log(LogLevel.Error, message, tag);
    public void Fatal(string message, string tag = "main") => Log(LogLevel.Fatal, message, tag);

    // Format-style overloads
    public void Debug(string format, string tag, params object[] args) => Log(LogLevel.Debug, string.Format(format, args), tag);
    public void Info(string format, string tag, params object[] args) => Log(LogLevel.Info, string.Format(format, args), tag);
    public void Warning(string format, string tag, params object[] args) => Log(LogLevel.Warning, string.Format(format, args), tag);
    public void Error(string format, string tag, params object[] args) => Log(LogLevel.Error, string.Format(format, args), tag);
    public void Fatal(string format, string tag, params object[] args) => Log(LogLevel.Fatal, string.Format(format, args), tag);

    public void ErrorWithException(Exception ex, string tag = "main", string additionalMessage = "")
    {
        var message = string.IsNullOrEmpty(additionalMessage)
            ? $"{ex.GetType().Name}: {ex.Message}"
            : $"{additionalMessage} | {ex.GetType().Name}: {ex.Message}";

        if (ex.StackTrace != null)
            message += $"\n{ex.StackTrace}";

        var extraData = new Dictionary<string, object>
        {
            ["exception_class"] = ex.GetType().FullName ?? ex.GetType().Name,
            ["exception_source"] = "caught"
        };

        Log(LogLevel.Error, message, tag, extraData);
    }

    // ======== BREADCRUMBS ========

    public void AddBreadcrumb(BreadcrumbType type, string category, string message, Dictionary<string, object>? data = null)
    {
        var bc = new Breadcrumb
        {
            Timestamp = DateTime.UtcNow,
            Type = type,
            Category = category,
            Message = message,
            Data = data
        };

        var threadId = Environment.CurrentManagedThreadId;
        var list = _breadcrumbs.GetOrAdd(threadId, _ => new List<Breadcrumb>());

        lock (list)
        {
            list.Add(bc);
            while (list.Count > Constants.MaxBreadcrumbs)
                list.RemoveAt(0);
        }
    }

    public void AddBreadcrumb(string message, string category = "custom")
        => AddBreadcrumb(BreadcrumbType.Custom, category, message);

    public List<Breadcrumb> GetBreadcrumbs() => GetBreadcrumbsInternal();

    private List<Breadcrumb> GetBreadcrumbsInternal()
    {
        var threadId = Environment.CurrentManagedThreadId;
        if (_breadcrumbs.TryGetValue(threadId, out var list))
        {
            lock (list)
                return new List<Breadcrumb>(list);
        }
        return [];
    }

    public void ClearBreadcrumbs() => ClearBreadcrumbsInternal();

    private void ClearBreadcrumbsInternal()
    {
        var threadId = Environment.CurrentManagedThreadId;
        if (_breadcrumbs.TryGetValue(threadId, out var list))
        {
            lock (list)
                list.Clear();
        }
    }

    // ======== USER IDENTITY ========

    public void SetUser(string id, string email = "", string name = "")
    {
        lock (_userLock)
            _user = new UserIdentity { Id = id, Email = email, Name = name };
    }

    public void SetUser(UserIdentity user)
    {
        lock (_userLock)
            _user = user;
    }

    public void ClearUser()
    {
        lock (_userLock)
            _user = null;
    }

    public UserIdentity? GetUser()
    {
        lock (_userLock)
            return _user;
    }

    // ======== CUSTOMER ID ========

    public void SetCustomerId(string customerId)
    {
        var old = _config.CustomerId;
        _config.CustomerId = customerId;
        _logger.Log($"SetCustomerId called | CustomerId={customerId}");

        if (!string.IsNullOrEmpty(customerId) && customerId != old)
            QueueDeviceInfo();
    }

    public string GetCustomerId() => _config.CustomerId;

    // ======== GLOBAL TAGS ========

    public void SetTag(string key, string value)
    {
        lock (_tagsLock)
            _tags[key] = value;
    }

    public void SetTags(IEnumerable<KeyValuePair<string, string>> tags)
    {
        lock (_tagsLock)
        {
            foreach (var kvp in tags)
                _tags[kvp.Key] = kvp.Value;
        }
    }

    public void RemoveTag(string key)
    {
        lock (_tagsLock)
            _tags.Remove(key);
    }

    public void ClearTags()
    {
        lock (_tagsLock)
            _tags.Clear();
    }

    public Dictionary<string, string> GetTags()
    {
        lock (_tagsLock)
            return new Dictionary<string, string>(_tags);
    }

    // ======== DEVICE INFO ========

    public void SendDeviceInfo()
    {
        QueueDeviceInfo();
    }

    public void SetCustomDeviceInfo(string key, string value)
    {
        lock (_customDeviceInfoLock)
            _customDeviceInfo[key] = value;
    }

    public void ClearCustomDeviceInfo(string key)
    {
        lock (_customDeviceInfoLock)
            _customDeviceInfo.Remove(key);
    }

    public void ClearAllCustomDeviceInfo()
    {
        lock (_customDeviceInfoLock)
            _customDeviceInfo.Clear();
    }

    public void SendCustomDeviceInfo()
    {
        QueueCustomDeviceInfo();
    }

    public void SendCustomDeviceInfo(string key, string value)
    {
        SetCustomDeviceInfo(key, value);
        SendCustomDeviceInfo();
    }

    private void QueueDeviceInfo()
    {
        if (string.IsNullOrEmpty(_config.CustomerId)) return;

        try
        {
            var hardware = SystemInfoCollector.Collect();

            Dictionary<string, string>? customInfo = null;
            lock (_customDeviceInfoLock)
            {
                if (_customDeviceInfo.Count > 0)
                    customInfo = new Dictionary<string, string>(_customDeviceInfo);
            }

            var json = JsonPayloadBuilder.BuildDeviceInfo(
                _config.CustomerId, _deviceInfo, hardware, customInfo, _sessionId);

            _fileQueue.Enqueue(json, Constants.DeviceFileExtension);
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | QueueDeviceInfo failed: {ex.Message}");
        }
    }

    private void QueueCustomDeviceInfo()
    {
        if (string.IsNullOrEmpty(_config.CustomerId)) return;

        try
        {
            Dictionary<string, string>? customInfo;
            lock (_customDeviceInfoLock)
            {
                if (_customDeviceInfo.Count == 0) return;
                customInfo = new Dictionary<string, string>(_customDeviceInfo);
            }

            var json = JsonPayloadBuilder.BuildDeviceInfo(
                _config.CustomerId, _deviceInfo, null, customInfo, _sessionId);

            _fileQueue.Enqueue(json, Constants.DeviceFileExtension);
        }
        catch (Exception ex)
        {
            _logger.Log($"ERROR | QueueCustomDeviceInfo failed: {ex.Message}");
        }
    }

    // ======== TIMING ========
    //
    // Stored per-thread: two threads calling StartTiming("op") in parallel
    // must not collide (StartTiming auto-closes duplicates on same thread).
    // Caller must hold _timingLock.
    private (Dictionary<string, TimingEntry> timings, List<string> stack)
        GetOrCreateThreadTiming(int threadId)
    {
        if (!_timings.TryGetValue(threadId, out var timings))
        {
            timings = [];
            _timings[threadId] = timings;
        }
        if (!_timingStacks.TryGetValue(threadId, out var stack))
        {
            stack = [];
            _timingStacks[threadId] = stack;
        }
        return (timings, stack);
    }

    public void StartTiming(string id, string tag = "", Dictionary<string, object>? metadata = null)
    {
        TimingEntry? duplicateEntry = null;
        var evictedIds = new List<string>();
        var evictedEntries = new List<TimingEntry>();
        int threadId = Environment.CurrentManagedThreadId;

        lock (_timingLock)
        {
            var (threadTimings, threadStack) = GetOrCreateThreadTiming(threadId);

            // Check for duplicate - extract for auto-close outside lock
            if (threadTimings.TryGetValue(id, out var existing))
            {
                duplicateEntry = existing;
                threadTimings.Remove(id);
                threadStack.Remove(id);
            }

            // Check max pending (per-thread) - collect evicted entries for auto-close
            while (threadTimings.Count >= Constants.MaxPendingTimings && threadStack.Count > 0)
            {
                var oldest = threadStack[0];
                threadStack.RemoveAt(0);
                if (threadTimings.TryGetValue(oldest, out var evicted))
                {
                    evictedIds.Add(oldest);
                    evictedEntries.Add(evicted);
                    threadTimings.Remove(oldest);
                }
            }

            threadTimings[id] = new TimingEntry
            {
                StartTicks = Stopwatch.GetTimestamp(),
                Tag = tag,
                Metadata = metadata
            };
            threadStack.Add(id);
        }

        // Auto-close entries OUTSIDE the lock (Log acquires other locks)

        if (duplicateEntry != null)
        {
            var elapsed = Stopwatch.GetElapsedTime(duplicateEntry.StartTicks);
            var extraData = new Dictionary<string, object>
            {
                ["timing_type"] = "duration",
                ["timing_id"] = id,
                ["duration_ms"] = Math.Round(elapsed.TotalMilliseconds, 2),
                ["success"] = false,
                ["auto_closed"] = true,
                ["auto_close_reason"] = "duplicate_start"
            };
            if (duplicateEntry.Metadata != null)
                extraData["metadata"] = duplicateEntry.Metadata;
            var timingTag = !string.IsNullOrEmpty(duplicateEntry.Tag) ? duplicateEntry.Tag : "timing";
            Log(LogLevel.Warning, $"[TIMING] {id}: {elapsed.TotalMilliseconds:F2}ms (auto-closed, duplicate StartTiming)", timingTag, extraData);
        }

        for (int i = 0; i < evictedIds.Count; i++)
        {
            var elapsed = Stopwatch.GetElapsedTime(evictedEntries[i].StartTicks);
            var extraData = new Dictionary<string, object>
            {
                ["timing_type"] = "duration",
                ["timing_id"] = evictedIds[i],
                ["duration_ms"] = Math.Round(elapsed.TotalMilliseconds, 2),
                ["success"] = false,
                ["auto_closed"] = true,
                ["auto_close_reason"] = "max_pending_reached"
            };
            if (evictedEntries[i].Metadata != null)
                extraData["metadata"] = evictedEntries[i].Metadata!;
            var timingTag = !string.IsNullOrEmpty(evictedEntries[i].Tag) ? evictedEntries[i].Tag : "timing";
            Log(LogLevel.Warning, $"[TIMING] {evictedIds[i]}: {elapsed.TotalMilliseconds:F2}ms (auto-closed, max pending timings reached)", timingTag, extraData);
        }
    }

    public void StartTiming(string format, object[] args, string tag = "")
        => StartTiming(string.Format(format, args), tag);

    public double EndTiming(string id, Dictionary<string, object>? endMetadata = null, bool success = true)
    {
        TimingEntry? entry;
        double durationMs;
        int threadId = Environment.CurrentManagedThreadId;

        lock (_timingLock)
        {
            if (!_timings.TryGetValue(threadId, out var threadTimings) ||
                !threadTimings.TryGetValue(id, out entry))
                return -1;

            threadTimings.Remove(id);
            if (_timingStacks.TryGetValue(threadId, out var threadStack))
                threadStack.Remove(id);
        }

        var elapsed = Stopwatch.GetElapsedTime(entry.StartTicks);
        durationMs = elapsed.TotalMilliseconds;

        var extraData = new Dictionary<string, object>
        {
            ["timing_type"] = "duration",
            ["timing_id"] = id,
            ["duration_ms"] = Math.Round(durationMs, 2),
            ["success"] = success
        };

        if (entry.Metadata != null || endMetadata != null)
        {
            var merged = new Dictionary<string, object>();
            if (entry.Metadata != null)
                foreach (var kvp in entry.Metadata)
                    merged[kvp.Key] = kvp.Value;
            if (endMetadata != null)
                foreach (var kvp in endMetadata)
                    merged[kvp.Key] = kvp.Value;
            extraData["metadata"] = merged;
        }

        var tag = !string.IsNullOrEmpty(entry.Tag) ? entry.Tag : "timing";
        Log(LogLevel.Info, $"Timing: {id} completed in {durationMs:F2}ms", tag, extraData);

        return durationMs;
    }

    public double EndTiming(string format, object[] args, Dictionary<string, object>? endMetadata = null, bool success = true)
        => EndTiming(string.Format(format, args), endMetadata, success);

    public double EndTiming()
    {
        string? lastId;
        int threadId = Environment.CurrentManagedThreadId;
        lock (_timingLock)
        {
            if (!_timingStacks.TryGetValue(threadId, out var threadStack) ||
                threadStack.Count == 0)
                return -1;
            lastId = threadStack[^1];
        }
        return EndTiming(lastId);
    }

    public bool IsTimingActive(string id)
    {
        int threadId = Environment.CurrentManagedThreadId;
        lock (_timingLock)
            return _timings.TryGetValue(threadId, out var t) && t.ContainsKey(id);
    }

    public void CancelTiming(string id)
    {
        int threadId = Environment.CurrentManagedThreadId;
        lock (_timingLock)
        {
            if (_timings.TryGetValue(threadId, out var threadTimings))
                threadTimings.Remove(id);
            if (_timingStacks.TryGetValue(threadId, out var threadStack))
                threadStack.Remove(id);
        }
    }

    public void CancelTiming()
    {
        int threadId = Environment.CurrentManagedThreadId;
        lock (_timingLock)
        {
            if (!_timingStacks.TryGetValue(threadId, out var threadStack) ||
                threadStack.Count == 0)
                return;
            var lastId = threadStack[^1];
            threadStack.RemoveAt(threadStack.Count - 1);
            if (_timings.TryGetValue(threadId, out var threadTimings))
                threadTimings.Remove(lastId);
        }
    }

    public List<ActiveTimingInfo> GetActiveTimings()
    {
        int threadId = Environment.CurrentManagedThreadId;
        lock (_timingLock)
        {
            var result = new List<ActiveTimingInfo>();
            if (!_timings.TryGetValue(threadId, out var threadTimings))
                return result;
            foreach (var kvp in threadTimings)
            {
                var elapsed = Stopwatch.GetElapsedTime(kvp.Value.StartTicks);
                result.Add(new ActiveTimingInfo
                {
                    Id = kvp.Key,
                    Tag = kvp.Value.Tag,
                    ElapsedMs = elapsed.TotalMilliseconds
                });
            }
            return result;
        }
    }

    // ======== METRICS ========

    public void IncrementCounter(string name, double value = 1.0, string tag = "")
    {
        var key = $"{name}|{tag}";
        lock (_metricsLock)
        {
            if (!_metrics.TryGetValue(key, out var acc))
            {
                acc = new MetricAccumulator { Name = name, MetricType = "counter", Tag = tag };
                _metrics[key] = acc;
            }
            acc.AddCounter(value);
        }
    }

    public void RecordGauge(string name, double value, string tag = "")
    {
        var key = $"{name}|{tag}";
        lock (_metricsLock)
        {
            if (!_metrics.TryGetValue(key, out var acc))
            {
                acc = new MetricAccumulator { Name = name, MetricType = "gauge", Tag = tag };
                _metrics[key] = acc;
            }
            acc.AddGauge(value);
        }
    }

    public void RegisterPeriodicGauge(string name, Func<double> callback, string tag = "")
    {
        if (_sampler == null)
        {
            _sampler = new SamplerThread(
                _config.GaugeSamplingIntervalSec,
                (n, v, t) => RecordGauge(n, v, t),
                _logger);
        }

        _sampler.Register(name, callback, tag);
        _logger.Log($"GAUGE | Registered periodic gauge '{name}'");
    }

    public void UnregisterPeriodicGauge(string name)
    {
        _sampler?.Unregister(name);
        _logger.Log($"GAUGE | Unregistered periodic gauge '{name}'");
    }

    // ======== FLUSH ========

    public void Flush()
    {
        PersistBuffer();
        PersistMetrics();

        // Wait for shipper thread to send pending files
        _flushDoneEvent.Reset();
        // Shipper will pick up files on its next loop iteration
        // Give it a reasonable timeout
        _flushDoneEvent.Wait(TimeSpan.FromSeconds(10));
    }

    public int GetPendingCount()
    {
        int bufferCount;
        lock (_bufferLock)
            bufferCount = _buffer.Count;
        int fileCount = _fileQueue.GetAllPendingFiles().Count;
        return bufferCount + fileCount;
    }

    /// <summary>
    /// Flushes the in-memory buffer to disk and waits (up to
    /// <paramref name="timeoutSec"/> seconds) until every pending event has
    /// been shipped to the server. Useful for short-lived apps / console
    /// samples where you must ensure events are uploaded before the process
    /// exits.
    /// Returns the number of events still pending when the call returns
    /// (0 = fully drained, &gt;0 = timeout with events still queued).
    /// </summary>
    public int WaitForSending(int timeoutSec)
    {
        PersistBuffer();
        PersistMetrics();

        if (timeoutSec < 0) timeoutSec = 0;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        long timeoutMs = (long)timeoutSec * 1000;
        while (GetPendingCount() > 0)
        {
            if (sw.ElapsedMilliseconds >= timeoutMs) break;
            Thread.Sleep(100);
        }
        return GetPendingCount();
    }

    // ======== VERSION ========

    public string GetAppVersion() => _config.AppVersion;

    // ======== SAMPLING ========

    private static bool ShouldSample(double rate)
    {
        if (rate >= 1.0) return true;
        if (rate <= 0) return false;
        return Random.Shared.NextDouble() < rate;
    }

    // ======== EXCEPTION CAPTURE ========

    private void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        try
        {
            if (e.ExceptionObject is Exception ex)
            {
                var extraData = new Dictionary<string, object>
                {
                    ["exception_class"] = ex.GetType().FullName ?? ex.GetType().Name,
                    ["exception_source"] = "unhandled"
                };

                Log(LogLevel.Fatal, $"Unhandled exception: {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}",
                    "exception", extraData);

                PersistBuffer();
            }
        }
        catch { }
    }

    // ======== SHUTDOWN ========

    public void Shutdown()
    {
        if (_disposed) return;

        _logger.Log("SDK SHUTDOWN");
        AppDomain.CurrentDomain.UnhandledException -= OnUnhandledException;

        // Clear callbacks to prevent calls during shutdown
        OnError = null;
        OnLogsSent = null;
        OnDeviceInfoSent = null;
        OnCustomDeviceInfoSent = null;

        // Signal shipper thread to stop (it will do final persist & send)
        _shutdown = true;
        _shutdownEvent.Set();
        _shipperThread.Join(TimeSpan.FromSeconds(5));

        _sampler?.Dispose();
        _sampler = null;

        _httpClient.Dispose();
        _shutdownEvent.Dispose();
        _flushDoneEvent.Dispose();
        _disposed = true;
    }

    public void Dispose()
    {
        Shutdown();
    }
}
