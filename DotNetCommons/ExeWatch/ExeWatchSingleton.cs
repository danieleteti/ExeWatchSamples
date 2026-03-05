using ExeWatch.Config;
using ExeWatch.Models;

namespace ExeWatch;

/// <summary>
/// Static wrapper around ExeWatchClient providing a singleton pattern.
/// Use ExeWatch.Initialize() to create the global instance,
/// then call methods via ExeWatch.Info(), ExeWatch.Error(), etc.
/// </summary>
public static class ExeWatchSdk
{
    private static ExeWatchClient? _instance;
    private static readonly object Lock = new();

    public static bool IsInitialized
    {
        get { lock (Lock) return _instance != null; }
    }

    public static ExeWatchClient Instance
    {
        get
        {
            lock (Lock)
            {
                if (_instance == null)
                    throw new InvalidOperationException("ExeWatch is not initialized. Call ExeWatch.Initialize() first.");
                return _instance;
            }
        }
    }

    public static void Initialize(string apiKey, string customerId, string appVersion = "")
    {
        var config = new ExeWatchConfig(apiKey, customerId);
        if (!string.IsNullOrEmpty(appVersion))
            config.AppVersion = appVersion;
        Initialize(config);
    }

    public static void Initialize(ExeWatchConfig config)
    {
        lock (Lock)
        {
            if (_instance != null)
                throw new InvalidOperationException("ExeWatch is already initialized. Call Shutdown() first.");
            _instance = new ExeWatchClient(config);
        }
    }

    public static void Shutdown()
    {
        lock (Lock)
        {
            _instance?.Shutdown();
            _instance = null;
        }
    }

    // Logging
    public static void Log(LogLevel level, string message, string tag = "main", Dictionary<string, object>? extraData = null)
        => Instance.Log(level, message, tag, extraData);
    public static void Debug(string message, string tag = "main") => Instance.Debug(message, tag);
    public static void Info(string message, string tag = "main") => Instance.Info(message, tag);
    public static void Warning(string message, string tag = "main") => Instance.Warning(message, tag);
    public static void Error(string message, string tag = "main") => Instance.Error(message, tag);
    public static void Fatal(string message, string tag = "main") => Instance.Fatal(message, tag);
    public static void ErrorWithException(Exception ex, string tag = "main", string additionalMessage = "")
        => Instance.ErrorWithException(ex, tag, additionalMessage);

    // Breadcrumbs
    public static void AddBreadcrumb(BreadcrumbType type, string category, string message, Dictionary<string, object>? data = null)
        => Instance.AddBreadcrumb(type, category, message, data);
    public static void AddBreadcrumb(string message, string category = "custom")
        => Instance.AddBreadcrumb(message, category);
    public static List<Breadcrumb> GetBreadcrumbs() => Instance.GetBreadcrumbs();
    public static void ClearBreadcrumbs() => Instance.ClearBreadcrumbs();

    // User
    public static void SetUser(string id, string email = "", string name = "") => Instance.SetUser(id, email, name);
    public static void SetUser(UserIdentity user) => Instance.SetUser(user);
    public static void ClearUser() => Instance.ClearUser();
    public static UserIdentity? GetUser() => Instance.GetUser();

    // Customer
    public static void SetCustomerId(string customerId) => Instance.SetCustomerId(customerId);
    public static string GetCustomerId() => Instance.GetCustomerId();

    // Tags
    public static void SetTag(string key, string value) => Instance.SetTag(key, value);
    public static void SetTags(IEnumerable<KeyValuePair<string, string>> tags) => Instance.SetTags(tags);
    public static void RemoveTag(string key) => Instance.RemoveTag(key);
    public static void ClearTags() => Instance.ClearTags();
    public static Dictionary<string, string> GetTags() => Instance.GetTags();

    // Device Info
    public static void SendDeviceInfo() => Instance.SendDeviceInfo();
    public static void SetCustomDeviceInfo(string key, string value) => Instance.SetCustomDeviceInfo(key, value);
    public static void ClearCustomDeviceInfo(string key) => Instance.ClearCustomDeviceInfo(key);
    public static void ClearAllCustomDeviceInfo() => Instance.ClearAllCustomDeviceInfo();
    public static void SendCustomDeviceInfo() => Instance.SendCustomDeviceInfo();
    public static void SendCustomDeviceInfo(string key, string value) => Instance.SendCustomDeviceInfo(key, value);

    // Timing
    public static void StartTiming(string id, string tag = "", Dictionary<string, object>? metadata = null)
        => Instance.StartTiming(id, tag, metadata);
    public static double EndTiming(string id, Dictionary<string, object>? endMetadata = null, bool success = true)
        => Instance.EndTiming(id, endMetadata, success);
    public static double EndTiming() => Instance.EndTiming();
    public static bool IsTimingActive(string id) => Instance.IsTimingActive(id);
    public static void CancelTiming(string id) => Instance.CancelTiming(id);
    public static void CancelTiming() => Instance.CancelTiming();
    public static List<ActiveTimingInfo> GetActiveTimings() => Instance.GetActiveTimings();

    // Metrics
    public static void IncrementCounter(string name, double value = 1.0, string tag = "")
        => Instance.IncrementCounter(name, value, tag);
    public static void RecordGauge(string name, double value, string tag = "")
        => Instance.RecordGauge(name, value, tag);
    public static void RegisterPeriodicGauge(string name, Func<double> callback, string tag = "")
        => Instance.RegisterPeriodicGauge(name, callback, tag);
    public static void UnregisterPeriodicGauge(string name) => Instance.UnregisterPeriodicGauge(name);

    // Other
    public static void Flush() => Instance.Flush();
    public static int GetPendingCount() => Instance.GetPendingCount();
    public static string SessionId => Instance.SessionId;
    public static ExeWatchConfig Config => Instance.Config;
}
