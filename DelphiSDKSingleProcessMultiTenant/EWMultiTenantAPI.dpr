program EWMultiTenantAPI;

{
  ExeWatch on a stateless multi-tenant server (DelphiMVCFramework).

  One process, one API key, several tenants, a pool of request threads that
  serve any tenant. Every request is attributed to the customer it belongs to,
  and no thread ever owns a tenant.

  Run more than one copy on the same host by passing a different instance name,
  so each keeps its own queues:

      EWMultiTenantAPI.exe inst01 8080
      EWMultiTenantAPI.exe inst02 8081

  Then:

      curl -H "X-Tenant-Id: ACME-Corp"     http://localhost:8080/orders
      curl -H "X-Tenant-Id: Northwind-Ltd" http://localhost:8080/orders/7
      curl -H "X-Tenant-Id: Globex-SA"     http://localhost:8080/orders/broken
      curl -H "X-Tenant-Id: nope"          http://localhost:8080/orders   -> 400
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.DotEnv,
  MVCFramework.Server.Intf,
  MVCFramework.Server.Factory,
  MVCFramework.Signal,
  TenantLoggersU in 'TenantLoggersU.pas',
  ExeWatchTenantU in 'ExeWatchTenantU.pas',
  Controllers.OrdersU in 'Controllers.OrdersU.pas',
  ExeWatchSDKv1 in '..\DelphiCommons\ExeWatchSDKv1.pas';

{$R *.res}

const
  // The key lives in bin\.env, never in the source. All tenants share it: the
  // key identifies the application, not the running copy or the tenant.
  //
  // DMVCFramework's dotEnv already reads that folder (it resolves to the
  // executable's directory), and bin\ is in .gitignore, so a real key put
  // there cannot reach a commit. There is deliberately no constant to edit:
  // a key typed into a source file is a key that eventually gets committed.
  API_KEY_SETTING = 'exewatch.api.key';
  APP_VERSION_SETTING = 'exewatch.app.version';

function ApiKey: string;
begin
  Result := dotEnv.Env(API_KEY_SETTING, '');
end;

function AppVersion: string;
begin
  // Set this from whatever your deploy already knows: a tag, a build number,
  // a commit. It is what tells you which release an error came from.
  Result := dotEnv.Env(APP_VERSION_SETTING, 'dev');
end;

function QueueRoot: string;
var
  Base: string;
begin
  // Servers often run as LocalSystem or under a shared service account, where
  // the SDK default (%LOCALAPPDATA%) is the same directory for every copy. Put
  // the queues somewhere the service account owns instead.
  Base := GetEnvironmentVariable('ProgramData');
  if Base = '' then
    Base := TPath.GetTempPath;
  Result := TPath.Combine(TPath.Combine(Base, 'ExeWatchSamples'), 'MultiTenantAPI');
end;

procedure ConfigureEngine(AEngine: TMVCEngine);
begin
  AEngine.AddController(TOrdersController);

  // Resolves the tenant before routing and refuses anything unknown.
  AEngine.AddMiddleware(TExeWatchTenantMiddleware.Create(GLoggers));

  // Unhandled errors are attributed to the tenant of the request that raised
  // them, read back from the request context.
  AEngine.SetExceptionHandler(
    procedure(E: Exception; SelectedController: TMVCController;
      WebContext: TWebContext; var ExceptionHandled: Boolean)
    var
      TenantId: string;
    begin
      TenantId := TenantOf(WebContext);
      if TenantId <> '' then
      begin
        GLoggers.ForTenant(TenantId).IncrementCounter('http.errors', 1, 'http');
        GLoggers.ForTenant(TenantId).ErrorWithException(E, 'unhandled');
      end;
      // Leave ExceptionHandled False: the framework still renders its own
      // error response.
    end);
end;

var
  Engine: TMVCEngine;
  Server: IMVCServer;
  InstanceName: string;
  Port: Integer;
  Pending: Integer;

begin
  IsMultiThread := True;

  InstanceName := ParamStr(1);
  if InstanceName = '' then
    InstanceName := 'inst01';
  Port := StrToIntDef(ParamStr(2), 8080);

  // The tenants this copy of the server serves. In a real deployment they come
  // from configuration or from the database connections the process opens, not
  // from the request.
  if ApiKey = '' then
  begin
    WriteLn('No API key.');
    WriteLn;
    WriteLn('Put your key from https://exewatch.com in a file named .env next to');
    WriteLn('this executable, as a single line:');
    WriteLn;
    WriteLn('    ', API_KEY_SETTING, '=ew_win_your_key_here');
    WriteLn;
    WriteLn('That folder is gitignored, so the key stays out of the repository.');
    Halt(1);
  end;

  GLoggers := TTenantLoggers.Create(ApiKey, InstanceName, QueueRoot, AppVersion,
    TArray<string>.Create('ACME-Corp', 'Northwind-Ltd', 'Globex-SA'));
  try
    WriteLn(Format('instance %s, version %s, on port %d, 3 tenants',
      [InstanceName, AppVersion, Port]));
    WriteLn('queues under ', TPath.Combine(QueueRoot, InstanceName));
    WriteLn('send X-Tenant-Id with every request. Ctrl+C to stop.');
    WriteLn;

    Engine := TMVCEngine.Create(
      procedure(Config: TMVCConfig)
      begin
        Config[TMVCConfigKey.DefaultContentType] := TMVCMediaType.APPLICATION_JSON;
        Config[TMVCConfigKey.AllowUnhandledAction] := 'false';
        Config[TMVCConfigKey.ExposeServerSignature] := 'false';
      end);
    try
      ConfigureEngine(Engine);

      Server := TMVCServerFactory.CreateIndyDirect(Engine);
      Server.RunAndWait(Port);   // blocks until Ctrl+C, then stops the server
    finally
      Server := nil;             // release the server before the engine it wraps
      Engine.Free;
    end;

    WriteLn;
    WriteLn('draining tenant queues...');
    Pending := GLoggers.FlushAll(20);
    if Pending = 0 then
      WriteLn('all events shipped')
    else
      WriteLn(Format('%d events still queued, they will be retried on next start', [Pending]));
  finally
    GLoggers.Free;
  end;
end.
