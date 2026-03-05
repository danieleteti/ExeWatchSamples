namespace ExeWatch;

public enum LogLevel
{
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
    Fatal = 4
}

public static class LogLevelExtensions
{
    private static readonly string[] Names = ["debug", "info", "warning", "error", "fatal"];

    public static string ToApiString(this LogLevel level) => Names[(int)level];

    public static LogLevel FromApiString(string value) => value.ToLowerInvariant() switch
    {
        "debug" => LogLevel.Debug,
        "info" => LogLevel.Info,
        "warning" => LogLevel.Warning,
        "error" => LogLevel.Error,
        "fatal" => LogLevel.Fatal,
        _ => LogLevel.Debug
    };
}
