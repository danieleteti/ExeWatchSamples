program EWDelphiFMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  MainFormU in 'MainFormU.pas' {MainForm},
  ExeWatchSDKv1 in '..\DelphiCommons\ExeWatchSDKv1.pas',
  ExeWatchSDKv1.FMX in '..\DelphiCommons\ExeWatchSDKv1.FMX.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
