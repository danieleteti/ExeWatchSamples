program EWMadExceptIntegration;

uses
  madExcept,                      // Link madExcept into the executable
  Vcl.Forms,
  ExeWatchSDKv1,
  ExeWatchSDKv1.VCL,
  ExeWatchMadExceptBridgeU in 'ExeWatchMadExceptBridgeU.pas',
  MainFormU in 'MainFormU.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
