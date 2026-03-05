# ExeWatch + DMVCFramework Sample

A complete web application built with [DMVCFramework](https://github.com/danieleteti/delphimvcframework), TemplatePro, and HTMX — fully instrumented with [ExeWatch](https://exewatch.com) for real-time server monitoring.

This sample shows that adding ExeWatch to an existing DMVCFramework project takes just a few lines of code, yet gives you deep visibility into what your server is doing.

## Getting Started

**Requirements:**
- Embarcadero Delphi 11+
- [DMVCFramework](https://github.com/danieleteti/delphimvcframework) (set the `$(DMVC)` environment variable to the `sources` folder)

**Step 1** — Open `DelphiDMVCFramework.dproj` in the Delphi IDE.

**Step 2** — Open `DelphiDMVCFramework.dpr` and replace `YOUR_EXEWATCH_APIKEY` with your API key from [exewatch.com](https://exewatch.com).

**Step 3** — Build and run. The server starts on port 8080.

**Step 4** — Open `http://localhost:8080` in your browser, navigate the pages, click buttons.

**Step 5** — Open the ExeWatch dashboard — you'll see logs, timings, breadcrumbs, counters, and metrics appearing in real time.

## How Easy Is the Integration?

The entire ExeWatch integration happens in `DelphiDMVCFramework.dpr` — **no changes needed in your controllers**.

### 1. Route DMVCFramework's logger to ExeWatch

DMVCFramework uses LoggerPro for internal logging. By adding a callback appender, every `LogI`, `LogW`, `LogE` call — **including the framework's own internal logs** — is automatically forwarded to ExeWatch:

```pascal
SetDefaultLogger(
  CreateLogBuilderWithDefaultConfiguration
    .WriteToCallback
    .WithCallback(
      procedure(const ALogItem: TLogItem; const AFormattedMessage: string)
      begin
        if ExeWatchIsInitialized and (ALogItem.LogType > TLogType.Debug) then
          EW.Log(
            TEWLogLevel(Ord(ALogItem.LogType)),
            ALogItem.LogMessage,
            ALogItem.LogTag,
            ALogItem.TimeStamp,
            ALogItem.ThreadID);
      end).Done.Build);
```

### 2. Initialize ExeWatch

```pascal
InitializeExeWatch(TExeWatchConfig.Create('ew_win_your_key', 'customer_id'));
```

### 3. Enable the built-in profiler

DMVCFramework has a built-in action profiler. Since the logger is already routed to ExeWatch, action timings appear automatically — no manual `StartTiming`/`EndTiming` in every controller method:

```pascal
Profiler.ProfileLogger := Log;
Profiler.WarningThreshold := 500;      // warn if action takes > 500ms
Profiler.LogsOnlyIfOverThreshold := False;
```

**That's it.** Three steps, all in the `.dpr` file. Your controllers don't need any ExeWatch-specific code to get full request logging and timing.

## What More You Can Do

The basic integration above gives you automatic logging and timing for free. But ExeWatch has many more features you can use where they make sense in your business logic:

### Structured Extra Data

When a batch operation partially fails, attach structured JSON data to any log entry. In the ExeWatch dashboard, clicking a log row reveals the full extra data:

```pascal
LExtra := TJSONObject.Create;
LExtra.AddPair('total_rows', TJSONNumber.Create(10));
LExtra.AddPair('imported', TJSONNumber.Create(7));
LExtra.AddPair('failed', TJSONNumber.Create(3));
LExtra.AddPair('failed_rows', LFailedRowsArray);  // detailed array

EW.Log(llWarning, 'Batch import: 7 imported, 3 failed', 'people', LExtra);
```

### Nested Timings

When an operation has multiple steps, time each one inside a parent timing. ExeWatch shows them as related entries so you can spot the bottleneck:

```pascal
EW.StartTiming('report.sales', 'reports');          // parent timing
  EW.StartTiming('report.sales.query', 'database'); // step 1
  // ...run query...
  EW.EndTiming('report.sales.query');
  EW.StartTiming('report.sales.charts', 'compute'); // step 2
  // ...render charts...
  EW.EndTiming('report.sales.charts');
EW.EndTiming('report.sales');                        // close parent
```

### Breadcrumbs

Breadcrumbs create a trail of actions. When an error occurs, the ExeWatch log detail shows everything that happened before:

```pascal
EW.AddBreadcrumb('Calling payment API', 'payment');
EW.AddBreadcrumb('Search: "Ford"', 'people');
```

### Counters and Gauges

Track business metrics alongside your logs:

```pascal
EW.IncrementCounter('payment.success', 1);
EW.IncrementCounter('email.rate_limited', 1);

EW.RegisterPeriodicGauge('memory_mb',
  function: Double
  begin
    Result := GetCurrentMemoryMB;
  end);
```

### Exception Capture

The global exception handler in `WebModuleU.pas` catches unhandled errors and forwards them with full details:

```pascal
fMVC.SetExceptionHandler(
  procedure(E: Exception; ...)
  begin
    EW.ErrorWithException(E, 'unhandled');  // class name, message, stack trace
  end);
```

## Pages Overview

| Page | What it does | What to look for in ExeWatch |
|------|-------------|------------------------------|
| **Dashboard** | Server stats and quick-action buttons | Click "Simulate Error/Warning/Slow" and watch them appear in real time |
| **People** | CRUD with live search and batch import | Filter logs by tag `people`; check batch import logs for structured extra data |
| **Reports** | Heavy reports with nested steps | Check the Timing page — each report shows a parent timing with individual sub-steps |
| **Services** | Simulated external API calls | Some calls fail randomly — filter by `payment`, `email`, or `geocoding` to see successes and failures |

### People — Batch Import

Click **Batch Import (10)** to import 10 people with a ~20% failure rate. Each failed row is logged individually with structured extra data (row number, name, error reason). The summary log includes an array of all failed rows — visible in the ExeWatch log detail modal.

### Reports — Three Different Behaviors

- **Sales Report** — Always succeeds. 4 nested steps timed individually.
- **Inventory Report** — 30% chance of failure (warehouse API down). Failed runs produce ERROR logs and failed timings.
- **Audit Report** — Slow queries trigger warnings. Compliance checks may find violations.

### Services — Realistic Failure Modes

- **Payment Gateway** — 60% success, 20% timeout (4s delay), 15% declined, 5% gateway error (502)
- **Email Service** — 75% success, 15% rate limited (429), 10% SMTP error
- **Geocoding API** — 15% cache hit (instant), normal response, or quota exceeded
- **Service Orchestration** — Calls 5 services sequentially, each timed inside a parent timing

## Project Structure

| File | Description |
|------|-------------|
| `DelphiDMVCFramework.dpr` | Server entry point — logger integration, ExeWatch init, profiler, gauges |
| `WebModuleU.pas` | MVC engine config, template engine, static files, global exception handler |
| `ControllerU.pas` | Controller actions with ExeWatch breadcrumbs, timings, and structured logs |
| `EntitiesU.pas` | TPerson entity |
| `ServicesU.pas` | Thread-safe in-memory people service |
| `bin/templates/` | TemplatePro page templates |
| `bin/templates/partials/` | Shared partials (nav, footer, content blocks, tables) |
| `bin/www/css/style.css` | Dark theme CSS |

## ExeWatch Features Used

| Feature | How it's used |
|---------|---------------|
| Logger integration | LoggerPro callback forwards all framework logs to ExeWatch |
| Profiler integration | DMVCFramework's built-in profiler auto-times every controller action |
| `EW.StartTiming / EndTiming` | Nested timings for reports and service orchestration |
| `EW.Log` with extra data | Batch import failures with structured JSON (failed rows array) |
| `EW.AddBreadcrumb` | Search queries, service calls, report steps |
| `EW.ErrorWithException` | Full exception details in the global exception handler |
| `EW.IncrementCounter` | Business metrics: payments, emails, cache hits, errors |
| `EW.RegisterPeriodicGauge` | Memory usage reported every 30 seconds |
| `EW.SetTag` | Global context: `framework=dmvcframework` on all logs |
| `EW.Flush` | Ensures all pending logs are sent before shutdown |
