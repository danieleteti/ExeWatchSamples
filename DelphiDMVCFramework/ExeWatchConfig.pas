unit ExeWatchConfig;

// ExeWatch (exewatch.com) setup of this application. Replace the API key in
// StartExeWatch with the key of your ExeWatch application for Windows (its
// keys start with ew_win_).

interface

// Starts ExeWatch. Call StartExeWatch once, at application startup. If you
// already know the customer, pass it: StartExeWatch('ACME').
procedure StartExeWatch(const ACustomerId: string = '');

// The customer who runs the application (the holder of a license, for
// example). Call it as soon as you know it: before or after StartExeWatch,
// either order works. Call it again if the customer changes.
procedure SetExeWatchCustomer(const ACustomerId: string);

// Ships the events still queued (waits up to 5 seconds). Call it once when
// the application ends.
procedure FlushExeWatch;

implementation

uses
  ExeWatchSDKv1;

var
  GCustomerId: string;

procedure SetExeWatchCustomer(const ACustomerId: string);
begin
  GCustomerId := ACustomerId;
  if ExeWatchIsInitialized then
    EW.SetCustomerId(ACustomerId);
end;

procedure StartExeWatch(const ACustomerId: string);
var
  Cfg: TExeWatchConfig;
begin
  if ACustomerId <> '' then
    GCustomerId := ACustomerId;
  Cfg := TExeWatchConfig.Create('YOUR_EXEWATCH_APIKEY', GCustomerId);
  Cfg.AppVersion := '1.0.0';  // your release tag (optional)
  // Cfg.AnonymizeDeviceId := True;  // hash the user name in the device id (GDPR)
  // Cfg.SampleRate := 1.0;  // 1.0 = every event; errors are always sent
  InitializeExeWatch(Cfg);
end;

procedure FlushExeWatch;
begin
  if ExeWatchIsInitialized then
    EW.WaitForSending(5);
end;

end.
