# ExeWatch Samples

Official sample projects demonstrating how to integrate [ExeWatch](https://exewatch.com) into your applications.

## What is ExeWatch?

ExeWatch is a real-time application monitoring platform for **Delphi** (Windows, Linux, MacOS, Android, iOS) and **JavaScript** applications. It captures errors, logs, performance timings, hardware info, and user behavior — giving you full visibility into what happens in production, without needing to reproduce issues locally.

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

Once registered, create an application in the ExeWatch dashboard and copy your **API Key** — you'll need it for both samples.

## What's in This Repository

| Folder | Sample | Language | Status |
|--------|--------|----------|--------|
| `DelphiVCL/` | Delphi VCL desktop app | Object Pascal | Ready |
| `JS/` | Browser-based web app | JavaScript/HTML | Ready |

---

## Sample 1: Delphi VCL

A Windows desktop application that demonstrates logging, timing, and exception capture using the ExeWatch Delphi SDK.

### Requirements

- Embarcadero Delphi 12.3+ (Community Edition works fine)

### Step-by-step

**Step 1** — Open the project in Delphi IDE:

```
DelphiVCL/EWDelphiVCL.dproj
```

**Step 2** — Open `MainFormU.pas` and find the `FormCreate` method. Replace the API key with your own:

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
begin
  InitializeExeWatch('YOUR_API_KEY_HERE', '');
  EW.OnError := OnEWError;
  EW.SetCustomerId('SampleCustomer');
  EW.SetCustomDeviceInfo('env', 'staging');
  EW.SendCustomDeviceInfo;
end;
```

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

// Timing
EW.StartTiming('load_report');
// ... your operation ...
EW.EndTiming('load_report');

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

## Sample 2: JavaScript Browser

A single HTML page that demonstrates ExeWatch logging, timing, and error capture directly in the browser.

### Requirements

- Any modern browser (Chrome, Firefox, Edge, Safari)
- No build tools, no npm — just open the file

### Step-by-step

**Step 1** — Open `JS/index.html` in a text editor and replace the API key placeholder with your own (browser API keys start with `ew_web_`):

```javascript
window.ewConfig = {
  apiKey: 'YOUR_API_KEY_HERE',
  customerId: 'SampleCustomer',
  appVersion: '1.0.0',
  debug: true
};
```

**Step 2** — Open `JS/index.html` in your browser (double-click the file, or use a local server).

**Step 3** — Click the buttons to try each feature:

- **Logging** — sends one log at each severity level (Debug, Info, Warning, Error, Fatal)
- **Timing** — measures a simulated async operation (300 – 1500 ms) and reports its duration
- **Breadcrumbs + Error** — adds a trail of breadcrumbs, then triggers an error so you can see the context in the dashboard
- **User Identity** — associates a user (id, email, name) with all subsequent events
- **Tags** — attaches key-value metadata to events
- **Metrics** — increments a counter and records a gauge value

**Step 4** — Open the ExeWatch dashboard to see your events arrive in real time.

### How it works

The sample loads the ExeWatch JavaScript SDK from CDN. Configuration is set via `window.ewConfig` before the SDK script, then the global `ew` object is available immediately:

```html
<script>
  window.ewConfig = {
    apiKey: 'ew_web_xxxx',
    customerId: 'SampleCustomer'
  };
</script>
<script src="https://exewatch.com/static/js/exewatch.v1.min.js"></script>
```

After loading, the API mirrors the Delphi SDK:

```javascript
// Logging
ew.debug('Page loaded');
ew.info('User signed in', 'auth');
ew.warning('Slow network detected', 'perf');
ew.error('API call failed', 'api');

// Breadcrumbs
ew.addBreadcrumb('Clicked checkout button', 'ui');
ew.addBreadcrumb('Entered payment details', 'form');

// Timing
ew.startTiming('api_call');
// ... your operation ...
ew.endTiming('api_call');

// User identity
ew.setUser({ id: 'user-42', email: 'jane@example.com', name: 'Jane Doe' });

// Tags
ew.setTag('environment', 'production');

// Metrics
ew.incrementCounter('page_views', 1, 'sample');
ew.recordGauge('cart_items', 5, 'sample');
```

---

## Quick Comparison

Both samples demonstrate the same core features — the API is intentionally similar across SDKs:

| Feature | Delphi | JavaScript |
|---------|--------|------------|
| Initialize | `InitializeExeWatch(key, id)` | `window.ewConfig = { apiKey, customerId }` |
| Log shortcut | `EW.Info(...)` | `ew.info(...)` |
| Breadcrumbs | `EW.AddBreadcrumb(...)` | `ew.addBreadcrumb(...)` |
| Timing | `EW.StartTiming` / `EW.EndTiming` | `ew.startTiming` / `ew.endTiming` |
| User identity | `EW.SetUser(id, email, name)` | `ew.setUser({ id, email, name })` |
| Tags | `EW.SetTag(key, value)` | `ew.setTag(key, value)` |
| Metrics | `EW.IncrementCounter` / `EW.RecordGauge` | `ew.incrementCounter` / `ew.recordGauge` |
| Exception capture | Automatic | Automatic |

## Learn More

- **Documentation**: https://exewatch.com/ui/docs
- **Pricing**: https://exewatch.com/ui/pricing
- **Changelog**: https://exewatch.com/ui/changelog
- **Contact**: exewatch@bittime.it
