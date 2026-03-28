{ ============================================================================
  MainFormU - Host Application Main Form

  This is the main form of the host application. It initializes ExeWatch
  and provides UI to dynamically load/unload module packages via
  LoadPackage/UnloadPackage.

  Key points for runtime package integration with ExeWatch:
  1. ExeWatch SDK is in its own package (ExeWatchSDKPkg.bpl) so the
     global EW instance is shared across all loaded modules
  2. Each module package registers its form via ModuleRegistryU
  3. After LoadPackage, the host queries the registry to discover forms
  4. All modules share the same ExeWatch session, API key, tags, etc.
  ============================================================================ }

unit MainFormU;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  ExeWatchSDKv1, ExeWatchSDKv1.VCL;

const
  { -----------------------------------------------------------------------
    CONFIGURATION: Set your ExeWatch API Key and Customer ID here.
    Get your API Key from https://exewatch.com after creating an app.
    ----------------------------------------------------------------------- }
  APP_API_KEY    = 'ew_win_YOUR_API_KEY_HERE';
  APP_CUSTOMER_ID = 'DEMO-CUSTOMER-001';

type
  TMainForm = class(TForm)
    pnlTop: TPanel;
    pnlConnection: TPanel;
    lblStep1: TLabel;
    lblApiKey: TLabel;
    lblApiKeyValue: TLabel;
    lblCustomerId: TLabel;
    lblCustomerIdValue: TLabel;
    btnToggleConnect: TButton;
    lblStatus: TLabel;
    pnlCenter: TPanel;
    grpModules: TGroupBox;
    lblStep2: TLabel;
    btnLoadCustomers: TButton;
    btnLoadOrders: TButton;
    lblLoadHint: TLabel;
    lblModulesLoaded: TLabel;
    lstModules: TListBox;
    btnShowForm: TButton;
    btnUnloadAll: TButton;
    pnlBottom: TPanel;
    lblLogOutput: TLabel;
    memoLog: TMemo;
    btnClearLog: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnToggleConnectClick(Sender: TObject);
    procedure btnLoadCustomersClick(Sender: TObject);
    procedure btnLoadOrdersClick(Sender: TObject);
    procedure btnShowFormClick(Sender: TObject);
    procedure btnUnloadAllClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
    procedure lstModulesDblClick(Sender: TObject);
  private
    FLoadedPackages: TStringList;
    procedure UILog(const AMessage: string);
    procedure LoadModule(const ABplName: string);
    procedure RefreshModuleList;
    procedure UpdateUI;
    procedure HandleError(const AErrorMessage: string);
    procedure HandleLogsSent(AAcceptedCount, ARejectedCount: Integer);
    procedure HandleDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

uses
  ModuleRegistryU;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FLoadedPackages := TStringList.Create;
  lblApiKeyValue.Caption := APP_API_KEY;
  lblCustomerIdValue.Caption := APP_CUSTOMER_ID;
  UpdateUI;
  UILog('ExeWatch Runtime Packages Demo started');
  UILog('SDK Version: ' + EXEWATCH_SDK_VERSION);
  UILog('');
  UILog('API Key and Customer ID are configured as constants in MainFormU.pas');
  UILog('Click Connect, then load module packages and open their forms.');
  UILog('All modules share the same ExeWatch session!');
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FinalizeExeWatch;
  FLoadedPackages.Free;
end;

procedure TMainForm.UILog(const AMessage: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if AMessage = '' then
        memoLog.Lines.Add('')
      else
        memoLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AMessage);
      SendMessage(memoLog.Handle, EM_SCROLLCARET, 0, 0);
    end);
end;

procedure TMainForm.UpdateUI;
var
  Connected: Boolean;
begin
  Connected := ExeWatchIsInitialized;

  if Connected then
  begin
    btnToggleConnect.Caption := 'Disconnect';
    lblStatus.Caption := 'Connected';
    lblStatus.Font.Color := clGreen;
  end
  else
  begin
    btnToggleConnect.Caption := 'Connect';
    lblStatus.Caption := 'Disconnected';
    lblStatus.Font.Color := clGray;
  end;

  btnLoadCustomers.Enabled := Connected and (FLoadedPackages.IndexOf('ModuleCustomers.bpl') < 0);
  btnLoadOrders.Enabled := Connected and (FLoadedPackages.IndexOf('ModuleOrders.bpl') < 0);
  btnUnloadAll.Enabled := FLoadedPackages.Count > 0;
  btnShowForm.Enabled := lstModules.Items.Count > 0;
end;

procedure TMainForm.HandleError(const AErrorMessage: string);
begin
  UILog('[EW ERROR] ' + AErrorMessage);
end;

procedure TMainForm.HandleLogsSent(AAcceptedCount, ARejectedCount: Integer);
begin
  UILog('[EW] ' + IntToStr(AAcceptedCount) + ' log(s) sent to server');
end;

procedure TMainForm.HandleDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
begin
  if ASuccess then
    UILog('[EW] Device info sent successfully')
  else
    UILog('[EW ERROR] Device info failed: ' + AErrorMessage);
end;

{ ---- Connection ---- }

procedure TMainForm.btnToggleConnectClick(Sender: TObject);
var
  Config: TExeWatchConfig;
begin
  if ExeWatchIsInitialized then
  begin
    { Disconnect }
    EW.Info('Host application disconnecting', 'host');
    FinalizeExeWatch;
    UILog('[OK] Disconnected from ExeWatch');
    UpdateUI;
    Exit;
  end;

  { Connect using constants defined at the top of this unit }
  Config := TExeWatchConfig.Create(APP_API_KEY, APP_CUSTOMER_ID);
  Config.AppVersion := '1.0.0-packages-demo';
  Config.SampleRate := 1.0;
  InitializeExeWatch(Config);

  EW.OnError := HandleError;
  EW.OnLogsSent := HandleLogsSent;
  EW.OnDeviceInfoSent := HandleDeviceInfoSent;

  EW.SetUser('demo_user', 'demo@example.com', 'Demo User');
  EW.SetTag('environment', 'demo');
  EW.SetTag('app_type', 'runtime_packages');
  EW.SendDeviceInfo;
  EW.Info('Host application started with runtime packages support', 'host');

  UILog('[OK] Connected to ExeWatch');
  UILog('     Endpoint: ' + EXEWATCH_ENDPOINT);
  UILog('     Customer: ' + APP_CUSTOMER_ID);
  UILog('');
  UpdateUI;
end;

{ ---- Module Loading ---- }

procedure TMainForm.LoadModule(const ABplName: string);
var
  Handle: HMODULE;
begin
  if FLoadedPackages.IndexOf(ABplName) >= 0 then
  begin
    UILog('[SKIP] ' + ABplName + ' already loaded');
    Exit;
  end;

  try
    if ExeWatchIsInitialized then
      EW.StartTiming('package.load.' + ABplName, 'host');

    Handle := LoadPackage(ABplName);

    if ExeWatchIsInitialized then
    begin
      EW.EndTiming('package.load.' + ABplName);
      EW.Info('Package loaded: ' + ABplName, 'host');
      EW.AddBreadcrumb(btSystem, 'packages', 'Loaded: ' + ABplName);
    end;

    FLoadedPackages.AddObject(ABplName, TObject(Handle));
    UILog('[OK] Loaded ' + ABplName);
    RefreshModuleList;
    UpdateUI;
  except
    on E: Exception do
    begin
      if ExeWatchIsInitialized then
      begin
        EW.CancelTiming('package.load.' + ABplName);
        EW.ErrorWithException(E, 'host', 'Failed to load package: ' + ABplName);
      end;
      UILog('[ERROR] Failed to load ' + ABplName + ': ' + E.Message);
      ShowMessage(
        'Cannot load ' + ABplName + ':' + sLineBreak +
        E.Message + sLineBreak + sLineBreak +
        'Make sure the BPL is in the same folder as the EXE ' +
        'or in a folder listed in the system PATH.' + sLineBreak + sLineBreak +
        'Build order: ExeWatchSDKPkg > ModuleCustomers/ModuleOrders > HostApp');
    end;
  end;
end;

procedure TMainForm.RefreshModuleList;
var
  Modules: TArray<TModuleInfo>;
  I: Integer;
begin
  lstModules.Items.Clear;
  Modules := GetRegisteredModules;
  for I := 0 to Length(Modules) - 1 do
    lstModules.Items.Add(Modules[I].ModuleName + ' - ' + Modules[I].Description);
  lblModulesLoaded.Caption := 'Registered modules: ' + IntToStr(Length(Modules));
end;

procedure TMainForm.btnLoadCustomersClick(Sender: TObject);
begin
  LoadModule('ModuleCustomers.bpl');
end;

procedure TMainForm.btnLoadOrdersClick(Sender: TObject);
begin
  LoadModule('ModuleOrders.bpl');
end;

procedure TMainForm.btnShowFormClick(Sender: TObject);
var
  Modules: TArray<TModuleInfo>;
  Idx: Integer;
  Form: TForm;
begin
  Idx := lstModules.ItemIndex;
  if Idx < 0 then
  begin
    ShowMessage('Select a module from the list');
    Exit;
  end;

  Modules := GetRegisteredModules;
  if Idx >= Length(Modules) then
    Exit;

  if ExeWatchIsInitialized then
    EW.AddBreadcrumb(btNavigation, 'host', 'Opening module: ' + Modules[Idx].ModuleName);

  UILog('Opening ' + Modules[Idx].ModuleName + ' form...');
  Form := Modules[Idx].FormClass.Create(Application);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
  UILog(Modules[Idx].ModuleName + ' form closed');
end;

procedure TMainForm.lstModulesDblClick(Sender: TObject);
begin
  btnShowFormClick(Sender);
end;

procedure TMainForm.btnUnloadAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := FLoadedPackages.Count - 1 downto 0 do
  begin
    try
      UnloadPackage(HMODULE(FLoadedPackages.Objects[I]));
      UILog('[OK] Unloaded ' + FLoadedPackages[I]);
      if ExeWatchIsInitialized then
        EW.Info('Package unloaded: ' + FLoadedPackages[I], 'host');
    except
      on E: Exception do
      begin
        UILog('[ERROR] Failed to unload ' + FLoadedPackages[I] + ': ' + E.Message);
        if ExeWatchIsInitialized then
          EW.ErrorWithException(E, 'host', 'Failed to unload: ' + FLoadedPackages[I]);
      end;
    end;
  end;
  FLoadedPackages.Clear;
  ClearModuleRegistry;
  RefreshModuleList;
  UpdateUI;
end;

procedure TMainForm.btnClearLogClick(Sender: TObject);
begin
  memoLog.Lines.Clear;
end;

end.
