using ExeWatch.Config;
using ExeWatch.Models;

namespace ExeWatch;

/// <summary>
/// Short alias for ExeWatchSdk. Provides the same API with a concise name.
/// Usage: EW.Info("message", "tag");
/// </summary>
public static class EW
{
    public static bool IsInitialized => ExeWatchSdk.IsInitialized;
    public static ExeWatchClient Instance => ExeWatchSdk.Instance;

    // Logging
    public static void Log(LogLevel level, string message, string tag = "main", Dictionary<string, object>? extraData = null)
        => ExeWatchSdk.Log(level, message, tag, extraData);
    public static void Debug(string message, string tag = "main") => ExeWatchSdk.Debug(message, tag);
    public static void Info(string message, string tag = "main") => ExeWatchSdk.Info(message, tag);
    public static void Warning(string message, string tag = "main") => ExeWatchSdk.Warning(message, tag);
    public static void Error(string message, string tag = "main") => ExeWatchSdk.Error(message, tag);
    public static void Fatal(string message, string tag = "main") => ExeWatchSdk.Fatal(message, tag);
    public static void ErrorWithException(Exception ex, string tag = "main", string additionalMessage = "")
        => ExeWatchSdk.ErrorWithException(ex, tag, additionalMessage);

    // Breadcrumbs
    public static void AddBreadcrumb(BreadcrumbType type, string category, string message, Dictionary<string, object>? data = null)
        => ExeWatchSdk.AddBreadcrumb(type, category, message, data);
    public static void AddBreadcrumb(string message, string category = "custom")
        => ExeWatchSdk.AddBreadcrumb(message, category);
    public static List<Breadcrumb> GetBreadcrumbs() => ExeWatchSdk.GetBreadcrumbs();
    public static void ClearBreadcrumbs() => ExeWatchSdk.ClearBreadcrumbs();

    // User
    public static void SetUser(string id, string email = "", string name = "") => ExeWatchSdk.SetUser(id, email, name);
    public static void SetUser(UserIdentity user) => ExeWatchSdk.SetUser(user);
    public static void ClearUser() => ExeWatchSdk.ClearUser();
    public static UserIdentity? GetUser() => ExeWatchSdk.GetUser();

    // Customer
    public static void SetCustomerId(string customerId) => ExeWatchSdk.SetCustomerId(customerId);
    public static string GetCustomerId() => ExeWatchSdk.GetCustomerId();

    // Tags
    public static void SetTag(string key, string value) => ExeWatchSdk.SetTag(key, value);
    public static void SetTags(IEnumerable<KeyValuePair<string, string>> tags) => ExeWatchSdk.SetTags(tags);
    public static void RemoveTag(string key) => ExeWatchSdk.RemoveTag(key);
    public static void ClearTags() => ExeWatchSdk.ClearTags();
    public static Dictionary<string, string> GetTags() => ExeWatchSdk.GetTags();

    // Device Info
    public static void SendDeviceInfo() => ExeWatchSdk.SendDeviceInfo();
    public static void SetCustomDeviceInfo(string key, string value) => ExeWatchSdk.SetCustomDeviceInfo(key, value);
    public static void ClearCustomDeviceInfo(string key) => ExeWatchSdk.ClearCustomDeviceInfo(key);
    public static void ClearAllCustomDeviceInfo() => ExeWatchSdk.ClearAllCustomDeviceInfo();
    public static void SendCustomDeviceInfo() => ExeWatchSdk.SendCustomDeviceInfo();
    public static void SendCustomDeviceInfo(string key, string value) => ExeWatchSdk.SendCustomDeviceInfo(key, value);

    // Timing
    public static void StartTiming(string id, string tag = "", Dictionary<string, object>? metadata = null)
        => ExeWatchSdk.StartTiming(id, tag, metadata);
    public static double EndTiming(string id, Dictionary<string, object>? endMetadata = null, bool success = true)
        => ExeWatchSdk.EndTiming(id, endMetadata, success);
    public static double EndTiming() => ExeWatchSdk.EndTiming();
    public static bool IsTimingActive(string id) => ExeWatchSdk.IsTimingActive(id);
    public static void CancelTiming(string id) => ExeWatchSdk.CancelTiming(id);
    public static void CancelTiming() => ExeWatchSdk.CancelTiming();
    public static List<ActiveTimingInfo> GetActiveTimings() => ExeWatchSdk.GetActiveTimings();

    // Metrics
    public static void IncrementCounter(string name, double value = 1.0, string tag = "")
        => ExeWatchSdk.IncrementCounter(name, value, tag);
    public static void RecordGauge(string name, double value, string tag = "")
        => ExeWatchSdk.RecordGauge(name, value, tag);
    public static void RegisterPeriodicGauge(string name, Func<double> callback, string tag = "")
        => ExeWatchSdk.RegisterPeriodicGauge(name, callback, tag);
    public static void UnregisterPeriodicGauge(string name) => ExeWatchSdk.UnregisterPeriodicGauge(name);

    // Other
    public static void Flush() => ExeWatchSdk.Flush();
    public static int GetPendingCount() => ExeWatchSdk.GetPendingCount();
    public static string SessionId => ExeWatchSdk.SessionId;
    public static ExeWatchConfig Config => ExeWatchSdk.Config;
}
