program EWDelphiVCL;

uses
  Vcl.Forms,
  MainFormU in 'MainFormU.pas' {MainForm},
  ExeWatchSDKv1 in '..\DelphiCommons\ExeWatchSDKv1.pas',
  ExeWatchSDKv1.VCL in '..\DelphiCommons\ExeWatchSDKv1.VCL.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
