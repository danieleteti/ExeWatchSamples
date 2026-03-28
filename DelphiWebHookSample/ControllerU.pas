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
  end;

const
  /// Set this to the token shown in ExeWatch > Alerts > Integrations > Webhook
  EXEWATCH_WEBHOOK_TOKEN = 'whsec_your_token_here';

implementation

uses
  System.SysUtils, MVCFramework.Logger;

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

end.
