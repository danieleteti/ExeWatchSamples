using System.Text.Json;
using ExeWatch.Models;

namespace ExeWatch.Serialization;

internal static class JsonPayloadBuilder
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = false
    };

    public static string BuildLogBatch(string customerId, DeviceInfo device, List<LogEvent> events)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);

        writer.WriteStartObject();
        writer.WriteString("customer_id", customerId);
        WriteDevice(writer, device);
        WriteEvents(writer, events);
        writer.WriteEndObject();
        writer.Flush();

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }

    public static string BuildDeviceInfo(string customerId, DeviceInfo device, HardwareInfo? hardware,
        Dictionary<string, string>? customDeviceInfo, string sessionId)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);

        writer.WriteStartObject();
        writer.WriteString("customer_id", customerId);
        WriteDevice(writer, device);

        if (hardware != null)
            WriteHardwareInfo(writer, hardware);

        if (customDeviceInfo != null && customDeviceInfo.Count > 0)
        {
            writer.WritePropertyName("custom_device_info");
            writer.WriteStartObject();
            foreach (var kvp in customDeviceInfo)
                writer.WriteString(kvp.Key, kvp.Value);
            writer.WriteEndObject();
        }

        if (!string.IsNullOrEmpty(sessionId))
            writer.WriteString("session_id", sessionId);

        writer.WriteEndObject();
        writer.Flush();

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }

    public static string BuildMetricsBatch(string customerId, DeviceInfo device, string sessionId,
        List<MetricAccumulator> metrics)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);

        writer.WriteStartObject();
        writer.WriteString("customer_id", customerId);
        WriteDevice(writer, device);
        writer.WriteString("session_id", sessionId);

        writer.WritePropertyName("metrics");
        writer.WriteStartArray();
        var now = DateTime.UtcNow;
        foreach (var m in metrics)
        {
            writer.WriteStartObject();
            writer.WriteString("name", m.Name);
            writer.WriteString("type", m.MetricType);
            writer.WriteNumber("value", m.Value);
            if (!string.IsNullOrEmpty(m.Tag))
                writer.WriteString("tag", m.Tag);
            if (m.MetricType == "gauge")
            {
                writer.WriteNumber("min", m.MinValue == double.MaxValue ? 0 : m.MinValue);
                writer.WriteNumber("max", m.MaxValue == double.MinValue ? 0 : m.MaxValue);
                writer.WriteNumber("avg", m.Avg);
            }
            writer.WriteNumber("count", m.SampleCount);
            writer.WriteString("period_start", m.PeriodStart.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"));
            writer.WriteString("period_end", now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"));
            writer.WriteEndObject();
        }
        writer.WriteEndArray();

        writer.WriteEndObject();
        writer.Flush();

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }

    private static void WriteDevice(Utf8JsonWriter writer, DeviceInfo device)
    {
        writer.WritePropertyName("device");
        writer.WriteStartObject();
        writer.WriteString("device_id", device.DeviceId);
        writer.WriteString("hostname", device.Hostname);
        writer.WriteString("username", device.Username);
        writer.WriteString("os_type", device.OsType);
        writer.WriteString("os_version", device.OsVersion);
        if (!string.IsNullOrEmpty(device.AppBinaryVersion))
            writer.WriteString("app_binary_version", device.AppBinaryVersion);
        if (!string.IsNullOrEmpty(device.AppVersion))
            writer.WriteString("app_version", device.AppVersion);
        writer.WriteString("sdk_version", device.SdkVersion);
        writer.WriteString("timezone_offset", device.TimezoneOffset);
        writer.WriteEndObject();
    }

    private static void WriteEvents(Utf8JsonWriter writer, List<LogEvent> events)
    {
        writer.WritePropertyName("events");
        writer.WriteStartArray();
        foreach (var evt in events)
        {
            writer.WriteStartObject();
            writer.WriteString("level", evt.Level.ToApiString());
            writer.WriteString("message", evt.Message);
            if (!string.IsNullOrEmpty(evt.Tag))
                writer.WriteString("tag", evt.Tag);
            writer.WriteString("timestamp", evt.Timestamp.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"));
            writer.WriteNumber("thread_id", evt.ThreadId);
            writer.WriteNumber("process_id", evt.ProcessId);
            if (!string.IsNullOrEmpty(evt.SessionId))
                writer.WriteString("session_id", evt.SessionId);
            if (evt.ExtraData != null && evt.ExtraData.Count > 0)
            {
                writer.WritePropertyName("extra_data");
                WriteExtraData(writer, evt.ExtraData);
            }
            writer.WriteEndObject();
        }
        writer.WriteEndArray();
    }

    private static void WriteExtraData(Utf8JsonWriter writer, Dictionary<string, object> data)
    {
        writer.WriteStartObject();
        foreach (var kvp in data)
        {
            writer.WritePropertyName(kvp.Key);
            WriteValue(writer, kvp.Value);
        }
        writer.WriteEndObject();
    }

    private static void WriteValue(Utf8JsonWriter writer, object? value)
    {
        switch (value)
        {
            case null:
                writer.WriteNullValue();
                break;
            case string s:
                writer.WriteStringValue(s);
                break;
            case bool b:
                writer.WriteBooleanValue(b);
                break;
            case int i:
                writer.WriteNumberValue(i);
                break;
            case long l:
                writer.WriteNumberValue(l);
                break;
            case double d:
                writer.WriteNumberValue(d);
                break;
            case float f:
                writer.WriteNumberValue(f);
                break;
            case decimal dec:
                writer.WriteNumberValue(dec);
                break;
            case Dictionary<string, object> dict:
                WriteExtraData(writer, dict);
                break;
            case List<Breadcrumb> breadcrumbs:
                writer.WriteStartArray();
                foreach (var bc in breadcrumbs)
                {
                    writer.WriteStartObject();
                    writer.WriteString("timestamp", bc.Timestamp.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"));
                    writer.WriteString("type", bc.Type.ToApiString());
                    writer.WriteString("category", bc.Category);
                    writer.WriteString("message", bc.Message);
                    if (bc.Data != null && bc.Data.Count > 0)
                    {
                        writer.WritePropertyName("data");
                        WriteExtraData(writer, bc.Data);
                    }
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
                break;
            default:
                writer.WriteStringValue(value.ToString());
                break;
        }
    }

    private static void WriteHardwareInfo(Utf8JsonWriter writer, HardwareInfo hw)
    {
        writer.WritePropertyName("hardware_info");
        writer.WriteStartObject();

        writer.WriteNumber("total_physical_memory", hw.TotalPhysicalMemory);
        writer.WriteNumber("available_physical_memory", hw.AvailablePhysicalMemory);
        if (!string.IsNullOrEmpty(hw.CpuName))
            writer.WriteString("cpu_name", hw.CpuName);
        writer.WriteNumber("cpu_cores", hw.CpuCores);
        writer.WriteNumber("cpu_logical_processors", hw.CpuLogicalProcessors);
        writer.WriteString("cpu_architecture", hw.CpuArchitecture);

        // Disks
        writer.WritePropertyName("disks");
        writer.WriteStartArray();
        foreach (var disk in hw.Disks)
        {
            writer.WriteStartObject();
            writer.WriteString("drive", disk.Drive);
            writer.WriteString("volume_name", disk.VolumeName);
            writer.WriteString("file_system", disk.FileSystem);
            writer.WriteNumber("total_bytes", disk.TotalBytes);
            writer.WriteNumber("free_bytes", disk.FreeBytes);
            writer.WriteString("drive_type", disk.DriveType);
            writer.WriteEndObject();
        }
        writer.WriteEndArray();

        // Monitors
        writer.WritePropertyName("monitors");
        writer.WriteStartArray();
        foreach (var mon in hw.Monitors)
        {
            writer.WriteStartObject();
            writer.WriteNumber("index", mon.Index);
            writer.WriteString("name", mon.Name);
            writer.WriteNumber("width", mon.Width);
            writer.WriteNumber("height", mon.Height);
            writer.WriteNumber("bits_per_pixel", mon.BitsPerPixel);
            writer.WriteBoolean("primary", mon.Primary);
            writer.WriteEndObject();
        }
        writer.WriteEndArray();

        if (!string.IsNullOrEmpty(hw.ExecutablePath))
            writer.WriteString("executable_path", hw.ExecutablePath);
        if (!string.IsNullOrEmpty(hw.WorkingDirectory))
            writer.WriteString("working_directory", hw.WorkingDirectory);
        if (!string.IsNullOrEmpty(hw.CommandLine))
            writer.WriteString("command_line", hw.CommandLine);
        if (hw.SystemBootTime.HasValue)
            writer.WriteString("system_boot_time", hw.SystemBootTime.Value.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"));

        writer.WritePropertyName("local_ip_addresses");
        writer.WriteStartArray();
        foreach (var ip in hw.LocalIpAddresses)
            writer.WriteStringValue(ip);
        writer.WriteEndArray();

        if (!string.IsNullOrEmpty(hw.Timezone))
            writer.WriteString("timezone", hw.Timezone);
        if (!string.IsNullOrEmpty(hw.SystemLanguage))
            writer.WriteString("system_language", hw.SystemLanguage);
        if (!string.IsNullOrEmpty(hw.SystemLocale))
            writer.WriteString("system_locale", hw.SystemLocale);
        if (!string.IsNullOrEmpty(hw.RuntimeVersion))
            writer.WriteString("runtime_version", hw.RuntimeVersion);

        writer.WriteEndObject();
    }

    public static Config.ServerConfig? ParseServerConfig(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (!root.TryGetProperty("config", out var configEl))
                return null;

            var config = new Config.ServerConfig();

            if (configEl.TryGetProperty("version", out var v))
                config.Version = v.GetInt32();
            if (configEl.TryGetProperty("flush_interval_ms", out var fi))
                config.FlushIntervalMs = fi.GetInt32();
            if (configEl.TryGetProperty("batch_size", out var bs))
                config.BatchSize = bs.GetInt32();
            if (configEl.TryGetProperty("sampling_rate", out var sr))
                config.SamplingRate = sr.GetDouble();
            if (configEl.TryGetProperty("max_message_length", out var mml))
                config.MaxMessageLength = mml.GetInt32();
            if (configEl.TryGetProperty("min_level", out var ml))
                config.MinLevel = LogLevelExtensions.FromApiString(ml.GetString() ?? "debug");
            if (configEl.TryGetProperty("enabled", out var en))
                config.Enabled = en.GetBoolean();

            return config;
        }
        catch
        {
            return null;
        }
    }

    public static (int accepted, int rejected) ParseIngestResponse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            int accepted = root.TryGetProperty("accepted", out var a) ? a.GetInt32() : 0;
            int rejected = root.TryGetProperty("rejected", out var r) ? r.GetInt32() : 0;
            return (accepted, rejected);
        }
        catch
        {
            return (0, 0);
        }
    }
}
