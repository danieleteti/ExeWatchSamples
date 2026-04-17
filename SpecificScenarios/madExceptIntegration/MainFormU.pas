{ *******************************************************************************
  ExeWatch — madExcept integration sample

  Shows how to forward exceptions intercepted by madExcept to ExeWatch,
  using madExcept's own call stack (accurate, resolved via the JDBG/MAP
  debug info embedded at build time) instead of the SDK's internal capture.

  Why this matters:

    madExcept installs low-level hooks (before Delphi's VCL handler) and
    resolves every frame with line numbers and unit names. The SDK's own
    StackWalk-based capture produces raw addresses unless you ship debug
    symbols alongside the exe, which most Delphi shops don't do in prod.

    By sending madExcept's resolved stack to ExeWatch you get the best of
    both worlds:
      - madExcept keeps doing what it does best (local dialog, bug report,
        optional email to the dev team, offline crash dump);
      - ExeWatch gets a symbolicated, searchable stack trace in the cloud
        dashboard, with full breadcrumb and session context.

  How it works:

    1. RegisterExceptionHandler(...) installs our callback inside madExcept.
    2. The callback builds a stack-trace string from IMEException.CallStack.
    3. It calls EW.ErrorWithException(E, StackTrace, ...) — the SDK stores
       the supplied stack verbatim and skips its own auto-capture.
    4. We leave Handled alone so madExcept's normal flow still runs.

  Prerequisite: madExcept must be installed in the IDE. This sample also
  enables the "madExcept linked" option via the 'madExcept' unit, which
  auto-installs the runtime hooks when the unit is used.

  Full docs: https://exewatch.com/ui/docs
******************************************************************************* }

unit MainFormU;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls;

type
  TMainForm = class(TForm)
    btnRaiseException: TButton;
    btnRaiseAV: TButton;
    btnLogInfo: TButton;
    Memo1: TMemo;
    lblInfo: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure btnRaiseExceptionClick(Sender: TObject);
    procedure btnRaiseAVClick(Sender: TObject);
    procedure btnLogInfoClick(Sender: TObject);
  private
    procedure Log(const AMessage: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  ExeWatchSDKv1,
  ExeWatchSDKv1.VCL,
  ExeWatchMadExceptBridgeU;

const
  // Replace with your actual API key from the ExeWatch dashboard
  EXEWATCH_API_KEY = 'ew_win_U9DDSZs1GPRgq_Mkyz_5R4EIzlpQ-RdDdr0ooeHXbrY';
  CUSTOMER_ID      = 'madExceptSample';

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

  // Initialize ExeWatch. The madExcept bridge registered its callback in the
  // initialization section of ExeWatchMadExceptBridgeU, so every exception
  // madExcept catches from now on will be forwarded here with a resolved stack.
  InitializeExeWatch(EXEWATCH_API_KEY, CUSTOMER_ID);

  Log('ExeWatch + madExcept bridge installed (SDK ' + EXEWATCH_SDK_VERSION + ')');
  Log('');
  Log('Click the buttons to generate exceptions:');
  Log('  - "Raise Exception"    — a regular EAssertionFailed raised from code');
  Log('  - "Raise Access Viol." — a hardware access violation (nil deref)');
  Log('  - "Log Info"           — plain info log, to verify baseline shipping');
  Log('');
  Log('After clicking, check the ExeWatch dashboard: the log should include');
  Log('a stack_trace field with madExcept-resolved unit names + line numbers.');
end;

procedure TMainForm.btnRaiseExceptionClick(Sender: TObject);
begin
  raise Exception.Create('Demo exception raised by the user (button click)');
end;

procedure TMainForm.btnRaiseAVClick(Sender: TObject);
var
  P: PInteger;
begin
  P := nil;
  P^ := 42;  // Access violation — caught by madExcept, not by standard try/except
end;

procedure TMainForm.btnLogInfoClick(Sender: TObject);
begin
  EW.Info('Button "Log Info" clicked — baseline log (no exception)', 'ui');
  Log('Info log sent. Check the ExeWatch dashboard.');
end;

procedure TMainForm.Log(const AMessage: string);
begin
  Memo1.Lines.Add(AMessage);
end;

end.
