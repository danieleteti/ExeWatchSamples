# ExeWatch Samples

Official sample projects demonstrating how to integrate [ExeWatch](https://exewatch.com) into your applications.

## What is ExeWatch?

ExeWatch is a real-time application monitoring platform for **Delphi**, **.NET / C#**, and **JavaScript** applications. It captures errors, logs, performance timings, hardware info, and user behavior — giving you full visibility into what happens in production, without needing to reproduce issues locally.

Key capabilities:

- **Logging** with five severity levels (Debug, Info, Warning, Error, Fatal)
- **Automatic exception capture** — unhandled errors are caught and reported
- **Breadcrumb trails** — see exactly what happened before an error
- **Performance timings** — measure operations with Avg/Min/Max/P95 stats
- **Hardware intelligence** — CPU, RAM, disk, OS, monitor details
- **Multi-customer tracking** — filter logs by customer ID
- **Email and timing alerts** — get notified when things go wrong

For full documentation, visit: **https://exewatch.com/ui/docs**

## Prerequisites

You need an ExeWatch account to run these samples. **The free Hobby plan requires no credit card** and includes:

- 1 application
- 10,000 events/month
- 7-day log retention
- 2 alerts (email + timing)

This is enough for personal projects and small commercial applications. Sign up at **https://exewatch.com**.

Once registered, create an application in the ExeWatch dashboard and copy your **API Key** — you'll need it for the samples.

## What's in This Repository

| Folder | Sample | Language | Status |
|--------|--------|----------|--------|
| `DelphiVCL/` | Delphi VCL desktop app | Object Pascal | Ready |
| `DelphiWebBroker/` | Delphi WebBroker server | Object Pascal | Ready |
| `DotNetConsole/` | .NET console application | C# | Ready |
| `DotNetWindowsForms/` | .NET Windows Forms desktop app | C# | Ready |
| `DotNetWindowsService/` | .NET Windows Service | C# | Ready |
| `JS/` | Browser-based web app | JavaScript/HTML | Ready |

All .NET samples require **.NET 8.0+** and **Visual Studio 2022 (17.8+)** or **JetBrains Rider 2024.1+**. The Delphi samples require **Embarcadero Delphi 12.3+**. The JavaScript sample works in any modern browser with no build tools.

---

## Sample 1: Delphi VCL

A Windows desktop application that demonstrates logging, timing, and exception capture using the ExeWatch Delphi SDK.

### Step-by-step

**Step 1** — Open `DelphiVCL/EWDelphiVCL.dproj` in the Delphi IDE.

**Step 2** — Open `MainFormU.pas` and replace the `EXEWATCH_API_KEY` constant with your own API key.

**Step 3** — Build and run (F9).

**Step 4** — Click the buttons to try each feature:

- **Logging** — sends one log at each severity level (Debug, Info, Warning, Error, Fatal)
- **Timing** — measures a simulated operation (300 – 1500 ms) and reports its duration
- **Breadcrumbs + Error** — adds a trail of breadcrumbs, then triggers an exception so you can see the context in the dashboard
- **User Identity** — associates a user (id, email, name) with all subsequent events
- **Tags** — attaches key-value metadata to events
- **Metrics** — increments a counter and records a gauge value

**Step 5** — Open the ExeWatch dashboard to see your logs, timings, and exceptions appear in real time.

### How it works

The sample uses three source files from the SDK:

| File | Role |
|------|------|
| `ExeWatchSDKv1.pas` | Core SDK — handles logging, buffering, disk persistence, and background shipping to ExeWatch |
| `ExeWatchSDKv1.VCL.pas` | VCL hook — automatically captures GUI exceptions that the standard `ExceptProc` misses |
| `MainFormU.pas` | Sample app — demonstrates the SDK API |

After calling `InitializeExeWatch`, you use the global `EW` shortcut for all operations:

```pascal
// Logging
EW.Debug('Loading configuration');
EW.Info('User logged in', 'auth');
EW.Warning('Disk space low', 'system');
EW.Error('Payment failed', 'billing');
EW.Fatal('Database unreachable', 'db');

// Breadcrumbs (context trail before errors)
EW.AddBreadcrumb('User clicked Save');
EW.AddBreadcrumb('Validated form fields');

// Timing with try/except
EW.StartTiming('load_report');
try
  LoadReport;
  EW.EndTiming('load_report');
except
  on E: Exception do
  begin
    EW.EndTiming('load_report', nil, False);
    raise;
  end;
end;

// User identity
EW.SetUser('user-123', 'john@example.com', 'John Doe');

// Tags
EW.SetTag('environment', 'production');

// Metrics
EW.IncrementCounter('page_views');
EW.RecordGauge('active_sessions', 42);
```

Logs are persisted to disk before being sent, so nothing is lost even if the app crashes.

---

## Sample 2: Delphi WebBroker

A REST API server built with Delphi WebBroker that demonstrates monitoring a web service with ExeWatch.

### Step-by-step

**Step 1** — Open `DelphiWebBroker/WebBrokerSample.dproj` in the Delphi IDE.

**Step 2** — Open `WebBrokerSample.dpr` and replace the `EXEWATCH_API_KEY` constant with your own API key.

**Step 3** — Build and run. The server starts on port 8080 (use `-p 9000` for a different port).

**Step 4** — Test the endpoints:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/api/info
curl http://localhost:8080/api/time
```

**Step 5** — Open the ExeWatch dashboard to see logs, timings, and metrics appear in real time.

### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML page listing all endpoints |
| `/health` | GET | Health check with request/error counts |
| `/api/info` | GET | Application information |
| `/api/echo` | POST | Echo back the request |
| `/api/time` | GET | Current server timestamp |
| `/api/delay` | GET | Simulate slow response (`?ms=500`) |

### How It Works

The WebModule wraps every request through `HandleRequest`, which:

1. Increments `http.requests` counter
2. Adds a breadcrumb for the request
3. Starts timing the endpoint
4. Executes the handler
5. Records timing (success or failure)

On errors: increments `http.errors` counter, logs the exception, returns HTTP 500.

```pascal
function TWebModule1.HandleRequest(Request: TWebRequest; Response: TWebResponse;
  const Endpoint: string; Handler: TProc): Boolean;
begin
  Result := True;
  EW.IncrementCounter('http.requests', 1);
  EW.AddBreadcrumb('request: ' + Endpoint, 'http');
  EW.StartTiming(Endpoint);
  try
    Handler;
    EW.EndTiming(Endpoint, nil, True);
  except
    on E: Exception do
    begin
      EW.IncrementCounter('http.errors', 1);
      EW.EndTiming(Endpoint, nil, False);
      EW.ErrorWithException(E, Endpoint);
      Response.StatusCode := 500;
    end;
  end;
end;
```

### Files

| File | Role |
|------|------|
| `WebBrokerSample.dpr` | Main program — initializes SDK, starts server |
| `WebModuleU.pas` | WebModule — endpoints and ExeWatch integration |

---

## Sample 3: JavaScript Browser

A single HTML page that demonstrates ExeWatch logging, timing, and error capture directly in the browser. No build tools required — just open the file.

### Step-by-step

**Step 1** — Open `JS/index.html` in a text editor and replace `YOUR_API_KEY_HERE` with your browser API key (starts with `ew_web_`):

```javascript
window.ewConfig = {
  apiKey: 'YOUR_API_KEY_HERE',
  customerId: 'SampleCustomer',
  appVersion: '1.0.0',
  debug: true
};
```

**Step 2** — Open `JS/index.html` in your browser (double-click the file, or use a local server).

**Step 3** — Click the buttons to try each feature: Logging, Timing, Breadcrumbs + Error, User Identity, Tags, Metrics.

**Step 4** — Open the ExeWatch dashboard to see your events arrive in real time.

### How it works

The sample loads the ExeWatch JavaScript SDK from CDN. Set `window.ewConfig` before the SDK script — the global `ew` object is then available immediately:

```html
<script>
  window.ewConfig = {
    apiKey: 'ew_web_xxxx',
    customerId: 'SampleCustomer'
  };
</script>
<script src="https://exewatch.com/static/js/exewatch.v1.min.js"></script>
```

```javascript
// Logging
ew.debug('Page loaded');
ew.info('User signed in', 'auth');
ew.error('API call failed', 'api');

// Breadcrumbs
ew.addBreadcrumb('Clicked checkout button', 'ui');

// Timing
ew.startTiming('api_call');
// ... your operation ...
ew.endTiming('api_call');

// User identity
ew.setUser({ id: 'user-42', email: 'jane@example.com', name: 'Jane Doe' });

// Tags & Metrics
ew.setTag('environment', 'production');
ew.incrementCounter('page_views', 1, 'sample');
ew.recordGauge('cart_items', 5, 'sample');
```

---

## Sample 4: .NET Console

A console application that demonstrates all major ExeWatch SDK features for .NET. It runs through each feature sequentially — including 20 timed iterations to generate meaningful Avg/Min/Max/P95 statistics in the dashboard.

### Step-by-step

**Step 1** — Open `DotNetConsole/DotNetConsole.csproj` in Visual Studio.

**Step 2** — Open `Program.cs` and replace `ew_win_YOUR_API_KEY_HERE` with your API key.

**Step 3** — Press F5 to run. The app will:

- Initialize the SDK and set user identity / global tags
- Log messages at various severity levels
- Add breadcrumbs for error context
- Run 20 simulated database queries with try/catch timing (some will fail randomly, so the dashboard shows a realistic success rate)
- Record counters and gauges
- Send custom device info

**Step 4** — Open the ExeWatch dashboard to see logs, timings (with Avg/Min/Max/P95/Count), and metrics.

### How it works

The sample references the SDK via project reference to `DotNetCommons/ExeWatch/`. After calling `ExeWatchSdk.Initialize(config)`, the global `EW` shortcut is available:

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

---

## Sample 5: .NET Windows Forms

An interactive desktop application that demonstrates every ExeWatch SDK feature through a tabbed GUI. The API key is entered at runtime — no code editing needed.

### Step-by-step

**Step 1** — Open `DotNetWindowsForms/DotNetWindowsForms.csproj` in Visual Studio.

**Step 2** — Press F5 to run.

**Step 3** — Enter your API key and Customer ID in the connection panel, then click **Use**.

**Step 4** — Explore the tabs:

- **Logging** — send individual logs or generate a batch with breadcrumbs; test automatic exception capture
- **Timing** — nested timings, parallel timings, LIFO stack, cancel, metadata, and a "Run All" button
- **Device Info** — send custom key-value pairs alongside the standard hardware info
- **Metrics** — counters (increment, batch, tagged), gauges (single, multiple, tagged), periodic gauges
- **Updates** — simulate version upgrades/downgrades, populate simulated devices

**Step 5** — Open the ExeWatch dashboard to see your events arrive in real time.

### How it works

The WinForms sample uses two SDK packages:

| Package | Role |
|---------|------|
| `ExeWatch` | Core SDK — logging, timing, metrics, device info |
| `ExeWatch.WinForms` | WinForms hook — captures `Application.ThreadException` automatically |

`ExeWatchWinForms.Install()` is called in `Program.cs` before `Application.Run()` to ensure unhandled GUI exceptions are captured.

### Files

| File | Role |
|------|------|
| `Program.cs` | Entry point — installs WinForms exception hook |
| `MainForm.cs` | Main form — all SDK feature demos |
| `MainForm.Designer.cs` | Visual Studio designer (auto-generated) |

---

## Sample 6: .NET Windows Service

A Worker Service that demonstrates monitoring a long-running background process with ExeWatch. It can run as a console app during development or be installed as a real Windows Service.

### Step-by-step

**Step 1** — Open `DotNetWindowsService/DotNetWindowsService.csproj` in Visual Studio.

**Step 2** — Open `Worker.cs` and replace `ew_win_YOUR_API_KEY_HERE` with your API key.

**Step 3** — Press F5 to run as a console app. The service processes a cycle every 10 seconds, generating timing and metric data continuously.

**Step 4** — To install as a real Windows Service:

```bash
dotnet publish -c Release -o C:\Services\ExeWatchDemo
sc create ExeWatchDemo binPath="C:\Services\ExeWatchDemo\DotNetWindowsService.exe"
sc start ExeWatchDemo
```

**Step 5** — Open the ExeWatch dashboard to see logs, timings, and metrics from each processing cycle.

### How it works

The service follows the recommended pattern for long-running .NET services:

| Method | ExeWatch integration |
|--------|---------------------|
| `StartAsync` | Initialize SDK, set tags, send device info |
| `ExecuteAsync` | Main loop — each cycle is timed and monitored |
| `ProcessCycleAsync` | Nested timings for sub-operations (fetch, transform) |
| `StopAsync` | Shut down SDK (flushes remaining logs) |

Each processing cycle demonstrates:

- **Outer timing** (`process_cycle`) wrapping the entire cycle
- **Nested timings** (`fetch_data`, `transform_data`) for individual sub-operations
- **try/catch pattern** — success marks timing as passed, exception marks it as failed with error details
- **Counters** (`items_processed`) and **gauges** (`batch_size`) for metrics
- **Graceful error handling** — failed cycles don't crash the service

### Files

| File | Role |
|------|------|
| `Program.cs` | Host builder — configures Windows Service support |
| `Worker.cs` | Background worker — main processing loop with ExeWatch instrumentation |

---

## Quick Comparison

All samples demonstrate the same core features — the API is intentionally similar across SDKs:

| Feature | Delphi | C# / .NET | JavaScript |
|---------|--------|-----------|------------|
| Initialize | `InitializeExeWatch(key, id)` | `ExeWatchSdk.Initialize(config)` | `window.ewConfig = { apiKey, customerId }` |
| Log shortcut | `EW.Info(...)` | `EW.Info(...)` | `ew.info(...)` |
| Breadcrumbs | `EW.AddBreadcrumb(...)` | `EW.AddBreadcrumb(...)` | `ew.addBreadcrumb(...)` |
| Timing | `EW.StartTiming` / `EW.EndTiming` | `EW.StartTiming` / `EW.EndTiming` | `ew.startTiming` / `ew.endTiming` |
| User identity | `EW.SetUser(id, email, name)` | `EW.SetUser(id, email, name)` | `ew.setUser({ id, email, name })` |
| Tags | `EW.SetTag(key, value)` | `EW.SetTag(key, value)` | `ew.setTag(key, value)` |
| Metrics | `EW.IncrementCounter` / `EW.RecordGauge` | `EW.IncrementCounter` / `EW.RecordGauge` | `ew.incrementCounter` / `ew.recordGauge` |
| Exception capture | Automatic | Automatic | Automatic |

## Learn More

- **Documentation**: https://exewatch.com/ui/docs
- **Pricing**: https://exewatch.com/ui/pricing
- **Changelog**: https://exewatch.com/ui/changelog
- **Contact**: exewatch@bittime.it
