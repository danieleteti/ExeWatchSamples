using ExeWatch;
using ExeWatch.Config;

namespace ExeWatchWindowsForms;

public partial class MainForm : Form
{
    private int _simulatedMajor = 1;
    private int _simulatedMinor;

    public MainForm()
    {
        InitializeComponent();
    }

    private void MainForm_Load(object? sender, EventArgs e)
    {
        edtApiKey.Text = "<Put your ExeWatch application key here>";
        edtCustomerId.Text = "DEMO-CUSTOMER";
        edtMessage.Text = "Test log message";
        edtTag.Text = "DEMO";
        edtCustomKey.Text = "license_type";
        edtCustomValue.Text = "evaluation";

        UpdateUI();
        UILog("ExeWatch .NET Demo started");
        UILog($"SDK Version: {Constants.SdkVersion}");
        UILog($"API Version: {Constants.ApiVersion}");
    }

    private void MainForm_FormClosing(object? sender, FormClosingEventArgs e)
    {
        if (ExeWatchSdk.IsInitialized)
            ExeWatchSdk.Shutdown();
    }

    // ======== UI HELPERS ========

    private void UILog(string message)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => UILog(message));
            return;
        }

        txtLog.AppendText($"[{DateTime.Now:HH:mm:ss.fff}] {message}{Environment.NewLine}");
    }

    private void UpdateUI()
    {
        bool connected = ExeWatchSdk.IsInitialized;

        btnUse.Enabled = !connected;
        btnDisconnect.Enabled = connected;
        tcFeatures.Enabled = connected;
        edtApiKey.Enabled = !connected;
        edtCustomerId.Enabled = !connected;

        if (connected)
        {
            lblStatus.Text = "Status: Connected";
            lblStatus.ForeColor = Color.Green;
        }
        else
        {
            lblStatus.Text = "Status: Disconnected";
            lblStatus.ForeColor = Color.Gray;
        }

        lblCurrentVersion.Text = $"Current simulated version: {_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen";
    }

    // ======== CONNECTION ========

    private void BtnUse_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(edtApiKey.Text))
        {
            MessageBox.Show("Please enter an API Key");
            edtApiKey.Focus();
            return;
        }

        if (string.IsNullOrWhiteSpace(edtCustomerId.Text))
        {
            MessageBox.Show("Please enter a Customer ID");
            edtCustomerId.Focus();
            return;
        }

        UILog("Connecting to ExeWatch...");

        var config = new ExeWatchConfig(edtApiKey.Text.Trim(), edtCustomerId.Text.Trim())
        {
            AppVersion = $"{_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen",
            SampleRate = 1.0
        };

        try
        {
            ExeWatchSdk.Initialize(config);
        }
        catch (Exception ex)
        {
            UILog($"ERROR: {ex.Message}");
            return;
        }

        // Set up callbacks
        EW.Instance.OnError = msg => UILog($"ERROR: {msg}");
        EW.Instance.OnLogsSent = (accepted, rejected) =>
            UILog($"Logs sent - Accepted: {accepted}, Rejected: {rejected}");
        EW.Instance.OnDeviceInfoSent = (success, error) =>
        {
            if (success) UILog("Device info sent successfully");
            else UILog($"Device info send failed: {error}");
        };

        // Set user identity
        EW.SetUser("user_123", "demo@example.com", "Demo User");
        UILog("User identity set: Demo User (demo@example.com)");

        // Set global tags
        EW.SetTag("environment", "demo");
        EW.SetTag("app_name", "ExeWatch .NET Demo");
        UILog("Global tags set: environment=demo, app_name=ExeWatch .NET Demo");

        // Send device info
        EW.SendDeviceInfo();

        UILog("SDK initialized successfully");
        UILog($"Customer ID: {config.CustomerId}");
        UILog($"AppVersion: {config.AppVersion}");

        UpdateUI();
    }

    private void BtnDisconnect_Click(object? sender, EventArgs e)
    {
        if (ExeWatchSdk.IsInitialized)
        {
            UILog("Disconnecting...");
            ExeWatchSdk.Shutdown();
            UILog("Disconnected");
        }
        UpdateUI();
    }

    // ======== LOGGING ========

    private void BtnDebug_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.Debug(edtMessage.Text, edtTag.Text);
        UILog($"Logged DEBUG: {edtMessage.Text}");
    }

    private void BtnInfo_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.Info(edtMessage.Text, edtTag.Text);
        UILog($"Logged INFO: {edtMessage.Text}");
    }

    private void BtnWarning_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.Warning(edtMessage.Text, edtTag.Text);
        UILog($"Logged WARNING: {edtMessage.Text}");
    }

    private void BtnError_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.Error(edtMessage.Text, edtTag.Text);
        UILog($"Logged ERROR: {edtMessage.Text}");
    }

    private void BtnFatal_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.Fatal(edtMessage.Text, edtTag.Text);
        UILog($"Logged FATAL: {edtMessage.Text}");
    }

    private void BtnGenerateLogs_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("Generating sample logs with breadcrumbs...");

        EW.AddBreadcrumb("User clicked \"Start Process\"", "ui");
        EW.AddBreadcrumb(BreadcrumbType.Navigation, "navigation", "Navigated to Settings page");
        EW.Info("Application started", "STARTUP");

        EW.AddBreadcrumb("User opened configuration dialog", "ui");
        EW.Debug("Loading configuration from registry", "CONFIG");

        EW.AddBreadcrumb(BreadcrumbType.Http, "api", "POST /api/login - 200 OK");
        EW.Info("User logged in: demo_user", "AUTH");

        EW.AddBreadcrumb("Database connection initiated", "system");
        EW.Debug("Connecting to database...", "DATABASE");
        EW.Info("Database connection established", "DATABASE");

        for (int i = 1; i <= 5; i++)
        {
            EW.AddBreadcrumb($"Processing batch item {i}", "batch");
            EW.Debug($"Processing item {i} of 5", "BATCH");
            Thread.Sleep(10);
        }

        EW.AddBreadcrumb("Memory check triggered", "system");
        EW.Warning("Memory usage above 80%", "SYSTEM");
        EW.Info("Batch processing completed successfully", "BATCH");

        EW.AddBreadcrumb(BreadcrumbType.Http, "api", "POST /api/email/send - 500 Error");
        EW.Error("Failed to send email notification", "EMAIL");
        UILog($"ERROR logged with breadcrumbs attached");

        EW.ClearBreadcrumbs();
        EW.Info("Application running normally", "STATUS");

        UILog("Generated 12 sample log entries with breadcrumbs");
    }

    private void BtnTestException_Click(object? sender, EventArgs e)
    {
        UILog("Raising test exception...");
        UILog("The exception will be captured by ExeWatchWinForms hook");
        throw new Exception("Test exception - automatically captured by ExeWatch!");
    }

    // ======== TIMING ========

    private void BtnTimingNested_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Nested Timing Test ---");
        EW.StartTiming("LoadData", "io");
        UILog("Started \"LoadData\" timing");
        Thread.Sleep(Random.Shared.Next(100, 600));

        EW.StartTiming("DatabaseQuery", "database");
        UILog("Started nested \"DatabaseQuery\" timing");
        Thread.Sleep(Random.Shared.Next(100, 600));

        double innerMs = EW.EndTiming("DatabaseQuery");
        UILog($"Ended \"DatabaseQuery\": {innerMs:F2}ms");
        Thread.Sleep(Random.Shared.Next(50, 100));

        double outerMs = EW.EndTiming("LoadData");
        UILog($"Ended \"LoadData\": {outerMs:F2}ms");
        UILog("Nested timing test complete");
    }

    private void BtnTimingParallel_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Parallel Timing Test ---");
        EW.StartTiming("Download", "network");
        UILog("Started \"Download\" timing");
        EW.StartTiming("Process", "cpu");
        UILog("Started \"Process\" timing");

        Thread.Sleep(50);
        double downloadMs = EW.EndTiming("Download");
        UILog($"Ended \"Download\": {downloadMs:F2}ms");

        Thread.Sleep(75);
        double processMs = EW.EndTiming("Process", success: Random.Shared.Next(10) > 5);
        UILog($"Ended \"Process\": {processMs:F2}ms");
        UILog("Parallel timing test complete");
    }

    private void BtnTimingLIFO_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- LIFO EndTiming() Test ---");

        EW.StartTiming("First");
        UILog("Started \"First\"");
        Thread.Sleep(30);

        EW.StartTiming("Second");
        UILog("Started \"Second\"");
        Thread.Sleep(30);

        EW.StartTiming("Third");
        UILog("Started \"Third\"");
        Thread.Sleep(30);

        double ms = EW.EndTiming();
        UILog($"EndTiming() closed last: {ms:F2}ms (should be \"Third\")");

        ms = EW.EndTiming();
        UILog($"EndTiming() closed last: {ms:F2}ms (should be \"Second\")");

        ms = EW.EndTiming();
        UILog($"EndTiming() closed last: {ms:F2}ms (should be \"First\")");

        ms = EW.EndTiming();
        UILog($"EndTiming() on empty stack: {ms:F2} (should be -1)");
        UILog("LIFO test complete");
    }

    private void BtnTimingFormat_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Format-style ID Test ---");
        int queryId = 12345;

        EW.StartTiming($"Query_{queryId}", "database");
        UILog($"Started \"Query_{queryId}\"");
        Thread.Sleep(50);

        double ms = EW.EndTiming($"Query_{queryId}");
        UILog($"Ended \"Query_{queryId}\": {ms:F2}ms");
        UILog("Format-style ID test complete");
    }

    private void BtnTimingWithMeta_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Timing with Metadata Test ---");

        var startMeta = new Dictionary<string, object>
        {
            ["query"] = "SELECT * FROM users",
            ["table"] = "users"
        };

        EW.StartTiming("QueryUsers", "database", startMeta);
        UILog("Started \"QueryUsers\" with metadata: query, table");
        Thread.Sleep(75);

        var endMeta = new Dictionary<string, object>
        {
            ["rows_returned"] = 42,
            ["cache_hit"] = false
        };

        double ms = EW.EndTiming("QueryUsers", endMeta, true);
        UILog($"Ended \"QueryUsers\": {ms:F2}ms with end metadata");
        UILog("Check logs - should have merged metadata: query, table, rows_returned, cache_hit");
    }

    private void BtnTimingCancel_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Cancel Timing Test ---");

        EW.StartTiming("CancelMe", "test");
        UILog("Started \"CancelMe\"");
        Thread.Sleep(50);

        if (EW.IsTimingActive("CancelMe"))
            UILog("\"CancelMe\" is active");
        else
            UILog("ERROR: \"CancelMe\" should be active!");

        EW.CancelTiming("CancelMe");
        UILog("Cancelled \"CancelMe\" - no log should be sent");

        if (!EW.IsTimingActive("CancelMe"))
            UILog("\"CancelMe\" is no longer active");
        else
            UILog("ERROR: \"CancelMe\" should not be active!");

        EW.StartTiming("Cancel1");
        EW.StartTiming("Cancel2");
        UILog("Started \"Cancel1\" and \"Cancel2\"");

        EW.CancelTiming();
        UILog("CancelTiming() - should cancel \"Cancel2\"");

        if (EW.IsTimingActive("Cancel1") && !EW.IsTimingActive("Cancel2"))
            UILog("Correct: Cancel1 active, Cancel2 cancelled");
        else
            UILog("ERROR: Wrong cancellation!");

        EW.CancelTiming();
        UILog("Cancel timing test complete");
    }

    private void BtnTimingActive_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("--- Check Active Timings ---");

        EW.StartTiming("Active1", "test");
        EW.StartTiming("Active2", "test");
        EW.StartTiming("Active3", "test");
        Thread.Sleep(100);

        var timings = EW.GetActiveTimings();
        UILog($"Active timings: {timings.Count}");

        for (int i = 0; i < timings.Count; i++)
            UILog($"  [{i}] ID: {timings[i].Id}, Tag: {timings[i].Tag}, Elapsed: {timings[i].ElapsedMs:F2}ms");

        while (EW.GetActiveTimings().Count > 0)
            EW.CancelTiming();

        UILog("Active timings test complete");
    }

    private void BtnTimingAll_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("========== RUNNING ALL TIMING TESTS ==========");
        UILog("");

        BtnTimingNested_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingParallel_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingLIFO_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingWithMeta_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingFormat_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingCancel_Click(null, EventArgs.Empty);
        Thread.Sleep(100);
        UILog("");

        BtnTimingActive_Click(null, EventArgs.Empty);

        UILog("");
        UILog("========== ALL TIMING TESTS COMPLETE ==========");
    }

    // ======== DEVICE INFO ========

    private void BtnSetCustomInfo_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.SetCustomDeviceInfo(edtCustomKey.Text, edtCustomValue.Text);
        UILog($"Custom info set: {edtCustomKey.Text} = {edtCustomValue.Text}");
    }

    private void BtnSendCustomInfo_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        EW.SendCustomDeviceInfo();
        UILog("Custom device info queued for sending");
    }

    // ======== METRICS ========

    private void BtnCounterIncrement_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Counter Increment ---");
        EW.IncrementCounter("api_calls");
        UILog("Counter \"api_calls\" incremented by 1");
        EW.IncrementCounter("api_calls");
        UILog("Counter \"api_calls\" incremented by 1 again");
        UILog("Total accumulated: 2 (will be flushed as single rollup)");
    }

    private void BtnCounterBatch_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Counter Batch ---");
        EW.IncrementCounter("bytes_processed", 4096);
        UILog("Counter \"bytes_processed\" += 4096");
        EW.IncrementCounter("bytes_processed", 8192);
        UILog("Counter \"bytes_processed\" += 8192");
        UILog("Total accumulated: 12288");
    }

    private void BtnCounterWithTag_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Counter with Tag ---");
        EW.IncrementCounter("cache_hits", 1, "database");
        UILog("Counter \"cache_hits\" +1 (tag: database)");
        EW.IncrementCounter("cache_misses", 1, "database");
        UILog("Counter \"cache_misses\" +1 (tag: database)");
        EW.IncrementCounter("cache_hits", 1, "api");
        UILog("Counter \"cache_hits\" +1 (tag: api)");
        UILog("Same counter name with different tags = separate metrics");
    }

    private void BtnGaugeRecord_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Record Gauge ---");
        var conn = Random.Shared.Next(100);
        var jobs = Random.Shared.Next(50);
        EW.RecordGauge("active_connections", conn);
        UILog($"Gauge \"active_connections\" = {conn}");
        EW.RecordGauge("queue_depth", jobs, "jobs");
        UILog($"Gauge \"queue_depth\" = {jobs} (tag: jobs)");
    }

    private void BtnGaugeMultiple_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Gauge Multiple Samples ---");
        EW.RecordGauge("memory_mb", 480);
        UILog("Gauge \"memory_mb\" = 480");
        Thread.Sleep(50);
        EW.RecordGauge("memory_mb", 512);
        UILog("Gauge \"memory_mb\" = 512");
        Thread.Sleep(50);
        EW.RecordGauge("memory_mb", 495);
        UILog("Gauge \"memory_mb\" = 495");
        UILog("SDK tracks min=480, max=512, avg=495.7, last=495, count=3");
    }

    private void BtnGaugeWithTag_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Gauge with Tag ---");
        EW.RecordGauge("cpu_pct", 45.2, "system");
        UILog("Gauge \"cpu_pct\" = 45.2 (tag: system)");
        EW.RecordGauge("disk_pct", 72.8, "system");
        UILog("Gauge \"disk_pct\" = 72.8 (tag: system)");
        EW.RecordGauge("latency_ms", 23.5, "api");
        UILog("Gauge \"latency_ms\" = 23.5 (tag: api)");
    }

    private void BtnRegisterGauge_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Register Periodic Gauge ---");
        EW.RegisterPeriodicGauge("cpu_usage_pct", () => Random.Shared.NextDouble() * 100, "system");
        UILog($"Registered \"cpu_usage_pct\" (sampled every {EW.Config.GaugeSamplingIntervalSec}s)");

        EW.RegisterPeriodicGauge("thread_count",
            () => Environment.CurrentManagedThreadId % 20 + 1, "system");
        UILog("Registered \"thread_count\"");
        UILog("Gauges will be sampled automatically in the background");
    }

    private void BtnUnregisterGauge_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;
        UILog("--- Unregister Periodic Gauges ---");
        EW.UnregisterPeriodicGauge("cpu_usage_pct");
        UILog("Unregistered \"cpu_usage_pct\"");
        EW.UnregisterPeriodicGauge("thread_count");
        UILog("Unregistered \"thread_count\"");
    }

    private void BtnMetricsAll_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        UILog("========== RUNNING ALL METRICS TESTS ==========");
        UILog("");

        BtnCounterIncrement_Click(null, EventArgs.Empty);
        UILog("");
        BtnCounterBatch_Click(null, EventArgs.Empty);
        UILog("");
        BtnCounterWithTag_Click(null, EventArgs.Empty);
        UILog("");
        BtnGaugeRecord_Click(null, EventArgs.Empty);
        UILog("");
        BtnGaugeMultiple_Click(null, EventArgs.Empty);
        UILog("");
        BtnGaugeWithTag_Click(null, EventArgs.Empty);
        UILog("");

        BtnRegisterGauge_Click(null, EventArgs.Empty);
        UILog("Waiting 5 seconds for gauge sampling...");
        Thread.Sleep(5000);
        Application.DoEvents();
        BtnUnregisterGauge_Click(null, EventArgs.Empty);

        UILog("");
        UILog("========== ALL METRICS TESTS COMPLETE ==========");
    }

    // ======== UPDATES ========

    private void BtnSimulateUpgrade_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized)
        {
            MessageBox.Show("Please connect first (Step 1)");
            return;
        }

        var oldVersion = $"{_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen";

        _simulatedMinor++;
        if (_simulatedMinor > 9) { _simulatedMinor = 0; _simulatedMajor++; }

        var newVersion = $"{_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen";
        UILog("");
        UILog($"=== Simulating Upgrade: {oldVersion} -> {newVersion} ===");

        UILog("Step 1: Finalizing SDK (simulates closing old version)...");
        ExeWatchSdk.Shutdown();

        UILog($"Step 2: Reinitializing SDK with version {newVersion}...");
        var config = new ExeWatchConfig(edtApiKey.Text.Trim(), edtCustomerId.Text.Trim())
        {
            AppVersion = newVersion,
            SampleRate = 1.0
        };
        ExeWatchSdk.Initialize(config);

        EW.Instance.OnError = msg => UILog($"ERROR: {msg}");
        EW.Instance.OnLogsSent = (a, r) => UILog($"Logs sent - Accepted: {a}, Rejected: {r}");
        EW.Instance.OnDeviceInfoSent = (s, err) =>
        {
            if (s) UILog("Device info sent successfully");
            else UILog($"Device info send failed: {err}");
        };

        UILog("Step 3: Sending device info (backend detects version change)...");
        EW.SendDeviceInfo();
        EW.Info($"Upgraded from {oldVersion} to {newVersion}", "upgrade");

        UILog("");
        UILog("Done! Open the ExeWatch dashboard -> Updates page to see:");
        UILog($"  Previous: {oldVersion} -> New: {newVersion} (type: upgrade)");
        UpdateUI();
    }

    private void BtnSimulateDowngrade_Click(object? sender, EventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized)
        {
            MessageBox.Show("Please connect first (Step 1)");
            return;
        }

        if (_simulatedMajor <= 1 && _simulatedMinor <= 0)
        {
            UILog("Cannot downgrade below 1.0.0 - click Upgrade first");
            return;
        }

        var oldVersion = $"{_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen";

        _simulatedMinor--;
        if (_simulatedMinor < 0) { _simulatedMinor = 9; _simulatedMajor--; }

        var newVersion = $"{_simulatedMajor}.{_simulatedMinor}.0-demo_oxygen";
        UILog("");
        UILog($"=== Simulating Downgrade: {oldVersion} -> {newVersion} ===");

        UILog("Finalizing SDK (simulates closing current version)...");
        ExeWatchSdk.Shutdown();

        UILog($"Reinitializing with older version {newVersion}...");
        var config = new ExeWatchConfig(edtApiKey.Text.Trim(), edtCustomerId.Text.Trim())
        {
            AppVersion = newVersion,
            SampleRate = 1.0
        };
        ExeWatchSdk.Initialize(config);

        EW.Instance.OnError = msg => UILog($"ERROR: {msg}");
        EW.Instance.OnLogsSent = (a, r) => UILog($"Logs sent - Accepted: {a}, Rejected: {r}");
        EW.Instance.OnDeviceInfoSent = (s, err) =>
        {
            if (s) UILog("Device info sent successfully");
            else UILog($"Device info send failed: {err}");
        };

        UILog("Sending device info (backend detects version rollback)...");
        EW.SendDeviceInfo();
        EW.Warning($"Downgraded from {oldVersion} to {newVersion}", "upgrade");

        UILog("");
        UILog("Done! Open the ExeWatch dashboard -> Updates page to see:");
        UILog($"  Previous: {oldVersion} -> New: {newVersion} (type: downgrade)");
        UpdateUI();
    }

    private void BtnPopulateDevices_Click(object? sender, EventArgs e)
    {
        var apiKey = edtApiKey.Text.Trim();
        if (string.IsNullOrEmpty(apiKey) || apiKey.StartsWith("<"))
        {
            MessageBox.Show("Please enter a valid API Key first (Step 1)");
            return;
        }

        btnPopulateDevices.Enabled = false;
        UILog("");
        UILog("=== Populating 20 simulated devices via SDK (7 customers, 4 versions) ===");
        UILog("Each device sends REAL hardware info collected by the SDK.");
        UILog("");

        if (ExeWatchSdk.IsInitialized)
            ExeWatchSdk.Shutdown();

        var devices = new (string CustomerId, string AppVersion)[]
        {
            ("ACME-Corp", "1.0.0"), ("ACME-Corp", "1.1.0"), ("ACME-Corp", "2.0.0"), ("ACME-Corp", "2.1.0"),
            ("Beta-Inc", "1.0.0"), ("Beta-Inc", "1.1.0"), ("Beta-Inc", "2.0.0"), ("Beta-Inc", "2.1.0"),
            ("Eta-Inc", "1.0.0"), ("Gamma-Ltd", "1.1.0"), ("Gamma-Ltd", "2.0.0"), ("Gamma-Ltd", "2.1.0"),
            ("Delta-SA", "1.0.0"), ("Delta-SA", "1.1.0"), ("Delta-SA", "2.0.0"), ("Delta-SA", "2.1.0"),
            ("Epsilon-GmbH", "1.0.0"), ("Epsilon-GmbH", "1.1.0"), ("Zeta-GmbH", "2.0.0"), ("Zeta-GmbH", "2.1.0")
        };

        int successCount = 0;
        for (int i = 0; i < devices.Length; i++)
        {
            var config = new ExeWatchConfig(apiKey, devices[i].CustomerId)
            {
                AppVersion = devices[i].AppVersion,
                SampleRate = 1.0
            };

            ExeWatchSdk.Initialize(config);
            EW.SendDeviceInfo();
            ExeWatchSdk.Shutdown();

            successCount++;
            UILog($"  [{i + 1}/20] {devices[i].CustomerId}  |  v{devices[i].AppVersion}");
            Application.DoEvents();
        }

        UILog("");
        UILog($"Done! {successCount}/20 devices sent via SDK with real hardware info.");
        UILog("Open the ExeWatch dashboard -> Updates page to see all devices.");

        btnPopulateDevices.Enabled = true;
        UpdateUI();
    }
}
