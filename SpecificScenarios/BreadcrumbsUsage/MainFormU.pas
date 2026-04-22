{ *******************************************************************************
  ExeWatch - Breadcrumbs Usage sample

  Answers the most common questions about breadcrumb usage:

    Q1. Do I add breadcrumbs in batches (4 AddBreadcrumb calls in a row)?
        -> NO. Scatter them across event handlers, not as a batch. They
           accumulate in a per-thread FIFO (max 20) and are attached to
           the next Error/Fatal log.

    Q2. Does ExeWatch call EW.Error automatically, or do I call it myself?
        -> BOTH, depending on the case:
             Unhandled exception    -> auto-captured (ExceptProc + VCL hook)
             Caught exception       -> YOU call EW.ErrorWithException(E)
             Logical error          -> YOU call EW.Error('...', 'tag')

    Q3. When are breadcrumbs attached to a log event?
        -> Only to ERROR and FATAL level logs, never to Info/Warning/Debug.
        -> After attach, the breadcrumb queue is cleared.

  This sample has four buttons that exercise each path:

    "Open Settings Screen"      - just adds a navigation breadcrumb.
    "Save (caught)"             - adds breadcrumbs, then raises + catches an
                                  Exception and logs via EW.ErrorWithException.
                                  Breadcrumbs get attached to the ERROR log.
    "Crash (unhandled)"         - adds breadcrumbs, then raises an Access
                                  Violation without try/except. The SDK's
                                  VCL hook logs it as FATAL automatically.
                                  Breadcrumbs attach, app keeps running.
    "Info log (no breadcrumbs)" - adds a breadcrumb, then EW.Info. You will
                                  NOT see breadcrumbs on this log - they are
                                  only attached to Error/Fatal.

  Full docs: https://exewatch.com/ui/docs#breadcrumbs
******************************************************************************* }

unit MainFormU;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls;

type
  TMainForm = class(TForm)
    btnOpenSettings: TButton;
    btnSaveCaught: TButton;
    btnSimulateCrash: TButton;
    btnLogInfo: TButton;
    Memo1: TMemo;
    lblInfo: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure btnOpenSettingsClick(Sender: TObject);
    procedure btnSaveCaughtClick(Sender: TObject);
    procedure btnSimulateCrashClick(Sender: TObject);
    procedure btnLogInfoClick(Sender: TObject);
  private
    procedure Log(const AMessage: string);
    procedure FakeSaveToDatabase;
    procedure FakeNotifyBackend;
  end;

var
  MainForm: TMainForm;

implementation

uses
  ExeWatchSDKv1;

const
  // Replace with your actual API key from the ExeWatch dashboard
  EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY';
  CUSTOMER_ID      = 'BreadcrumbsSample';

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
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

  InitializeExeWatch(EXEWATCH_API_KEY, CUSTOMER_ID);

  Log('ExeWatch breadcrumbs sample ready (SDK ' + EXEWATCH_SDK_VERSION + ')');
  Log('');
  Log('Click the buttons IN ORDER. Breadcrumbs accumulate in a per-thread');
  Log('FIFO (max 20). They are attached to the NEXT Error/Fatal log.');
  Log('');
end;

{ Button 1 - just a navigation breadcrumb, no log generated.
  Demonstrates: breadcrumbs are added where the action happens. }
procedure TMainForm.btnOpenSettingsClick(Sender: TObject);
begin
  EW.AddBreadcrumb(btNavigation, 'router', 'Opened Settings screen');
  Log('[+] breadcrumb added: "Opened Settings screen"');
  Log('    (no log sent - breadcrumbs are just buffered until Error/Fatal)');
end;

{ Button 2 - CAUGHT exception.
  Demonstrates: breadcrumbs scattered across code, then a caught exception
  manually forwarded to ExeWatch via EW.ErrorWithException. The SDK attaches
  all breadcrumbs from THIS thread to the error event. }
procedure TMainForm.btnSaveCaughtClick(Sender: TObject);
begin
  EW.AddBreadcrumb(btClick, 'ui', 'Clicked "Save" button');

  try
    EW.AddBreadcrumb(btQuery, 'db', 'UPDATE users SET name = ''John''');
    FakeSaveToDatabase;  // raises

    EW.AddBreadcrumb(btHttp, 'api', 'POST /api/settings');  // not reached
    FakeNotifyBackend;
  except
    on E: Exception do
    begin
      // Manual log: the three breadcrumbs above are attached to this Error,
      // then the queue is cleared.
      EW.ErrorWithException(E, 'settings');
      Log('[!] caught exception - EW.ErrorWithException(E) logged as Error');
      Log('    breadcrumbs attached: "Clicked Save", "UPDATE users ..."');
    end;
  end;
end;

{ Button 3 - UNHANDLED exception.
  Demonstrates: the SDK's VCL hook (Application.OnException) catches the
  exception, logs it as Fatal, and attaches the breadcrumbs. No user code
  is needed for the logging part. The app keeps running because the VCL
  shows its default "EAccessViolation" dialog instead of terminating. }
procedure TMainForm.btnSimulateCrashClick(Sender: TObject);
var
  P: PInteger;
begin
  EW.AddBreadcrumb(btClick, 'ui', 'Clicked "Simulate Crash"');
  EW.AddBreadcrumb(btSystem, 'core', 'About to touch a nil pointer');

  Log('[!] about to raise an UNHANDLED access violation...');
  Log('    SDK will auto-log it as FATAL with breadcrumbs attached.');

  P := nil;
  P^ := 42;  // access violation - caught by ExeWatchSDKv1.VCL hook
end;

{ Button 4 - Info log.
  Demonstrates: breadcrumbs are NOT attached to Info/Warning/Debug logs.
  The breadcrumb added here stays in the queue for the next Error/Fatal. }
procedure TMainForm.btnLogInfoClick(Sender: TObject);
begin
  EW.AddBreadcrumb(btClick, 'ui', 'Clicked "Log Info"');
  EW.Info('Baseline info log - not an error', 'ui');
  Log('[i] EW.Info sent. Breadcrumbs are NOT attached (only Error/Fatal).');
  Log('    The breadcrumb above stays buffered for the next Error/Fatal.');
end;

procedure TMainForm.FakeSaveToDatabase;
begin
  // Simulates a failing DB operation.
  raise Exception.Create('Simulated database failure (demo)');
end;

procedure TMainForm.FakeNotifyBackend;
begin
  // Never reached in the demo - present to show a realistic flow.
end;

procedure TMainForm.Log(const AMessage: string);
begin
  Memo1.Lines.Add(AMessage);
end;

end.
