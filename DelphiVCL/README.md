# ExeWatch — Delphi VCL Sample

A Windows desktop application that demonstrates logging, timing, and exception capture using the ExeWatch Delphi SDK.

## Requirements

- Embarcadero Delphi 12.3+ (Community Edition works fine)

## Step-by-step

**Step 1** — Open `EWDelphiVCL.dproj` in the Delphi IDE.

**Step 2** — Open `MainFormU.pas` and replace the `EXEWATCH_API_KEY` constant with your own API key (from [exewatch.com](https://exewatch.com)).

**Step 3** — Build and run (F9).

**Step 4** — Click the buttons to try each feature:

- **Logging** — sends one log at each severity level (Debug, Info, Warning, Error, Fatal)
- **Timing** — measures a simulated operation (300 – 1500 ms) and reports its duration
- **Breadcrumbs + Error** — adds a trail of breadcrumbs, then triggers an exception so you can see the context in the dashboard
- **User Identity** — associates a user (id, email, name) with all subsequent events
- **Tags** — attaches key-value metadata to events
- **Metrics** — increments a counter and records a gauge value

**Step 5** — Open the ExeWatch dashboard to see your logs, timings, and exceptions appear in real time.

## How it works

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
