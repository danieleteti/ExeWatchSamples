program EWBreadcrumbsUsage;

uses
  Vcl.Forms,
  ExeWatchSDKv1,
  ExeWatchSDKv1.VCL,
  MainFormU in 'MainFormU.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
