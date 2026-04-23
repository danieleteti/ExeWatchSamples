program EWDelphiDLL;

uses
  Vcl.Forms,
  ExeWatchSDKv1Imports in '..\DLLSDKCommons\ExeWatchSDKv1Imports.pas',
  MainFormU in 'MainFormU.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
