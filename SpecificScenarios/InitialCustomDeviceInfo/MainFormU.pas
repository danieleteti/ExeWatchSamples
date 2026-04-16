{ *******************************************************************************
  ExeWatch — GlobalTags + InitialCustomDeviceInfo sample

  Shows how to attach environment metadata to the very first events sent by
  the SDK, so they are visible in the dashboard from the moment the app starts.

  Two mechanisms:

    Config.GlobalTags
      Tags applied to ALL log events, starting from "Application started".
      Equivalent to calling SetTag before the first log — which is normally
      impossible because the startup log is emitted during InitializeExeWatch.

    Config.InitialCustomDeviceInfo
      Key-value pairs sent with the device-info payload (hardware, OS, etc.).
      Visible in the Devices section of the dashboard.

  Use GlobalTags for data you want to filter/search in LOGS (e.g. session
  type, deployment mode).  Use InitialCustomDeviceInfo for environment details
  that describe the DEVICE (e.g. screen resolution, color depth).

  Full docs: https://exewatch.com/ui/docs
******************************************************************************* }

unit MainFormU;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls;

type
  TMainForm = class(TForm)
    Memo1: TMemo;
    lblInfo: TLabel;
    procedure FormCreate(Sender: TObject);
  private
    procedure Log(const AMessage: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.Generics.Collections,
  ExeWatchSDKv1;

const
  // Replace with your actual API key from the ExeWatch dashboard
//  EXEWATCH_API_KEY = 'ew_win_FDYE6Jfu9rojpDMekuAGwRFCoh3e-qDsUAVtrnh7DQo'; //remoto
  EXEWATCH_API_KEY = 'ew_win_STfZFFFiFuDS_U_VFZgx_jMEV-huDt2-gwPnOY7BmYM';
{$R *.dfm}

{ ---------------------------------------------------------------------------
  Session-type detection helpers.

  These use standard Windows APIs to determine whether the application is
  running on a local console, via RDP, or inside a Terminal Server / Citrix
  session.
  --------------------------------------------------------------------------- }

const
  SM_REMOTESESSION = $1000;

function DetectSessionType: string;
var
  SessionName: string;
begin
  // 1. Check the SESSIONNAME environment variable (set by Windows)
  //    'Console' = local desktop, 'RDP-Tcp#...' = RDP, 'ICA-...' = Citrix
  SessionName := GetEnvironmentVariable('SESSIONNAME');
  if SessionName <> '' then
  begin
    if SessionName.StartsWith('RDP', True) then
      Exit('RDP');
    if SessionName.StartsWith('ICA', True) then
      Exit('Citrix');
    if SameText(SessionName, 'Console') then
      Exit('Desktop');
  end;

  // 2. Fallback: SM_REMOTESESSION detects any remote session
  if GetSystemMetrics(SM_REMOTESESSION) <> 0 then
    Exit('RemoteSession');

  Result := 'Desktop';
end;

function DetectColorDepth: string;
var
  DC: HDC;
begin
  DC := GetDC(0);
  try
    Result := IntToStr(GetDeviceCaps(DC, BITSPIXEL)) + 'bpp';
  finally
    ReleaseDC(0, DC);
  end;
end;

function DetectScreenResolution: string;
begin
  Result := Format('%dx%d', [
    GetSystemMetrics(SM_CXSCREEN),
    GetSystemMetrics(SM_CYSCREEN)]);
end;

{ ---------------------------------------------------------------------------
  Initialization — the core of this sample.

  Instead of the simple one-liner:
    InitializeExeWatch(API_KEY, CUSTOMER_ID);

  we build a TExeWatchConfig and populate:
    - GlobalTags: appear on the "Application started" log and all subsequent
      events (just like SetTag, but applied before the first log).
    - InitialCustomDeviceInfo: sent with the device-info payload to the
      Devices section of the dashboard.
  --------------------------------------------------------------------------- }

procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
  SessionType: string;
begin
  Memo1.Clear;

  if EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY' then
  begin
    ShowMessage(
      'API Key Not Configured' + sLineBreak + sLineBreak +
      'Open MainFormU.pas and replace EXEWATCH_API_KEY with your actual key.' + sLineBreak +
      'Get one from: https://exewatch.com');
    Application.Terminate;
    Exit;
  end;

  SessionType := DetectSessionType;

  Config := TExeWatchConfig.Create(EXEWATCH_API_KEY, 'SampleCustomer');

  // GlobalTags — these appear on the "Application started" log event
  // and on every subsequent log, just like calling SetTag().
  Config.GlobalTags := [
    TPair<string, string>.Create('session_type', SessionType)
  ];

  // InitialCustomDeviceInfo — these appear in the Devices dashboard section,
  // attached to the hardware/OS info payload.
  Config.InitialCustomDeviceInfo := [
    TPair<string, string>.Create('session_type',  SessionType),
    TPair<string, string>.Create('screen_res',    DetectScreenResolution),
    TPair<string, string>.Create('color_depth',   DetectColorDepth)
  ];

  InitializeExeWatch(Config);

  Log('ExeWatch initialized (SDK ' + EXEWATCH_SDK_VERSION + ')');
  Log('');
  Log('GlobalTags (on every log, including "Application started"):');
  Log('  session_type = ' + SessionType);
  Log('');
  Log('InitialCustomDeviceInfo (in Devices dashboard):');
  Log('  session_type = ' + SessionType);
  Log('  screen_res   = ' + DetectScreenResolution);
  Log('  color_depth  = ' + DetectColorDepth);
  Log('');
  Log('Open the ExeWatch dashboard to verify:');
  Log('  - Logs > first event has tag "session_type"');
  Log('  - Devices > device details show screen_res, color_depth');
end;

procedure TMainForm.Log(const AMessage: string);
begin
  Memo1.Lines.Add(AMessage);
end;

end.
