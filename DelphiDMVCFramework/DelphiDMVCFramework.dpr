// ***************************************************************************
//
// ExeWatch - DMVCFramework Integration Sample
//
// Demonstrates how to integrate ExeWatch APM with a DMVCFramework web
// application using TemplatePro templates and HTMX for the UI.
//
// ***************************************************************************

program DelphiDMVCFramework;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Web.ReqMulti,
  Web.WebReq,
  Web.WebBroker,
  LoggerPro,
  MVCFramework,
  MVCFramework.Logger,
  MVCFramework.DotEnv,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  IdContext,
  IdHTTPWebBrokerBridge,
  MVCFramework.Container,
  MVCFramework.Signal,
  ControllerU in 'ControllerU.pas',
  EntitiesU in 'EntitiesU.pas',
  ServicesU in 'ServicesU.pas',
  WebModuleU in 'WebModuleU.pas' {MyWebModule: TWebModule},
  ExeWatchConfig in 'ExeWatchConfig.pas',
  ExeWatchSDKv1;

{$R *.res}

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.OnParseAuthentication := TMVCParseAuthentication.OnParseAuthentication;
    LServer.DefaultPort := APort;
    LServer.KeepAlive := True;
    LServer.MaxConnections := 1024;
    LServer.ListenQueue := 500;
    LServer.Active := True;

    LogI('Listening on http://localhost:' + APort.ToString);
    LogI('Press Ctrl+C to shut down.');

    WaitForTerminationSignal;
    EnterInShutdownState;

    // Flush pending logs before shutdown
    EW.Flush;

    LServer.Active := False;
  finally
    LServer.Free;
  end;
end;

begin
  IsMultiThread := True;
  MVCSerializeNulls := True;
  MVCNameCaseDefault := TMVCNameCase.ncLowerCase;
  UseConsoleLogger := True;
  UseLoggerVerbosityLevel := TLogLevel.levNormal;

  WriteLn('==========================================');
  WriteLn(' ExeWatch + DMVCFramework Sample');
  WriteLn('==========================================');
  WriteLn('');

  // -------------------------------------------------------------------------
  //  ExeWatch integration with DMVCFramework logging
  //
  //  By routing DMVCFramework's LoggerPro output through ExeWatch, every
  //  LogI/LogW/LogE call — including the framework's own internal logs —
  //  appears automatically in the ExeWatch dashboard.
  // -------------------------------------------------------------------------
  SetDefaultLogger(
    CreateLogBuilderWithDefaultConfiguration
      .WriteToCallback
      .WithCallback(
        procedure(const ALogItem: TLogItem; const AFormattedMessage: string)
        begin
          if ExeWatchIsInitialized and (ALogItem.LogType > TLogType.Debug) then
          begin
            // Skip noisy framework-internal messages
            if ALogItem.LogMessage.Contains('{ROUTE NOT FOUND}', True) then
              Exit;
            if (ALogItem.LogType = TLogType.Info)
               and ALogItem.LogMessage.Contains('TMVCStaticFilesMiddleware', True) then
              Exit;

            // Forward to ExeWatch preserving level, tag, timestamp, and thread ID
            EW.Log(
              TEWLogLevel(Ord(ALogItem.LogType)),
              ALogItem.LogMessage,
              ALogItem.LogTag,
              ALogItem.TimeStamp,
              ALogItem.ThreadID);
          end;
        end).Done.Build);

  // --- Initialize ExeWatch SDK ---
  WriteLn('Initializing ExeWatch SDK...');
  StartExeWatch('dmvc_sample_customer');

  // Set global tags for all log entries
  EW.SetTag('framework', 'dmvcframework');
  EW.SetTag('app', 'DMVCSample');

  // Initialize counters
  EW.IncrementCounter('http.requests', 0);
  EW.IncrementCounter('http.errors', 0);

  // Register a periodic gauge that reports memory usage every 30 seconds
  EW.RegisterPeriodicGauge('memory_mb',
    function: Double
    var
      LMemMgr: TMemoryManagerState;
    begin
      {$WARN SYMBOL_PLATFORM OFF}
      GetMemoryManagerState(LMemMgr);
      {$WARN SYMBOL_PLATFORM ON}
      Result := LMemMgr.TotalAllocatedMediumBlockSize / (1024 * 1024);
    end
  );

  WriteLn('ExeWatch SDK initialized.');
  WriteLn('');

  LogI('** DMVCFramework Server ** build ' + DMVCFRAMEWORK_VERSION);

  try
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;

    WebRequestHandlerProc.MaxConnections := 1024;

    // Enable the built-in DMVCFramework profiler.
    // Since the logger is routed to ExeWatch, action timings appear
    // automatically on the ExeWatch dashboard — no manual instrumentation.
    Profiler.ProfileLogger := Log;
    Profiler.WarningThreshold := 500; // warn if action takes > 500ms
    Profiler.LogsOnlyIfOverThreshold := False;

    RegisterServices(DefaultMVCServiceContainer);
    DefaultMVCServiceContainer.Build;

    RunServer(dotEnv.Env('dmvc.server.port', 8080));
  except
    on E: Exception do
    begin
      EW.ErrorWithException(E, 'startup');
      LogF(E.ClassName + ': ' + E.Message);
    end;
  end;
  FlushExeWatch();
end.
