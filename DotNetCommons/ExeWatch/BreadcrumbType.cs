namespace ExeWatch;

public enum BreadcrumbType
{
    Click,
    Navigation,
    Http,
    Console,
    Custom,
    Error,
    Query,
    Transaction,
    User,
    System,
    File,
    State,
    Form,
    Config,
    Message,
    Debug
}

public static class BreadcrumbTypeExtensions
{
    private static readonly string[] Names =
    [
        "click", "navigation", "http", "console", "custom", "error",
        "query", "transaction", "user", "system", "file", "state",
        "form", "config", "message", "debug"
    ];

    public static string ToApiString(this BreadcrumbType type) => Names[(int)type];
}
