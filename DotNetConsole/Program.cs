using ExeWatch;
using ExeWatch.Config;

// ============================================================
//  ExeWatch .NET SDK — Console Application Sample
// ============================================================
//
//  This sample demonstrates how to integrate ExeWatch into a
//  .NET console application. It covers all major SDK features:
//
//    1. SDK initialization and graceful shutdown
//    2. All log levels (Debug, Info, Warning, Error, Fatal)
//    3. Performance timing with try/catch pattern
//       - Success: EndTiming(id)               → success = true
//       - Exception: EndTiming(id, data, false) → records the error
//    4. User identity and global tags
//    5. Breadcrumbs for error context
//    6. Custom metrics (counters and gauges)
//    7. Custom device info
//
//  Prerequisites:
//    - .NET 8.0 or later
//    - Add a project reference to the ExeWatch SDK
//    - Replace the API key below with your own (from the ExeWatch dashboard)
//
// ============================================================

const string ApiKey = "ew_win_YOUR_API_KEY_HERE";
const string CustomerId = "DEMO-CUSTOMER";

// -------------------------------------------------------
// 1. INITIALIZE THE SDK
//    The SDK must be initialized before any logging call.
//    Provide your API key and a customer identifier.
//    AppVersion is optional but recommended for tracking.
// -------------------------------------------------------
if (ApiKey == "ew_win_YOUR_API_KEY_HERE")
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine("ERROR: You must set your API key before running this sample.");
    Console.WriteLine("Open Program.cs and replace \"ew_win_YOUR_API_KEY_HERE\" with your actual API key.");
    Console.WriteLine("You can find your API key in the ExeWatch dashboard: https://exewatch.com");
    Console.ResetColor();
    Console.WriteLine("\nPress any key to exit.");
    Console.ReadKey();
    return;
}

var config = new ExeWatchConfig(ApiKey, CustomerId)
{
    AppVersion = "1.0.0-console-demo"
};

ExeWatchSdk.Initialize(config);
Console.WriteLine("ExeWatch SDK initialized.");

// -------------------------------------------------------
// 2. SET USER IDENTITY
//    Identifies the current user across all log entries.
//    Useful for correlating logs to a specific person.
// -------------------------------------------------------
EW.SetUser("user_42", "john@acme.com", "John Doe");

// -------------------------------------------------------
// 3. SET GLOBAL TAGS
//    Key-value pairs attached to every log entry.
//    Use them for environment, module, region, etc.
// -------------------------------------------------------
EW.SetTag("environment", "development");
EW.SetTag("module", "console-demo");

// -------------------------------------------------------
// 4. BASIC LOGGING
//    Five log levels are available: Debug, Info, Warning,
//    Error, and Fatal. Each takes a message and an
//    optional tag to categorize the log.
// -------------------------------------------------------
EW.Debug("Application starting up", "startup");
EW.Info("Configuration loaded successfully", "config");
EW.Warning("Cache directory not found, using temp", "cache");

// -------------------------------------------------------
// 5. BREADCRUMBS
//    Breadcrumbs record a trail of user/system actions.
//    When an error occurs, the breadcrumbs are attached
//    to give context about what led to the failure.
// -------------------------------------------------------
EW.AddBreadcrumb("Loaded config from appsettings.json", "config");
EW.AddBreadcrumb("Connected to database", "database");
EW.AddBreadcrumb("Started background job scheduler", "jobs");

// -------------------------------------------------------
// 6. PERFORMANCE TIMING
//    Wrap your operation in a try/catch block:
//      - On success: call EndTiming(id)
//      - On exception: call EndTiming(id, errorData, false)
//    This lets ExeWatch track both duration AND success rate.
//
//    We run multiple iterations so the ExeWatch dashboard can
//    compute meaningful statistics: Avg, Min, Max, P95, Count,
//    and Success Rate. With a single execution you'd only see
//    one data point — the real value of timing comes from
//    observing patterns across many calls.
// -------------------------------------------------------
const int TimingIterations = 20;
Console.WriteLine($"\nRunning {TimingIterations} simulated database queries...");

for (int i = 1; i <= TimingIterations; i++)
{
    EW.StartTiming("database_query", "database");
    try
    {
        // Simulate variable query times (50-500ms) to produce
        // a realistic spread of durations in the dashboard.
        Thread.Sleep(Random.Shared.Next(50, 500));

        // Simulate occasional failures (15% chance) so the
        // dashboard shows a meaningful Success Rate.
        if (Random.Shared.Next(100) < 15)
            throw new TimeoutException("Connection timed out");

        // Success: EndTiming with just the ID (success = true by default)
        EW.EndTiming("database_query");
        Console.WriteLine($"  Query {i}/{TimingIterations}: OK");
    }
    catch (Exception ex)
    {
        // Failure: EndTiming with error metadata and success = false.
        // The timing duration is still recorded, so you can see how long
        // the operation ran before it failed.
        EW.EndTiming("database_query",
            new Dictionary<string, object> { ["error"] = ex.Message }, false);
        EW.Error($"Query {i} failed: {ex.Message}", "database");
        Console.WriteLine($"  Query {i}/{TimingIterations}: FAILED - {ex.Message}");
    }
}

Console.WriteLine("  Check the Timing page in the dashboard to see Avg, Min, Max, P95, and Success Rate.");

// -------------------------------------------------------
// 7. CUSTOM METRICS
//    Counters accumulate values over time (e.g., items
//    processed, bytes transferred). Gauges record a
//    point-in-time value (e.g., memory usage, queue depth).
// -------------------------------------------------------
Console.WriteLine("\nRecording metrics...");

// Counters: accumulate values, flushed as a single rollup
EW.IncrementCounter("items_processed", 150);
EW.IncrementCounter("items_processed", 75, "batch_A");  // with tag

// Gauges: snapshot values (min/max/avg tracked automatically)
EW.RecordGauge("memory_mb", Environment.WorkingSet / 1024.0 / 1024.0, "system");
EW.RecordGauge("thread_count", Environment.ProcessorCount, "system");

Console.WriteLine("  Counters and gauges recorded.");

// -------------------------------------------------------
// 9. CUSTOM DEVICE INFO
//    Send additional key-value pairs alongside the
//    standard hardware info (CPU, RAM, OS, etc.).
//    Useful for license type, deployment mode, etc.
// -------------------------------------------------------
Console.WriteLine("Sending custom device info...");

EW.SetCustomDeviceInfo("license_type", "evaluation");
EW.SetCustomDeviceInfo("deployment", "standalone");
EW.SendCustomDeviceInfo();

Console.WriteLine("  Custom device info queued.");

// -------------------------------------------------------
// 10. SHUTDOWN
//     Always shut down the SDK before exiting. This
//     flushes any remaining logs to the server.
// -------------------------------------------------------
EW.Info("Console demo completed successfully", "startup");
Console.WriteLine("\nAll done. Shutting down SDK...");

ExeWatchSdk.Shutdown();
Console.WriteLine("SDK shut down. Press any key to exit.");
Console.ReadKey();
