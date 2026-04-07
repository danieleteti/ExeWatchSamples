{ *******************************************************************************
  ExeWatch DLL SDK Sample Application

  This demo shows how to use every feature of the ExeWatch SDK via the DLL
  version. The DLL allows you to use ExeWatch from any Delphi version
  (Delphi 5 through Delphi 13 Florence) without needing to compile the SDK
  source code.

  This sample uses the convenience wrappers (EWInfo, EWDebug, etc.) which
  handle the string-to-PWideChar conversion automatically for all Delphi
  versions, including pre-Unicode (Delphi 5-2007).

  Quick start:
    1. Replace the API key below with your own (from https://exewatch.com)
    2. Make sure ExeWatchSDKv1DLL.dll (32-bit) or ExeWatchSDKv1DLL_x64.dll
       (64-bit) is in the same directory as the executable
    3. Build and run (F9)
    4. Click the buttons and watch events appear in the ExeWatch dashboard

  Full docs: https://exewatch.com/ui/docs
******************************************************************************* }

unit MainFormU;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Winapi.PsAPI, Vcl.ExtCtrls;

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
    btnIncrementCounter1: TButton;
    btnRecordGauge: TButton;
    lblLog: TLabel;
    btnClearLog: TButton;
    Memo1: TMemo;
    btnSingleTiming: TButton;
    Panel1: TPanel;
    Shape1: TShape;
    Label1: TLabel;
    btnIncrementCounter2: TButton;
    btnCounter3: TButton;
    tmrPeriodicGauge: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
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
    procedure btnIncrementCounter1Click(Sender: TObject);
    procedure btnRecordGaugeClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
    procedure btnSingleTimingClick(Sender: TObject);
    procedure btnIncrementCounter2Click(Sender: TObject);
    procedure btnCounter3Click(Sender: TObject);
    procedure tmrPeriodicGaugeTimer(Sender: TObject);
  private
    procedure Log(const AMessage: string);
    procedure OnAppException(Sender: TObject; E: Exception);
  end;

var
  MainForm: TMainForm;

implementation

uses
  ExeWatchSDKv1Imports;

const
  // Replace with your actual API key from the ExeWatch dashboard
  EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY';

{$R *.dfm}

{ Returns the current process working set (physical memory) in megabytes.
  Used by the periodic gauge timer to monitor memory usage. }
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
  DiskFree(3) returns free bytes for drive C: (1=A, 2=B, 3=C, ...). }
function GetDiskFreeGB: Double;
var
  FreeBytes: Int64;
begin
  FreeBytes := DiskFree(3);
  if FreeBytes >= 0 then
    Result := FreeBytes / (1024 * 1024 * 1024)
  else
    Result := 0;
end;

{ ============================================================================
  INITIALIZATION — REQUIRED
  EWInitialize() is the only call you MUST make. Everything else (user
  identity, tags, custom device info, etc.) is optional.

  Parameters:
    - AApiKey      : your application API key (starts with "ew_win_")
    - ACustomerId  : identifies the customer/tenant using your app
    - AAppVersion  : OPTIONAL user-defined version/release tag

  NOTE: The DLL version uses convenience wrappers (EWInitialize, EWInfo, etc.)
  that accept plain Delphi strings and handle the PWideChar conversion
  automatically. This works for ALL Delphi versions, both pre-Unicode
  (Delphi 5-2007 where string = AnsiString) and Unicode (Delphi 2009+).

  VCL/FMX exception hooks are NOT available in the DLL version. Instead,
  install Application.OnException manually and call EWError from there.
  ============================================================================ }
procedure TMainForm.FormCreate(Sender: TObject);
var
  Buf: array[0..63] of WideChar;
begin
  Randomize;
  Constraints.MaxWidth := Width;
  Memo1.Clear;

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

  // Initialize the SDK via DLL
  if EWInitialize(EXEWATCH_API_KEY, 'SampleCustomer') <> EW_OK then
  begin
    ShowMessage('ExeWatch initialization failed: ' + EWGetLastErrorStr);
    Application.Terminate;
    Exit;
  end;

  // Show SDK version in the caption
  if ew_GetVersion(@Buf[0], Length(Buf)) = EW_OK then
    Caption := Caption + ' - ExeWatch SDK ' + string(PWideChar(@Buf[0]));

  // OPTIONAL — Attach custom key-value pairs to the device info sent to ExeWatch.
  EWSetCustomDeviceInfo('env', 'staging');
  EWSetCustomDeviceInfo('sample', 'DelphiWithDLLSDK');
  ew_SendCustomDeviceInfo;

  // OPTIONAL — Register periodic gauge sampling via a TTimer.
  // NOTE: The DLL version does not support RegisterPeriodicGauge (which requires
  // anonymous method callbacks). Instead, use a TTimer to sample and record
  // gauge values at regular intervals. This achieves the same result.
  tmrPeriodicGauge.Interval := 30000;  // 30 seconds, same as SDK default
  tmrPeriodicGauge.Enabled := True;

  // OPTIONAL — Install VCL exception handler to capture unhandled GUI exceptions.
  // The DLL version does not include the ExeWatchSDKv1.VCL unit, so we hook
  // Application.OnException manually to get the same behavior.
  Application.OnException := OnAppException;

  Log('ExeWatch initialized via DLL');
end;

{ Called when an unhandled VCL exception occurs. Logs it to ExeWatch and
  shows the default error dialog. This replaces the ExeWatchSDKv1.VCL unit
  which is not available in the DLL version.

  Uses EWErrorWithStackTrace to include the exception class name and stack
  trace. The stack trace is captured here because the DLL cannot hook into
  the host application's RTL exception mechanism.

  If you use a stack trace library (JCL, madExcept, EurekaLog), capture
  the trace and pass it here. Without one, pass an empty string — the
  exception class + message are still logged. }
procedure TMainForm.OnAppException(Sender: TObject; E: Exception);
var
  StackTrace: string;
begin
  // If you have JCL: StackTrace := JclDebug.GetExceptionStackInfoAsString(E);
  // If you have madExcept: StackTrace := madExcept.GetCrashStackTrace;
  // Without a stack trace library, pass empty string:
  StackTrace := '';
  EWErrorWithStackTrace(E.Message, 'exception', StackTrace, E.ClassName);
  Application.ShowException(E);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  tmrPeriodicGauge.Enabled := False;
  ew_Shutdown;
end;

{ Helper — writes a timestamped line to the local activity log (Memo). }
procedure TMainForm.Log(const AMessage: string);
begin
  Memo1.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + AMessage);
end;

{ ============================================================================
  PERIODIC GAUGE TIMER — Replacement for RegisterPeriodicGauge

  Since the DLL cannot accept anonymous method callbacks, we use a TTimer
  to sample gauge values periodically. This fires on the main thread,
  so it's safe to call any VCL methods if needed.
  ============================================================================ }
procedure TMainForm.tmrPeriodicGaugeTimer(Sender: TObject);
begin
  EWRecordGauge('memory_mb', GetWorkingSetMB, 'system');
  EWRecordGauge('disk_free_gb', GetDiskFreeGB, 'system');
end;

{ ============================================================================
  LOGGING — The core feature.

  Five severity levels: Debug, Info, Warning, Error, Fatal.
  All convenience wrappers accept plain Delphi strings.
  The optional tag parameter defaults to 'main'.
  ============================================================================ }
procedure TMainForm.btnDebugClick(Sender: TObject);
begin
  EWDebug('This is a DEBUG message', 'sample');
  Log('[DEBUG] Sent debug log');
end;

procedure TMainForm.btnInfoClick(Sender: TObject);
begin
  EWInfo('This is an INFO message', 'sample');
  Log('[INFO] Sent info log');
end;

procedure TMainForm.btnWarningClick(Sender: TObject);
begin
  EWWarning('This is a WARNING message', 'sample');
  Log('[WARNING] Sent warning log');
end;

procedure TMainForm.btnErrorClick(Sender: TObject);
begin
  EWError('This is an ERROR message', 'sample');
  Log('[ERROR] Sent error log');
end;

procedure TMainForm.btnFatalClick(Sender: TObject);
begin
  EWFatal('This is a FATAL message', 'sample');
  Log('[FATAL] Sent fatal log');
end;

{ ============================================================================
  TIMING — Measure how long operations take.

  EWStartTiming / EWEndTiming wrap the DLL calls with automatic string
  conversion. EndTiming returns the elapsed time via an out parameter.
  ============================================================================ }
procedure TMainForm.btnTimingClick(Sender: TObject);
const
  Operations: array[0..2] of string = ('Customers Query', 'Invoices Aggregate', 'Create Reports');
var
  I, Duration: Integer;
  TimingID: string;
  ElapsedMs: Double;
begin
  for I := 0 to 3 + Random(4) do
  begin
    Duration := 100 + Random(1500);
    TimingID := Operations[Random(Length(Operations))];

    Log('Timing started: Executing ' + TimingID + ' - simulating ' + IntToStr(Duration) + ' ms operation...');

    EWStartTiming(TimingID, 'sample');
    try
      Sleep(Duration);
      if Random(10) > 7 then
        raise Exception.Create('Some Error Occurred');
      EWEndTiming(TimingID, ElapsedMs);
      Log('Success');
    except
      on E: Exception do
      begin
        // End timing with failure — pass success=False via direct DLL call
        ew_EndTiming(PWideChar(EWStr(TimingID)), ElapsedMs);
        Log('Failed');
      end;
    end;
  end;
end;

procedure TMainForm.btnSingleTimingClick(Sender: TObject);
var
  Duration: Integer;
  ElapsedMs: Double;
begin
  Duration := 100 + Random(1500);
  Log('Timing started: Operation [Billing] simulating ' + IntToStr(Duration) + ' ms operation...');

  EWStartTiming('Billing', 'billing');
  try
    Sleep(Duration);
    EWEndTiming('Billing', ElapsedMs);
    Log('Success');
  except
    on E: Exception do
    begin
      ew_EndTiming(PWideChar(EWStr('Billing')), ElapsedMs);
      Log('Failed');
      raise;
    end;
  end;
end;

{ ============================================================================
  BREADCRUMBS + ERROR — Capture a trail of events leading up to an error.

  EWAddBreadcrumb records what the user/app was doing before an error.
  The SDK keeps the last 20 breadcrumbs and attaches them to the next
  error/fatal event.
  ============================================================================ }
procedure TMainForm.btnBreadcrumbsErrorClick(Sender: TObject);
begin
  EWAddBreadcrumb(EW_BT_NAVIGATION, 'navigation', 'User opened customer details');
  Log('Breadcrumb: User opened customer details');

  EWAddBreadcrumb(EW_BT_USER, 'user', 'Edited billing address');
  Log('Breadcrumb: Edited billing address');

  EWAddBreadcrumb(EW_BT_CLICK, 'ui', 'Clicked Save');
  Log('Breadcrumb: Clicked Save');

  // Simulate an exception — the breadcrumbs above will be attached to this error
  raise Exception.Create('Save failed: invalid postal code');

  ew_ClearBreadcrumbs;
end;

{ ============================================================================
  USER IDENTITY — OPTIONAL. Track which user triggered events.
  ============================================================================ }
procedure TMainForm.btnSetUserClick(Sender: TObject);
begin
  EWSetUser('user-42', 'jane@example.com', 'Jane Doe');
  EWInfo('User identity configured', 'sample');
  Log('User set - id: user-42, email: jane@example.com, name: Jane Doe');
  Log('Sent a log - open the dashboard and check that this event includes the user');
end;

procedure TMainForm.btnClearUserClick(Sender: TObject);
begin
  ew_ClearUser;
  EWInfo('User identity cleared', 'sample');
  Log('User cleared');
  Log('Sent a log - open the dashboard and verify this event has no user');
end;

{ ============================================================================
  TAGS — OPTIONAL. Attach key-value metadata to all subsequent events.
  ============================================================================ }
procedure TMainForm.btnSetTagsClick(Sender: TObject);
begin
  EWSetTag('environment', 'staging');
  EWSetTag('feature_flag', 'new_checkout');
  EWInfo('Tags configured - this event carries the additional tags', 'sample');
  Log('Tags set - environment=staging, feature_flag=new_checkout');
  Log('Sent a log - open the dashboard and check that this event includes the tags');
end;

procedure TMainForm.btnClearTagsClick(Sender: TObject);
begin
  ew_ClearTags;
  EWInfo('Tags cleared - this event has no tags', 'sample');
  Log('Tags cleared');
  Log('Sent a log - open the dashboard and verify this event has no tags');
end;

{ ============================================================================
  METRICS — OPTIONAL. Track counters and gauges.

  COUNTERS — cumulative values that only go up.
  GAUGES — point-in-time values that go up and down.

  NOTE: Periodic gauges are handled by tmrPeriodicGauge (TTimer) instead
  of RegisterPeriodicGauge, since the DLL cannot accept callback closures.
  ============================================================================ }
procedure TMainForm.btnIncrementCounter1Click(Sender: TObject);
begin
  EWIncrementCounter('orders.new', 1, 'wharehouse');
  Log('Counter incremented');
end;

procedure TMainForm.btnIncrementCounter2Click(Sender: TObject);
begin
  EWIncrementCounter('orders.shipped', 1, 'sample');
  Log('Counter incremented');
end;

procedure TMainForm.btnCounter3Click(Sender: TObject);
begin
  EWIncrementCounter('orders.billed', 1, 'wharehouse');
  Log('Counter incremented');
end;

procedure TMainForm.btnRecordGaugeClick(Sender: TObject);
var
  Items: Integer;
begin
  Items := 1 + Random(10);
  EWRecordGauge('cart_items', Items, 'sample');
  Log('Gauge recorded - cart_items = ' + IntToStr(Items));
end;

{ Clear Log }

procedure TMainForm.btnClearLogClick(Sender: TObject);
begin
  Memo1.Clear;
end;

end.
