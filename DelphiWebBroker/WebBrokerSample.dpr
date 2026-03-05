program WebBrokerSample;
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.SyncObjs,
  IPPeerServer,
  IPPeerAPI,
  IdHTTPWebBrokerBridge,
  IdGlobal,
  Web.WebReq,
  Web.WebBroker,
  WebModuleU in 'WebModuleU.pas' {WebModule1: TWebModule},
  ServerConstU in 'ServerConstU.pas',
  ExeWatchSDKv1 in '..\DelphiCommons\ExeWatchSDKv1.pas';

{$R *.res}

const
  // Replace with your actual API key from the ExeWatch dashboard
  EXEWATCH_API_KEY = 'YOUR_EXEWATCH_APIKEY';

var
  GServer: TIdHTTPWebBrokerBridge;
  GShutdownEvent: TEvent;

function BindPort(APort: Integer): Boolean;
var
  LTestServer: IIPTestServer;
begin
  Result := True;
  try
    LTestServer := PeerFactory.CreatePeer('', IIPTestServer) as IIPTestServer;
    LTestServer.TestOpenPort(APort, nil);
  except
    Result := False;
  end;
end;

function CheckPort(APort: Integer): Integer;
begin
  if BindPort(APort) then
    Result := APort
  else
    Result := 0;
end;

procedure StartServer(AServer: TIdHTTPWebBrokerBridge; APort: Integer);
begin
  if not AServer.Active then
  begin
    if CheckPort(APort) > 0 then
    begin
      AServer.DefaultPort := APort;
      AServer.Bindings.Clear;
      AServer.Active := True;
      WriteLn(Format(sStartingServer, [APort]));
      WriteLn('Server started successfully on port ', APort);
      WriteLn('Press Ctrl+C to stop the server');
    end
    else
      WriteLn(Format(sPortInUse, [APort.ToString]));
  end
  else
    WriteLn(sServerRunning);
end;

procedure StopServer(AServer: TIdHTTPWebBrokerBridge);
begin
  if AServer.Active then
  begin
    WriteLn(sStoppingServer);
    AServer.Active := False;
    AServer.Bindings.Clear;
    WriteLn(sServerStopped);
  end;
end;

procedure CtrlCHandler(Sender: TObject);
begin
  WriteLn('');
  WriteLn('Shutdown signal received...');
  GShutdownEvent.SetEvent;
end;

var
  Port: Integer;
begin
  Port := 8080;
  GShutdownEvent := TEvent.Create(nil, True, False, '');
  
  try
    // Check for port parameter
    if ParamCount >= 2 then
    begin
      if SameText(ParamStr(1), '-p') or SameText(ParamStr(1), '--port') then
        TryStrToInt(ParamStr(2), Port);
    end;

    WriteLn('===========================================');
    WriteLn('ExeWatch WebBroker Sample Server');
    WriteLn('===========================================');
    WriteLn('');

    // Initialize ExeWatch SDK
    if EXEWATCH_API_KEY = 'YOUR_EXEWATCH_APIKEY' then
    begin
      WriteLn('');
      WriteLn('ERROR: API key not configured!');
      WriteLn('Open WebBrokerSample.dpr and replace "YOUR_EXEWATCH_APIKEY"');
      WriteLn('with your actual API key from: https://exewatch.com');
      WriteLn('');
      WriteLn('Press Enter to exit.');
      ReadLn;
      Exit;
    end;

    WriteLn('Initializing ExeWatch SDK...');
    InitializeExeWatch(TExeWatchConfig.Create(
      EXEWATCH_API_KEY,
      'demo_customer'
    ));

    EW.SetTag('app', 'WebBrokerSample');
    EW.SetTag('platform', 'Delphi');
    EW.IncrementCounter('http.requests', 0);
    EW.IncrementCounter('http.errors', 0);

    EW.Info('Server started', 'startup');
    WriteLn('ExeWatch SDK initialized');
    WriteLn('');

    try
      if WebRequestHandler <> nil then
        WebRequestHandler.WebModuleClass := WebModuleClass;

      GServer := TIdHTTPWebBrokerBridge.Create(nil);
      try
        StartServer(GServer, Port);

        if GServer.Active then
        begin
          // Keep running until shutdown event (Ctrl+C)
          GShutdownEvent.WaitFor(INFINITE);
          StopServer(GServer);
        end;

      finally
        EW.Info('Server stopped', 'shutdown');
        EW.Flush;
        GServer.Free;
      end;

    except
      on E: Exception do
      begin
        WriteLn(E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;

    WriteLn('Server shutdown complete.');
  finally
    GShutdownEvent.Free;
  end;
end.
