// ***************************************************************************
//
// ExeWatch Webhook Receiver Sample
//
// A DMVCFramework controller that receives and processes ExeWatch
// alert webhook notifications.
//
// For more info: https://exewatch.com/docs#webhooks
//
// ***************************************************************************

unit ControllerU;

interface

uses
  MVCFramework, MVCFramework.Commons, JsonDataObjects;

type
  [MVCPath('/api')]
  TExeWatchWebHookController = class(TMVCController)
  public
    [MVCPath('/webhook')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Receives ExeWatch alert webhook notifications')]
    function HandleWebHook([MVCFromBody] Payload: TJSONObject): IMVCResponse;

    [MVCPath('/trace-demo')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Emits a nested timing trace (profiler-style waterfall) to ExeWatch')]
    function TraceDemo: IMVCResponse;
  end;

const
  /// Set this to the token shown in ExeWatch > Alerts > Integrations > Webhook
  EXEWATCH_WEBHOOK_TOKEN = 'whsec_your_token_here';

implementation

uses
  System.SysUtils, MVCFramework.Logger, ExeWatchSDKv1;

function TExeWatchWebHookController.HandleWebHook(Payload: TJSONObject): IMVCResponse;
var
  Token: string;
  Event, AlertType, AlertName, AppName, Condition, Msg, AppId: string;
begin
  // 1. Verify the token
  Token := Context.Request.Headers['X-ExeWatch-Token'];
  if Token <> EXEWATCH_WEBHOOK_TOKEN then
  begin
    LogW('ExeWatch webhook rejected: invalid token');
    Result := UnauthorizedResponse('Invalid token');
    Exit;
  end;

  // 2. Extract fields from payload
  Event     := Payload.S['event'];      // "alert.fired" or "test"
  AlertType := Payload.S['alert_type']; // "log_level", "timing", "health_critical", "health_degraded", "health_recovery"
  AlertName := Payload.S['alert_name'];
  AppName   := Payload.S['app_name'];
  Condition := Payload.S['condition'];
  Msg       := Payload.S['message'];
  AppId     := Payload.S['app_id'];

  // 3. Log the alert
  LogI('ExeWatch [%s] %s - %s: %s', [AlertType, AppName, AlertName, Msg]);

  // 4. Handle different alert types
  if AlertType = 'log_level' then
  begin
    // Error/Fatal log threshold exceeded
    // Example: send a Telegram message, create a Jira ticket, page on-call, etc.
    LogW('LOG ALERT: %s - %s (%s)', [AlertName, Msg, Condition]);
  end
  else if AlertType = 'timing' then
  begin
    // Slow operations detected
    LogW('TIMING ALERT: %s - %s (%s)', [AlertName, Msg, Condition]);
  end
  else if AlertType = 'health_critical' then
  begin
    // App health is critical (red)
    LogE('HEALTH CRITICAL: %s - %s', [AppName, Msg]);
  end
  else if AlertType = 'health_degraded' then
  begin
    // App health is degraded (yellow)
    LogW('HEALTH DEGRADED: %s - %s', [AppName, Msg]);
  end
  else if AlertType = 'health_recovery' then
  begin
    // App health recovered (green)
    LogI('HEALTH RECOVERED: %s - %s', [AppName, Msg]);
  end;

  // 5. Save to file for debugging (optional - remove in production)
  Payload.SaveToFile('last_webhook.json', False);

  // 6. Return 200 to acknowledge receipt
  Result := OKResponse('Webhook received');
end;

// ---------------------------------------------------------------------------
//  GET /api/trace-demo  ->  Nested Timing Trace demo
// ---------------------------------------------------------------------------
//
//  Produces a profiler-style "waterfall" of one request's work in ExeWatch.
//  EW.StartTrace opens a named ROOT trace and returns a 16-hex trace id; every
//  EW.StartTiming / EW.EndTiming run before EW.EndTrace auto-nests under it via
//  the SDK's per-thread LIFO stack. A DMVCFramework action runs entirely on the
//  request thread, so the whole tree is captured in order: ValidateRequest,
//  then QueryDatabase (with OpenConnection + RunQuery as children), then
//  SerializeJson. EndTrace must run on every path (success and error), hence the
//  try/except that re-raises after closing the trace. This is purely additive:
//  the existing /api/webhook endpoint is unchanged.
//
function TExeWatchWebHookController.TraceDemo: IMVCResponse;
var
  LTraceId: string;
  LTotalMs: Double;
begin
  EW.AddBreadcrumb('Trace demo request', 'trace');

  LTraceId := EW.StartTrace('HandleTraceDemo');
  try
    EW.StartTiming('ValidateRequest', 'http');
    Sleep(5);
    EW.EndTiming('ValidateRequest', nil, True);

    EW.StartTiming('QueryDatabase', 'db');
    EW.StartTiming('OpenConnection', 'db');
    Sleep(10);
    EW.EndTiming('OpenConnection', nil, True);
    EW.StartTiming('RunQuery', 'db');
    Sleep(20);
    EW.EndTiming('RunQuery', nil, True);
    EW.EndTiming('QueryDatabase', nil, True);

    EW.StartTiming('SerializeJson', 'cpu');
    Sleep(8);
    EW.EndTiming('SerializeJson', nil, True);

    LTotalMs := EW.EndTrace;
  except
    on E: Exception do
    begin
      EW.EndTrace;
      raise;
    end;
  end;

  EW.Info(Format('Trace "HandleTraceDemo" completed (id %s) in ~%.0f ms',
    [LTraceId, LTotalMs]), 'trace');

  Result := OKResponse(Format(
    'Nested trace recorded. id=%s total~%.0fms. ' +
    'Spans: ValidateRequest -> QueryDatabase (OpenConnection, RunQuery) -> SerializeJson. ' +
    'Open the Timing / Traces page in ExeWatch to see the waterfall.',
    [LTraceId, LTotalMs]));
end;

end.
