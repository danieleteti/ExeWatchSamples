{ *******************************************************************************
  ExeWatch VCL Sample Application

  This demo shows how to use every feature of the ExeWatch Delphi SDK.
  Each button maps to one SDK capability. Read the comments below to
  understand what is REQUIRED vs OPTIONAL in your own application.

  Quick start:
    1. Replace the API key in FormCreate with your own (from https://exewatch.com)
    2. Build and run (F9)
    3. Click the buttons and watch events appear in the ExeWatch dashboard

  Full docs: https://exewatch.com/ui/docs
******************************************************************************* }

unit MainFormU;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    grpLogging: TGroupBox;
    btnDebug: TButton;
    btnInfo: TButton;
    btnWarning: TButton;
    btnError: TButton;
    btnFatal: TButton;
    grpTiming: TGroupBox;
    btnTiming: TButton;
    grpBreadcrumbs: TGroupBox;
    btnBreadcrumbsError: TButton;
    grpUser: TGroupBox;
    btnSetUser: TButton;
    btnClearUser: TButton;
    grpTags: TGroupBox;
    btnSetTags: TButton;
    btnClearTags: TButton;
    grpMetrics: TGroupBox;
    btnIncrementCounter: TButton;
    btnRecordGauge: TButton;
    lblLog: TLabel;
    btnClearLog: TButton;
    Memo1: TMemo;
    Button1: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnDebugClick(Sender: TObject);
    procedure btnInfoClick(Sender: TObject);
    procedure btnWarningClick(Sender: TObject);
    procedure btnErrorClick(Sender: TObject);
    procedure btnFatalClick(Sender: TObject);
    procedure btnTimingClick(Sender: TObject);
    procedure btnBreadcrumbsErrorClick(Sender: TObject);
    procedure btnSetUserClick(Sender: TObject);
    procedure btnClearUserClick(Sender: TObject);
    procedure btnSetTagsClick(Sender: TObject);
    procedure btnClearTagsClick(Sender: TObject);
    procedure btnIncrementCounterClick(Sender: TObject);
    procedure btnRecordGaugeClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
  private
    FPageViewCount: Integer;
    procedure Log(const AMessage: string);
    procedure OnEWError(const ErrorMessage: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  Winapi.PsAPI,
  ExeWatchSDKv1;

const
  // Replace with your actual API key from the ExeWatch dashboard
  EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY';

{$R *.dfm}

{ Returns the current process working set (physical memory) in megabytes.
  Used by the periodic gauge demo to monitor memory usage automatically. }
function GetWorkingSetMB: Double;
var
  Counters: TProcessMemoryCounters;
begin
  Counters.cb := SizeOf(Counters);
  if GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then
    Result := Counters.WorkingSetSize / (1024 * 1024)
  else
    Result := 0;
end;

{ Returns the free disk space on drive C: in gigabytes.
  Used by the periodic gauge demo to monitor available storage.
  DiskFree(3) returns free bytes for drive C: (1=A, 2=B, 3=C, ...). }
function GetDiskFreeGB: Double;
var
  FreeBytes: Int64;
begin
  FreeBytes := DiskFree(3);  // 3 = drive C:
  if FreeBytes >= 0 then
    Result := FreeBytes / (1024 * 1024 * 1024)
  else
    Result := 0;
end;

{ ============================================================================
  INITIALIZATION — REQUIRED
  InitializeExeWatch() is the only call you MUST make. Everything else
  (user identity, tags, custom device info, etc.) is optional.

  Parameters:
    - AApiKey      : your application API key (starts with "ew_win_")
    - ACustomerId  : identifies the customer/tenant using your app.
                     Can be empty and set later via EW.SetCustomerId().
    - AAppVersion  : OPTIONAL user-defined version/release tag (e.g. "2024-Q1",
                     "v2.0-beta"). This is a free-form label you choose to group
                     events by release in the dashboard.

  Versioning — there are two distinct version fields:
    - AppBinaryVersion : AUTOMATIC. The SDK reads the FileVersion from the
                         executable's version info resource (e.g. "2.0.0.0").
                         You don't need to set this — it's always extracted
                         automatically. If the executable has no version info,
                         it falls back to "not available".
    - AppVersion       : MANUAL. A label you define yourself to identify the
                         release (e.g. "2024-Q1", "v3.1-hotfix"). Set it via
                         the third parameter of InitializeExeWatch, or via
                         Config.AppVersion when using the config-based overload.
                         If you don't need release tagging, just omit it.

  After this call the global shortcut EW is available (alias for ExeWatch).
  The SDK immediately starts:
    - capturing unhandled exceptions (via System.ExceptProc)
    - collecting hardware/OS info and sending it to ExeWatch
    - buffering logs to disk and shipping them in the background
  ============================================================================ }
procedure TMainForm.FormCreate(Sender: TObject);
begin
  Randomize;
  Constraints.MaxWidth := Width;
  Memo1.Clear;
  FPageViewCount := 0;
  Caption := Caption + ' - ExeWatch SDK ' + EXEWATCH_SDK_VERSION;

  // ---------------------------------------------------------------
  // REQUIRED — Replace with your API key from https://exewatch.com
  // ---------------------------------------------------------------
  if EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY' then
  begin
    ShowMessage(
      'API Key Not Configured' + sLineBreak + sLineBreak +
      'You must set your API key before running this sample.' + sLineBreak +
      'Open MainFormU.pas, find the EXEWATCH_API_KEY constant and replace' + sLineBreak +
      '"ew_win_xxxxxx_USE_YOUR_OWN_KEY" with your actual API key.' + sLineBreak + sLineBreak +
      'Get your API key from: https://exewatch.com');
    Application.Terminate;
    Exit;
  end;

  InitializeExeWatch(EXEWATCH_API_KEY, 'SampleCustomer');

  // OPTIONAL — Get notified when the SDK encounters an error (e.g. network failure).
  // Useful for debugging integration issues. You can safely omit this in production.
  EW.OnError := OnEWError;

  // OPTIONAL — Attach custom key-value pairs to the device info sent to ExeWatch.
  // Use this to tag the environment, build variant, feature flags, etc.
  // Call SetCustomDeviceInfo() as many times as needed, then SendCustomDeviceInfo()
  // once to transmit them all.
  EW.SetCustomDeviceInfo('env', 'staging');
  EW.SetCustomDeviceInfo('sample', 'DelphiVCL');
  EW.SendCustomDeviceInfo;

  // OPTIONAL — Register periodic gauges. The SDK calls these anonymous functions
  // automatically every 30 seconds (configurable via Config.GaugeSamplingIntervalSec)
  // and sends the returned values as gauge metrics. Use this for values you want
  // to monitor continuously without placing manual RecordGauge calls everywhere.
  // The callbacks run on a background thread — keep them fast and thread-safe.
  // You can register up to 20 periodic gauges.
  EW.RegisterPeriodicGauge('memory_mb',
    function: Double
    begin
      Result := GetWorkingSetMB;
    end, 'system');

  EW.RegisterPeriodicGauge('disk_free_gb',
    function: Double
    begin
      Result := GetDiskFreeGB;
    end, 'system');

  Log('ExeWatch initialized - SDK v' + EXEWATCH_SDK_VERSION);
end;

{ Helper — writes a timestamped line to the local activity log (Memo). }
procedure TMainForm.Log(const AMessage: string);
begin
  Memo1.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + AMessage);
end;

{ Called by the SDK when something goes wrong internally (network errors, etc.) }
procedure TMainForm.OnEWError(const ErrorMessage: string);
begin
  Log('SDK ERROR: ' + ErrorMessage);
end;

{ ============================================================================
  LOGGING — The core feature.

  Five severity levels, from least to most critical:
    EW.Debug   — fine-grained diagnostic info (hidden in dashboard by default)
    EW.Info    — normal operational events
    EW.Warning — unexpected situations that are not errors
    EW.Error   — failures that affect functionality
    EW.Fatal   — critical failures, app cannot continue

  All methods accept:
    - AMessage : the log text
    - ATag     : OPTIONAL grouping label (default 'main'). Use tags to filter
                 logs in the dashboard (e.g. 'auth', 'billing', 'db').

  Format-style overloads are also available:
    EW.Info('User %s logged in from %s', [UserName, IP], 'auth');

  Logs are buffered to disk first (crash-safe), then shipped to ExeWatch
  in the background every 5 seconds.
  ============================================================================ }
procedure TMainForm.btnDebugClick(Sender: TObject);
begin
  EW.Debug('This is a DEBUG message', 'sample');
  Log('[DEBUG] Sent debug log');
end;

procedure TMainForm.btnInfoClick(Sender: TObject);
begin
  EW.Info('This is an INFO message', 'sample');
  Log('[INFO] Sent info log');
end;

procedure TMainForm.btnWarningClick(Sender: TObject);
begin
  EW.Warning('This is a WARNING message', 'sample');
  Log('[WARNING] Sent warning log');
end;

procedure TMainForm.btnErrorClick(Sender: TObject);
begin
  EW.Error('This is an ERROR message', 'sample');
  Log('[ERROR] Sent error log');
end;

procedure TMainForm.btnFatalClick(Sender: TObject);
begin
  EW.Fatal('This is a FATAL message', 'sample');
  Log('[FATAL] Sent fatal log');
end;

{ ============================================================================
  TIMING — Measure how long operations take.

  Wrap any operation between StartTiming / EndTiming:
    EW.StartTiming('operation_id', 'optional_tag');
    // ... your code ...
    Elapsed := EW.EndTiming('operation_id');

  - The operation_id links the start/end pair. Use descriptive names like
    'db_query', 'generate_report', 'api_call'.
  - EndTiming returns the elapsed time in milliseconds (-1 if id not found).
  - The SDK sends a timing event to ExeWatch with Avg/Min/Max/P95 stats.
  - Timings are LIFO (stack-based), so nested timings are supported.
  - You can also call EW.EndTiming() without an id to end the last started timing.
  - Use EW.CancelTiming('id') to discard a timing without sending it.
  ============================================================================ }
procedure TMainForm.btnTimingClick(Sender: TObject);
var
  Duration: Integer;
  Elapsed: Double;
begin
  Duration := 300 + Random(1200);
  Log('Timing started - simulating ' + Duration.ToString + ' ms operation...');

  EW.StartTiming('simulated_operation', 'sample');
  Sleep(Duration);  // Simulates a real operation (e.g. DB query, API call)
  Elapsed := EW.EndTiming('simulated_operation');

  Log('Timing ended - ' + FormatFloat('0.0', Elapsed) + ' ms reported to ExeWatch');
end;

{ ============================================================================
  BREADCRUMBS + ERROR — Capture a trail of events leading up to an error.

  Breadcrumbs are short messages that record what the user/app was doing
  before an error occurred. They give you context to understand the error
  without needing to reproduce it.

    EW.AddBreadcrumb('message', 'category');

  - The SDK keeps the last 20 breadcrumbs (older ones are dropped).
  - Breadcrumbs are automatically attached to the NEXT error/fatal event.
  - After the error is sent, call EW.ClearBreadcrumbs to reset the trail.
  - Categories are free-form strings. Common ones: 'navigation', 'ui',
    'user', 'http', 'db', 'system'.

  ErrorWithException is a convenience method that logs an exception at
  Error level, including the exception class name and message as extra data.
  ============================================================================ }
procedure TMainForm.btnBreadcrumbsErrorClick(Sender: TObject);
begin
  // Add breadcrumbs to record what happened before the error
  EW.AddBreadcrumb('User opened customer details', 'navigation');
  Log('Breadcrumb: User opened customer details');

  EW.AddBreadcrumb('Edited billing address', 'user');
  Log('Breadcrumb: Edited billing address');

  EW.AddBreadcrumb('Clicked Save', 'ui');
  Log('Breadcrumb: Clicked Save');

  // Simulate an exception — the breadcrumbs above will be attached to this error
  try
    raise Exception.Create('Save failed: invalid postal code');
  except
    on E: Exception do
    begin
      // ErrorWithException(E, tag) logs the exception class + message at Error level.
      // The breadcrumb trail is automatically included.
      EW.ErrorWithException(E, 'sample');
      Log('[ERROR] ' + E.Message + ' - check dashboard for breadcrumb trail');
    end;
  end;
end;

{ ============================================================================
  USER IDENTITY — OPTIONAL. Track which user triggered events.

  Call EW.SetUser once (e.g. after login). All subsequent logs, errors,
  and timings will include this user's info, so you can search by user
  in the ExeWatch dashboard.

    EW.SetUser('user-id', 'email', 'display-name');

  - Only the id is required; email and name are optional.
  - Call EW.ClearUser on logout.
  - User info is included in all events until cleared.
  ============================================================================ }
procedure TMainForm.btnSetUserClick(Sender: TObject);
begin
  EW.SetUser('user-42', 'jane@example.com', 'Jane Doe');
  // Send a log so you can immediately verify in the dashboard that
  // this event carries the user identity we just set.
  EW.Info('User identity configured', 'sample');
  Log('User set - id: user-42, email: jane@example.com, name: Jane Doe');
  Log('Sent a log - open the dashboard and check that this event includes the user');
end;

procedure TMainForm.btnClearUserClick(Sender: TObject);
begin
  EW.ClearUser;
  EW.Info('User identity cleared', 'sample');
  Log('User cleared');
  Log('Sent a log - open the dashboard and verify this event has no user');
end;

{ ============================================================================
  TAGS — OPTIONAL. Attach key-value metadata to all subsequent events.

  Tags are global — once set, they are included in every log, error, and
  timing until removed. Use them for cross-cutting context like environment,
  feature flags, A/B test groups, etc.

    EW.SetTag('key', 'value');     — set one tag
    EW.RemoveTag('key');           — remove one tag
    EW.ClearTags;                  — remove all tags
  ============================================================================ }
procedure TMainForm.btnSetTagsClick(Sender: TObject);
begin
  EW.SetTag('environment', 'staging');
  EW.SetTag('feature_flag', 'new_checkout');
  // Send a log so you can immediately verify in the dashboard that
  // this event carries the tags we just set.
  EW.Info('Tags configured - this event carries the additional tags', 'sample');
  Log('Tags set - environment=staging, feature_flag=new_checkout');
  Log('Sent a log - open the dashboard and check that this event includes the tags');
end;

procedure TMainForm.btnClearTagsClick(Sender: TObject);
begin
  EW.ClearTags;
  EW.Info('Tags cleared - this event has no tags', 'sample');
  Log('Tags cleared');
  Log('Sent a log - open the dashboard and verify this event has no tags');
end;

{ ============================================================================
  METRICS — OPTIONAL. Track counters and gauges.

  COUNTERS — cumulative values that only go up.
    EW.IncrementCounter('name', value, 'tag');
    value defaults to 1.0, tag defaults to ''.

    Real-world examples:
      EW.IncrementCounter('invoices_generated');        // +1 every time
      EW.IncrementCounter('emails_sent', 1, 'notify');  // tagged by subsystem
      EW.IncrementCounter('items_exported', BatchSize); // +N per batch
      EW.IncrementCounter('login_failures', 1, 'auth'); // track security events
      EW.IncrementCounter('cache_hits');                 // measure cache effectiveness
      EW.IncrementCounter('api_calls', 1, 'rest');       // count external API usage

  GAUGES — point-in-time values that go up and down.
    EW.RecordGauge('name', value, 'tag');

    Real-world examples:
      EW.RecordGauge('active_users', GetActiveUserCount);          // who's online now
      EW.RecordGauge('pending_orders', OrderQueue.Count);          // queue depth
      EW.RecordGauge('memory_mb', GetProcessMemoryMB, 'system');   // resource usage
      EW.RecordGauge('db_pool_used', Pool.ActiveCount, 'db');      // connection pool
      EW.RecordGauge('disk_free_gb', GetDiskFreeGB('C'), 'infra'); // disk monitoring
      EW.RecordGauge('cart_total_eur', Cart.Total, 'ecommerce');   // business metric

  PERIODIC GAUGES — auto-sampled on a background timer.
    EW.RegisterPeriodicGauge('name', callback, 'tag');
    The callback is called every GaugeSamplingIntervalSec (default 30s).
    Use this for values you want to monitor continuously without manual calls.

    Real-world examples:
      EW.RegisterPeriodicGauge('memory_mb',
        function: Double begin Result := GetProcessMemoryMB end, 'system');
      EW.RegisterPeriodicGauge('thread_count',
        function: Double begin Result := TThread.CurrentThread.ThreadID end, 'system');

  - Metrics are pre-aggregated in memory and flushed to ExeWatch every
    60 seconds (counters as sum, gauges as min/max/avg/last).
  - In the dashboard you get charts with trends, min, max, avg, and last value.
  ============================================================================ }
procedure TMainForm.btnIncrementCounterClick(Sender: TObject);
begin
  Inc(FPageViewCount);
  // IncrementCounter adds to the running total for this metric name.
  // The value parameter (default 1) is the amount to add.
  EW.IncrementCounter('page_views', 1, 'sample');
  Log('Counter incremented - page_views = ' + FPageViewCount.ToString);
end;

procedure TMainForm.btnRecordGaugeClick(Sender: TObject);
var
  Items: Integer;
begin
  Items := 1 + Random(10);
  // RecordGauge records a snapshot value. The SDK tracks min/max/avg/last
  // across all recordings within the 60-second flush window.
  EW.RecordGauge('cart_items', Items, 'sample');
  Log('Gauge recorded - cart_items = ' + Items.ToString);
end;

{ Clear Log }

procedure TMainForm.btnClearLogClick(Sender: TObject);
begin
  Memo1.Clear;
end;

end.
