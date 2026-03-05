using ExeWatch;
using ExeWatch.Config;

namespace DotNetWindowsService;

/// <summary>
/// Background worker that demonstrates ExeWatch SDK integration in a Windows Service.
///
/// This sample shows how to properly use ExeWatch in a long-running service:
///   - Initialize the SDK once at service startup
///   - Use timing with try/catch in each work cycle
///   - Record metrics for monitoring
///   - Shut down the SDK gracefully when the service stops
///
/// The worker runs a periodic processing cycle every 10 seconds, simulating
/// a typical service pattern (fetch data, process it, record metrics).
/// </summary>
public class Worker : BackgroundService
{
    // Replace with your actual API key from the ExeWatch dashboard
    private const string ApiKey = "ew_win_YOUR_API_KEY_HERE";
    private const string CustomerId = "DEMO-CUSTOMER";

    private readonly ILogger<Worker> _logger;
    private int _cycleCount;

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Called once when the service starts.
    /// This is the right place to initialize the ExeWatch SDK.
    /// </summary>
    public override Task StartAsync(CancellationToken cancellationToken)
    {
        if (ApiKey == "ew_win_YOUR_API_KEY_HERE")
        {
            _logger.LogCritical("You must set your API key before running this sample. " +
                "Open Worker.cs and replace \"ew_win_YOUR_API_KEY_HERE\" with your actual API key. " +
                "You can find your API key in the ExeWatch dashboard: https://exewatch.com");
            throw new InvalidOperationException(
                "ExeWatch API key not configured. Edit Worker.cs and set your API key.");
        }

        // Initialize the SDK with your API key and customer ID.
        // AppVersion helps you track which version of the service is running
        // across different machines in the ExeWatch dashboard.
        var config = new ExeWatchConfig(ApiKey, CustomerId)
        {
            AppVersion = "1.0.0-service-demo"
        };

        ExeWatchSdk.Initialize(config);

        // Global tags are attached to EVERY log entry sent by this service.
        // Use them to identify the service and environment.
        EW.SetTag("service_name", "ExeWatchDemoService");
        EW.SetTag("environment", "development");

        // Send hardware info (CPU, RAM, OS, etc.) to the dashboard.
        // This is typically done once at startup.
        EW.SendDeviceInfo();

        EW.Info("Service started", "lifecycle");
        _logger.LogInformation("ExeWatch Demo Service started");

        return base.StartAsync(cancellationToken);
    }

    /// <summary>
    /// Main service loop. Runs until the service is stopped.
    /// Each cycle processes a batch of work with full ExeWatch instrumentation.
    /// </summary>
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Worker running");

        while (!stoppingToken.IsCancellationRequested)
        {
            _cycleCount++;
            await ProcessCycleAsync(_cycleCount, stoppingToken);

            // Wait 10 seconds before the next cycle
            await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }
    }

    /// <summary>
    /// A single processing cycle. Demonstrates the recommended pattern for
    /// timing service operations with ExeWatch:
    ///
    ///   EW.StartTiming("operation_id");
    ///   try
    ///   {
    ///       // ... do work ...
    ///       EW.EndTiming("operation_id");               // success
    ///   }
    ///   catch (Exception ex)
    ///   {
    ///       EW.EndTiming("operation_id",
    ///           new Dictionary&lt;string, object&gt; { ["error"] = ex.Message }, false);  // failure
    ///       // handle or re-throw
    ///   }
    ///
    /// Note how nested timings work: each sub-operation (fetch_data, transform_data)
    /// is timed independently within the outer process_cycle timing.
    /// </summary>
    private async Task ProcessCycleAsync(int cycle, CancellationToken ct)
    {
        // Breadcrumbs provide context if something goes wrong during this cycle
        EW.AddBreadcrumb($"Starting cycle {cycle}", "worker");

        // Time the entire cycle
        EW.StartTiming("process_cycle", "worker");
        try
        {
            // --- Sub-operation 1: Fetch data from database ---
            // Each sub-operation gets its own timing, so you can see
            // exactly which part is slow in the ExeWatch Timing page.
            EW.StartTiming("fetch_data", "database");
            try
            {
                // Simulate a database query (50-300ms)
                await Task.Delay(Random.Shared.Next(50, 300), ct);

                // Simulate occasional database errors (10% chance)
                if (Random.Shared.Next(10) == 0)
                    throw new InvalidOperationException("Database connection timeout");

                // Success: close the timing normally
                EW.EndTiming("fetch_data");
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Failure: close the timing with the error and success = false
                EW.EndTiming("fetch_data",
                    new Dictionary<string, object> { ["error"] = ex.Message }, false);
                throw; // re-throw so the outer catch handles it
            }

            // --- Sub-operation 2: Transform/process the data ---
            EW.StartTiming("transform_data", "processing");
            try
            {
                var itemCount = Random.Shared.Next(10, 100);

                // Simulate processing time (100-500ms)
                await Task.Delay(Random.Shared.Next(100, 500), ct);

                // Record metrics for this batch.
                // Counters accumulate: the dashboard shows total items/sec.
                // Gauges show point-in-time values: the dashboard shows min/max/avg.
                EW.IncrementCounter("items_processed", itemCount);
                EW.RecordGauge("batch_size", itemCount, "worker");

                // Success
                EW.EndTiming("transform_data");
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                EW.EndTiming("transform_data",
                    new Dictionary<string, object> { ["error"] = ex.Message }, false);
                throw;
            }

            // Outer timing: success (all sub-operations completed)
            EW.EndTiming("process_cycle");

            EW.Debug($"Cycle {cycle} completed", "worker");
            _logger.LogInformation("Cycle {Cycle} completed", cycle);
        }
        catch (OperationCanceledException)
        {
            // Service is shutting down — mark the cycle as cancelled
            EW.EndTiming("process_cycle",
                new Dictionary<string, object> { ["reason"] = "cancelled" }, false);
            throw; // let the framework handle the shutdown
        }
        catch (Exception ex)
        {
            // A sub-operation failed — the cycle timing is marked as failed
            EW.EndTiming("process_cycle",
                new Dictionary<string, object> { ["error"] = ex.Message }, false);

            // Log the error (will appear in the ExeWatch Logs page)
            EW.Error($"Cycle {cycle} failed: {ex.Message}", "worker");
            _logger.LogError(ex, "Cycle {Cycle} failed", cycle);

            // Don't re-throw: let the service continue to the next cycle.
            // In a real service, you might add a backoff delay here.
        }
    }

    /// <summary>
    /// Called once when the service is stopping.
    /// Always shut down the SDK here to flush remaining logs.
    /// </summary>
    public override Task StopAsync(CancellationToken cancellationToken)
    {
        EW.Info($"Service stopping after {_cycleCount} cycles", "lifecycle");
        _logger.LogInformation("Service stopping after {Cycles} cycles", _cycleCount);

        // Shutdown flushes all pending logs to the server.
        // Without this call, the last batch of logs might be lost.
        ExeWatchSdk.Shutdown();

        return base.StopAsync(cancellationToken);
    }
}
