{ *******************************************************************************
  ExeWatch - Android FMX Sample

  A single-screen FMX application targeting Android that exercises every
  feature of the ExeWatch Delphi SDK: log levels, exception capture,
  breadcrumbs, timings, user identity, global tags, customer ID, device
  info, metrics (counter / gauge / periodic), background-thread usage,
  flush, and diagnostics.

  Why a dedicated Android sample (instead of reusing the FMX desktop one):

    - The UI is built programmatically in FormCreate so it renders
      sensibly on a phone screen (narrow, scrollable vertical layout)
      without depending on a Form Designer preview device.
    - The FMX hook (ExeWatchSDKv1.FMX) is used on mobile exactly like
      on desktop - unhandled FMX exceptions are captured by
      Application.OnException. Android apps crash differently than
      Windows, so "Unhandled Exception (FMX)" is especially useful to
      verify that ExeWatch captures the crash before the app tears down.
    - Hardware / device info collected by the SDK is Android-specific
      (model, manufacturer, OS version, screen density, etc.) - it's
      worth having a sample where that payload is the primary thing you
      are verifying in the dashboard.

  Quick start:

    1. Sign up at https://exewatch.com (free Hobby plan, no credit card).
    2. Create an Application with platform = Android in the dashboard.
       You will receive an API key starting with 'ew_and_'.
    3. Open MainFormU.pas and replace EXEWATCH_API_KEY below with your key.
    4. Optionally change CUSTOMER_ID to something meaningful (the dashboard
       uses it to group events; it can be any string).
    5. Select the Android target in Project Manager, deploy to a device
       or emulator (F9).
    6. Tap the buttons and watch events appear in the ExeWatch dashboard.

  Full docs: https://exewatch.com/ui/docs
******************************************************************************* }

unit MainFormU;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.JSON, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Layouts, FMX.Objects,
  ExeWatchSDKv1, ExeWatchSDKv1.FMX;

type
  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FScrollBox: TVertScrollBox;
    FLogMemo: TText;
    FLogLines: TStringList;
    FCurrentY: Single;
    procedure AddSectionLabel(const AText: string);
    function AddButton(const AText: string; AOnClick: TNotifyEvent): TButton;
    procedure AppendLog(const AMsg: string);

    // Log levels
    procedure OnDebugClick(Sender: TObject);
    procedure OnInfoClick(Sender: TObject);
    procedure OnWarningClick(Sender: TObject);
    procedure OnErrorClick(Sender: TObject);
    procedure OnFatalClick(Sender: TObject);
    procedure OnFormatLogClick(Sender: TObject);

    // Exceptions
    procedure OnCaptureExceptionClick(Sender: TObject);
    procedure OnErrorWithExceptionClick(Sender: TObject);
    procedure OnUnhandledExceptionClick(Sender: TObject);

    // Breadcrumbs
    procedure OnAddBreadcrumbClick(Sender: TObject);
    procedure OnAddTypedBreadcrumbClick(Sender: TObject);
    procedure OnGetBreadcrumbsClick(Sender: TObject);
    procedure OnClearBreadcrumbsClick(Sender: TObject);
    procedure OnBreadcrumbThenErrorClick(Sender: TObject);

    // Timing
    procedure OnStartTimingClick(Sender: TObject);
    procedure OnEndTimingClick(Sender: TObject);
    procedure OnQuickTimingClick(Sender: TObject);
    procedure OnActiveTimingsClick(Sender: TObject);

    // User identity
    procedure OnSetUserClick(Sender: TObject);
    procedure OnGetUserClick(Sender: TObject);
    procedure OnClearUserClick(Sender: TObject);

    // Tags
    procedure OnSetTagsClick(Sender: TObject);
    procedure OnGetTagsClick(Sender: TObject);
    procedure OnClearTagsClick(Sender: TObject);

    // Customer ID
    procedure OnSetCustomerIdClick(Sender: TObject);
    procedure OnGetCustomerIdClick(Sender: TObject);

    // Device info
    procedure OnSendDeviceInfoClick(Sender: TObject);
    procedure OnSetCustomDeviceInfoClick(Sender: TObject);
    procedure OnSendCustomDeviceInfoClick(Sender: TObject);

    // Metrics
    procedure OnIncrementCounterClick(Sender: TObject);
    procedure OnRecordGaugeClick(Sender: TObject);
    procedure OnRegisterPeriodicGaugeClick(Sender: TObject);
    procedure OnUnregisterPeriodicGaugeClick(Sender: TObject);

    // Background thread
    procedure OnBackgroundLogClick(Sender: TObject);
    procedure OnBackgroundTimingClick(Sender: TObject);
    procedure OnBackgroundBreadcrumbClick(Sender: TObject);
    procedure OnBackgroundExceptionClick(Sender: TObject);

    // Flush & diagnostics
    procedure OnFlushClick(Sender: TObject);
    procedure OnPendingCountClick(Sender: TObject);
    procedure OnSessionIdClick(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

const
  // Replace with your actual API key from the ExeWatch dashboard.
  // Android keys are prefixed with 'ew_and_'.
  EXEWATCH_API_KEY = 'ew_and_xxxxxx_USE_YOUR_OWN_KEY';
  CUSTOMER_ID      = 'AndroidSample';

  BTN_HEIGHT     = 50;
  BTN_MARGIN     = 6;
  SECTION_HEIGHT = 36;
  SIDE_PADDING   = 12;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FLogLines := TStringList.Create;

  if EXEWATCH_API_KEY = 'ew_and_xxxxxx_USE_YOUR_OWN_KEY' then
  begin
    ShowMessage(
      'API Key Not Configured' + sLineBreak + sLineBreak +
      'Open MainFormU.pas and replace EXEWATCH_API_KEY with your actual key.' + sLineBreak +
      'Get one from: https://exewatch.com');
    Application.Terminate;
    Exit;
  end;

  InitializeExeWatch(EXEWATCH_API_KEY, CUSTOMER_ID);

  // Scrollable container
  FScrollBox := TVertScrollBox.Create(Self);
  FScrollBox.Parent := Self;
  FScrollBox.Align := TAlignLayout.Client;
  FCurrentY := 10;

  // === LOG LEVELS ===
  AddSectionLabel('Log Levels');
  AddButton('Debug', OnDebugClick);
  AddButton('Info', OnInfoClick);
  AddButton('Warning', OnWarningClick);
  AddButton('Error', OnErrorClick);
  AddButton('Fatal', OnFatalClick);
  AddButton('Format Log (args)', OnFormatLogClick);

  // === EXCEPTIONS ===
  AddSectionLabel('Exceptions');
  AddButton('Capture Exception', OnCaptureExceptionClick);
  AddButton('Error With Exception', OnErrorWithExceptionClick);
  AddButton('Unhandled Exception (FMX)', OnUnhandledExceptionClick);

  // === BREADCRUMBS ===
  AddSectionLabel('Breadcrumbs');
  AddButton('Add Breadcrumb', OnAddBreadcrumbClick);
  AddButton('Add Typed Breadcrumb', OnAddTypedBreadcrumbClick);
  AddButton('Get Breadcrumbs', OnGetBreadcrumbsClick);
  AddButton('Clear Breadcrumbs', OnClearBreadcrumbsClick);
  AddButton('Breadcrumbs + Error', OnBreadcrumbThenErrorClick);

  // === TIMING ===
  AddSectionLabel('Timing / Profiling');
  AddButton('Start Timing "load_data"', OnStartTimingClick);
  AddButton('End Timing "load_data"', OnEndTimingClick);
  AddButton('Quick Timing (500ms)', OnQuickTimingClick);
  AddButton('Active Timings', OnActiveTimingsClick);

  // === USER IDENTITY ===
  AddSectionLabel('User Identity');
  AddButton('Set User', OnSetUserClick);
  AddButton('Get User', OnGetUserClick);
  AddButton('Clear User', OnClearUserClick);

  // === TAGS ===
  AddSectionLabel('Global Tags');
  AddButton('Set Tags', OnSetTagsClick);
  AddButton('Get Tags', OnGetTagsClick);
  AddButton('Clear Tags', OnClearTagsClick);

  // === CUSTOMER ID ===
  AddSectionLabel('Customer ID');
  AddButton('Set Customer ID', OnSetCustomerIdClick);
  AddButton('Get Customer ID', OnGetCustomerIdClick);

  // === DEVICE INFO ===
  AddSectionLabel('Device Info');
  AddButton('Send Device Info', OnSendDeviceInfoClick);
  AddButton('Set Custom Device Info', OnSetCustomDeviceInfoClick);
  AddButton('Send Custom Device Info', OnSendCustomDeviceInfoClick);

  // === METRICS ===
  AddSectionLabel('Metrics');
  AddButton('Increment Counter', OnIncrementCounterClick);
  AddButton('Record Gauge', OnRecordGaugeClick);
  AddButton('Register Periodic Gauge', OnRegisterPeriodicGaugeClick);
  AddButton('Unregister Periodic Gauge', OnUnregisterPeriodicGaugeClick);

  // === BACKGROUND THREAD ===
  AddSectionLabel('Background Thread');
  AddButton('BG: Log from Thread', OnBackgroundLogClick);
  AddButton('BG: Timing from Thread', OnBackgroundTimingClick);
  AddButton('BG: Breadcrumb from Thread', OnBackgroundBreadcrumbClick);
  AddButton('BG: Exception from Thread', OnBackgroundExceptionClick);

  // === FLUSH & DIAGNOSTICS ===
  AddSectionLabel('Flush & Diagnostics');
  AddButton('Flush Now', OnFlushClick);
  AddButton('Pending Count', OnPendingCountClick);
  AddButton('Session ID', OnSessionIdClick);

  // === LOG OUTPUT ===
  AddSectionLabel('Output');
  FLogMemo := TText.Create(Self);
  FLogMemo.Parent := FScrollBox;
  FLogMemo.Position.X := SIDE_PADDING;
  FLogMemo.Position.Y := FCurrentY;
  FLogMemo.Width := FScrollBox.Width - SIDE_PADDING * 2;
  FLogMemo.Height := 300;
  FLogMemo.TextSettings.FontColor := TAlphaColorRec.Black;
  FLogMemo.TextSettings.Font.Size := 12;
  FLogMemo.TextSettings.HorzAlign := TTextAlign.Leading;
  FLogMemo.TextSettings.VertAlign := TTextAlign.Leading;
  FLogMemo.TextSettings.WordWrap := True;
  FLogMemo.Text := 'Ready.';
  FCurrentY := FCurrentY + 300 + BTN_MARGIN;

  AppendLog('ExeWatch initialized. SDK v' + EXEWATCH_SDK_VERSION);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FLogLines.Free;
end;

procedure TMainForm.AddSectionLabel(const AText: string);
var
  Lbl: TLabel;
begin
  FCurrentY := FCurrentY + 6;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := FScrollBox;
  Lbl.Text := AText;
  Lbl.Position.X := SIDE_PADDING;
  Lbl.Position.Y := FCurrentY;
  Lbl.Width := FScrollBox.Width - SIDE_PADDING * 2;
  Lbl.Height := SECTION_HEIGHT;
  Lbl.StyledSettings := [];
  Lbl.TextSettings.FontColor := TAlphaColorRec.Navy;
  Lbl.TextSettings.Font.Size := 16;
  Lbl.TextSettings.Font.Style := [TFontStyle.fsBold];
  FCurrentY := FCurrentY + SECTION_HEIGHT;
end;

function TMainForm.AddButton(const AText: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FScrollBox;
  Result.Text := AText;
  Result.Position.X := SIDE_PADDING;
  Result.Position.Y := FCurrentY;
  Result.Width := FScrollBox.Width - SIDE_PADDING * 2;
  Result.Height := BTN_HEIGHT;
  Result.OnClick := AOnClick;
  FCurrentY := FCurrentY + BTN_HEIGHT + BTN_MARGIN;
end;

procedure TMainForm.AppendLog(const AMsg: string);
begin
  FLogLines.Add(TimeToStr(Now) + ' ' + AMsg);
  // Keep last 30 lines
  while FLogLines.Count > 30 do
    FLogLines.Delete(0);
  if FLogMemo <> nil then
    FLogMemo.Text := FLogLines.Text;
end;

// ============================================================
// LOG LEVELS
// ============================================================

procedure TMainForm.OnDebugClick(Sender: TObject);
begin
  EW.Debug('Debug message from Android', 'test');
  AppendLog('Sent DEBUG');
end;

procedure TMainForm.OnInfoClick(Sender: TObject);
begin
  EW.Info('Info message from Android', 'test');
  AppendLog('Sent INFO');
end;

procedure TMainForm.OnWarningClick(Sender: TObject);
begin
  EW.Warning('Warning message from Android', 'test');
  AppendLog('Sent WARNING');
end;

procedure TMainForm.OnErrorClick(Sender: TObject);
begin
  EW.Error('Error message from Android', 'test');
  AppendLog('Sent ERROR');
end;

procedure TMainForm.OnFatalClick(Sender: TObject);
begin
  EW.Fatal('Fatal message from Android', 'test');
  AppendLog('Sent FATAL');
end;

procedure TMainForm.OnFormatLogClick(Sender: TObject);
begin
  EW.Info('User %s logged in from %s (attempt %d)', ['john', '192.168.1.1', 3], 'auth');
  AppendLog('Sent formatted INFO');
end;

// ============================================================
// EXCEPTIONS
// ============================================================

procedure TMainForm.OnCaptureExceptionClick(Sender: TObject);
begin
  try
    raise EArgumentException.Create('Test argument exception');
  except
    on E: Exception do
    begin
      EW.ErrorWithException(E, 'exceptions');
      AppendLog('Captured: ' + E.Message);
    end;
  end;
end;

procedure TMainForm.OnErrorWithExceptionClick(Sender: TObject);
begin
  try
    raise EProgrammerNotFound.Create('Where is the programmer?');
  except
    on E: Exception do
    begin
      EW.ErrorWithException(E, 'exceptions', 'Additional context info');
      AppendLog('ErrorWithException: ' + E.Message);
    end;
  end;
end;

procedure TMainForm.OnUnhandledExceptionClick(Sender: TObject);
begin
  // This will be caught by ExeWatchSDKv1.FMX hook (Application.OnException)
  AppendLog('Raising unhandled exception...');
  raise EInvalidOperation.Create('Unhandled FMX exception test');
end;

// ============================================================
// BREADCRUMBS
// ============================================================

procedure TMainForm.OnAddBreadcrumbClick(Sender: TObject);
begin
  EW.AddBreadcrumb('User tapped button', 'ui');
  AppendLog('Added breadcrumb');
end;

procedure TMainForm.OnAddTypedBreadcrumbClick(Sender: TObject);
begin
  EW.AddBreadcrumb(btNavigation, 'navigation', 'Opened Settings screen');
  AppendLog('Added typed breadcrumb (navigation)');
end;

procedure TMainForm.OnGetBreadcrumbsClick(Sender: TObject);
var
  Crumbs: TArray<TBreadcrumb>;
begin
  Crumbs := EW.GetBreadcrumbs;
  AppendLog('Breadcrumbs: ' + Length(Crumbs).ToString);
end;

procedure TMainForm.OnClearBreadcrumbsClick(Sender: TObject);
begin
  EW.ClearBreadcrumbs;
  AppendLog('Breadcrumbs cleared');
end;

procedure TMainForm.OnBreadcrumbThenErrorClick(Sender: TObject);
begin
  EW.AddBreadcrumb('Opened main screen', 'navigation');
  EW.AddBreadcrumb('Loaded customer list', 'data');
  EW.AddBreadcrumb('Clicked export button', 'ui');
  EW.Error('Export failed: disk full', 'export');
  AppendLog('Sent 3 breadcrumbs + error');
end;

// ============================================================
// TIMING / PROFILING
// ============================================================

procedure TMainForm.OnStartTimingClick(Sender: TObject);
begin
  EW.StartTiming('load_data', 'database');
  AppendLog('Started timing "load_data"');
end;

procedure TMainForm.OnEndTimingClick(Sender: TObject);
var
  Elapsed: Double;
begin
  Elapsed := EW.EndTiming('load_data');
  if Elapsed >= 0 then
    AppendLog('Ended timing: ' + FormatFloat('0.00', Elapsed) + ' ms')
  else
    AppendLog('No active timing "load_data"');
end;

procedure TMainForm.OnQuickTimingClick(Sender: TObject);
begin
  EW.StartTiming('quick_op', 'perf');
  AppendLog('Started quick timing, sleeping 500ms...');
  TThread.CreateAnonymousThread(
    procedure
    var
      Elapsed: Double;
    begin
      Sleep(500);
      Elapsed := EW.EndTiming('quick_op');
      TThread.Synchronize(nil,
        procedure
        begin
          AppendLog('Quick timing done: ' + FormatFloat('0.00', Elapsed) + ' ms');
        end);
    end).Start;
end;

procedure TMainForm.OnActiveTimingsClick(Sender: TObject);
var
  Timings: TArray<TActiveTimingInfo>;
  I: Integer;
begin
  Timings := EW.GetActiveTimings;
  if Length(Timings) = 0 then
    AppendLog('No active timings')
  else
    for I := 0 to High(Timings) do
      AppendLog('Active: ' + Timings[I].Id + ' (' + Timings[I].Tag + ')');
end;

// ============================================================
// USER IDENTITY
// ============================================================

procedure TMainForm.OnSetUserClick(Sender: TObject);
begin
  EW.SetUser('user_42', 'john@example.com', 'John Doe');
  AppendLog('User set: john@example.com');
end;

procedure TMainForm.OnGetUserClick(Sender: TObject);
var
  User: TUserIdentity;
begin
  User := EW.GetUser;
  if User.Id <> '' then
    AppendLog('User: ' + User.Name + ' (' + User.Email + ') ID=' + User.Id)
  else
    AppendLog('No user set');
end;

procedure TMainForm.OnClearUserClick(Sender: TObject);
begin
  EW.ClearUser;
  AppendLog('User cleared');
end;

// ============================================================
// GLOBAL TAGS
// ============================================================

procedure TMainForm.OnSetTagsClick(Sender: TObject);
begin
  EW.SetTag('environment', 'staging');
  EW.SetTag('build', 'debug');
  EW.SetTag('region', 'eu-west');
  AppendLog('Set 3 tags');
end;

procedure TMainForm.OnGetTagsClick(Sender: TObject);
var
  Tags: TArray<TPair<string, string>>;
  Tag: TPair<string, string>;
begin
  Tags := EW.GetTags;
  if Length(Tags) = 0 then
    AppendLog('No tags set')
  else
    for Tag in Tags do
      AppendLog('Tag: ' + Tag.Key + '=' + Tag.Value);
end;

procedure TMainForm.OnClearTagsClick(Sender: TObject);
begin
  EW.ClearTags;
  AppendLog('Tags cleared');
end;

// ============================================================
// CUSTOMER ID
// ============================================================

procedure TMainForm.OnSetCustomerIdClick(Sender: TObject);
begin
  EW.SetCustomerId('acme_corp_123');
  AppendLog('Customer ID set: acme_corp_123');
end;

procedure TMainForm.OnGetCustomerIdClick(Sender: TObject);
begin
  AppendLog('Customer ID: ' + EW.GetCustomerId);
end;

// ============================================================
// DEVICE INFO
// ============================================================

procedure TMainForm.OnSendDeviceInfoClick(Sender: TObject);
begin
  EW.SendDeviceInfo;
  AppendLog('Device info sent');
end;

procedure TMainForm.OnSetCustomDeviceInfoClick(Sender: TObject);
begin
  EW.SetCustomDeviceInfo('store', 'Google Play');
  EW.SetCustomDeviceInfo('install_source', 'organic');
  EW.SetCustomDeviceInfo('premium', 'true');
  AppendLog('Set 3 custom device info keys');
end;

procedure TMainForm.OnSendCustomDeviceInfoClick(Sender: TObject);
begin
  EW.SendCustomDeviceInfo;
  AppendLog('Custom device info sent');
end;

// ============================================================
// METRICS
// ============================================================

procedure TMainForm.OnIncrementCounterClick(Sender: TObject);
begin
  EW.IncrementCounter('button_clicks', 1.0, 'ui');
  EW.IncrementCounter('api_calls', 1.0, 'network');
  AppendLog('Incremented 2 counters');
end;

procedure TMainForm.OnRecordGaugeClick(Sender: TObject);
var
  MemVal: Double;
begin
  MemVal := 150 + Random(100);
  EW.RecordGauge('memory_mb', MemVal, 'system');
  AppendLog('Recorded gauge: memory_mb=' + FormatFloat('0.0', MemVal));
end;

procedure TMainForm.OnRegisterPeriodicGaugeClick(Sender: TObject);
begin
  EW.RegisterPeriodicGauge('random_value',
    function: Double
    begin
      Result := Random(1000);
    end, 'test');
  AppendLog('Registered periodic gauge "random_value"');
end;

procedure TMainForm.OnUnregisterPeriodicGaugeClick(Sender: TObject);
begin
  EW.UnregisterPeriodicGauge('random_value');
  AppendLog('Unregistered periodic gauge "random_value"');
end;

// ============================================================
// BACKGROUND THREAD
// ============================================================

procedure TMainForm.OnBackgroundLogClick(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      EW.Info('Log from background thread', 'background');
      EW.Warning('Warning from background thread', 'background');
      TThread.Synchronize(nil,
        procedure
        begin
          AppendLog('BG: Sent Info + Warning from thread');
        end);
    end).Start;
end;

procedure TMainForm.OnBackgroundTimingClick(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Elapsed: Double;
    begin
      EW.StartTiming('bg_work', 'background');
      Sleep(300);
      Elapsed := EW.EndTiming('bg_work');
      TThread.Synchronize(nil,
        procedure
        begin
          AppendLog('BG: Timing done: ' + FormatFloat('0.00', Elapsed) + ' ms');
        end);
    end).Start;
end;

procedure TMainForm.OnBackgroundBreadcrumbClick(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      EW.AddBreadcrumb('BG: Started sync', 'sync');
      EW.AddBreadcrumb('BG: Downloaded data', 'sync');
      EW.AddBreadcrumb('BG: Parsed response', 'sync');
      EW.Error('BG: Sync failed - timeout', 'sync');
      TThread.Synchronize(nil,
        procedure
        begin
          AppendLog('BG: 3 breadcrumbs + error from thread');
        end);
    end).Start;
end;

procedure TMainForm.OnBackgroundExceptionClick(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        raise Exception.Create('config.json not found');
      except
        on E: Exception do
        begin
          EW.ErrorWithException(E, 'background', 'Background file operation');
          TThread.Synchronize(nil,
            procedure
            begin
              AppendLog('BG: Exception captured from thread');
            end);
        end;
      end;
    end).Start;
end;

// ============================================================
// FLUSH & DIAGNOSTICS
// ============================================================

procedure TMainForm.OnFlushClick(Sender: TObject);
begin
  EW.Flush;
  AppendLog('Flush requested');
end;

procedure TMainForm.OnPendingCountClick(Sender: TObject);
begin
  AppendLog('Pending files: ' + EW.GetPendingCount.ToString);
end;

procedure TMainForm.OnSessionIdClick(Sender: TObject);
begin
  AppendLog('Session ID: ' + EW.SessionId);
  AppendLog('Pending files: ' + EW.GetPendingCount.ToString);
  AppendLog('SDK version: ' + EXEWATCH_SDK_VERSION);
  AppendLog('Enabled: ' + BoolToStr(EW.Enabled, True));
end;

end.
