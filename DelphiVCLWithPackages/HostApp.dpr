{ ============================================================================
  HostApp - ExeWatch Runtime Packages Demo

  This application demonstrates that ExeWatch works seamlessly with
  Delphi runtime packages loaded via LoadPackage.

  Architecture:
    ExeWatchSDKPkg.bpl  - ExeWatch SDK as a shared runtime package
    ModuleCustomers.bpl - Customer module (loaded on demand)
    ModuleOrders.bpl    - Orders module (loaded on demand)
    HostApp.exe         - This host application

  IMPORTANT: This project must be compiled with "Build with runtime
  packages" enabled. See README.md for detailed build instructions.

  Build order:
    1. ExeWatchSDKPkg.dpk
    2. ModuleCustomers.dpk  (requires ExeWatchSDKPkg)
    3. ModuleOrders.dpk     (requires ExeWatchSDKPkg)
    4. HostApp.dpr           (requires ExeWatchSDKPkg)
  ============================================================================ }

program HostApp;

uses
  Vcl.Forms,
  MainFormU in 'MainFormU.pas' {MainForm};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
