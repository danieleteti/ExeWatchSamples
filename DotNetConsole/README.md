# ExeWatch — .NET Console Sample

A console application that demonstrates all major ExeWatch SDK features for .NET. It runs through each feature sequentially — including 20 timed iterations to generate meaningful Avg/Min/Max/P95 statistics in the dashboard.

## Requirements

- .NET 8.0 or later
- Visual Studio 2022 (17.8+) or JetBrains Rider 2024.1+

## Step-by-step

**Step 1** — Open `DotNetConsole.csproj` in Visual Studio.

**Step 2** — Open `Program.cs` and replace `ew_win_YOUR_API_KEY_HERE` with your API key (from [exewatch.com](https://exewatch.com)).

**Step 3** — Press F5 to run. The app will:

- Initialize the SDK and set user identity / global tags
- Log messages at various severity levels
- Add breadcrumbs for error context
- Run 20 simulated database queries with try/catch timing (some will fail randomly, so the dashboard shows a realistic success rate)
- Record counters and gauges
- Send custom device info

**Step 4** — Open the ExeWatch dashboard to see logs, timings (with Avg/Min/Max/P95/Count), and metrics.

## How it works

The sample references the SDK via project reference to `../DotNetCommons/ExeWatch/`. After calling `ExeWatchSdk.Initialize(config)`, the global `EW` shortcut is available:

```csharp
// Logging
EW.Debug("Loading configuration", "config");
EW.Info("User logged in", "auth");
EW.Error("Payment failed", "billing");

// Breadcrumbs (context trail before errors)
EW.AddBreadcrumb("User clicked Save", "ui");

// Timing with try/catch — the recommended pattern
EW.StartTiming("database_query", "database");
try
{
    var results = RunQuery(sql);
    EW.EndTiming("database_query");                    // success
}
catch (Exception ex)
{
    EW.EndTiming("database_query",
        new Dictionary<string, object> { ["error"] = ex.Message }, false);  // failure
    throw;
}

// User identity
EW.SetUser("user-123", "john@example.com", "John Doe");

// Tags
EW.SetTag("environment", "production");

// Metrics
EW.IncrementCounter("page_views");
EW.RecordGauge("active_sessions", 42);
```
