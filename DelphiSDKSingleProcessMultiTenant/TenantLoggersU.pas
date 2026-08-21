unit TenantLoggersU;

{
  One TExeWatch instance per tenant, all inside a single server process.

  Why one instance per tenant, and not one instance with SetCustomerId called
  per request: the ingest payload carries customer_id and device once per
  batch, not once per event. A single instance therefore cannot attribute
  different events to different tenants, and switching the customer id while
  requests are in flight re-tags whatever is still sitting in the buffer.

  Why every instance needs its own StoragePath: by default the SDK derives the
  queue directory from the API key alone. Every tenant here shares one key, so
  the default would put all of them in the same folder, where their shipper
  threads compete for the same queue files and each newly created instance runs
  its startup crash-recovery pass over files its siblings are still sending.

  Why the tenant list is fixed at construction: each instance costs a shipper
  thread, a queue directory and a device record. A registry that created one on
  demand would let whoever can set a tenant header decide how many threads this
  process runs. The tenants a server process serves are known at startup, from
  its configuration or its database connections; anything else is a bad request.
  That bound is also the honest limit of this design: it fits a process serving
  a handful to a few dozen tenants, not thousands. See the README.
}

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  ExeWatchSDKv1;

type
  EUnknownTenant = class(Exception);

  TTenantLoggers = class
  private
    FLoggers: TObjectDictionary<string, TExeWatch>;
    FKnownTenants: TDictionary<string, Boolean>;
    FLock: TCriticalSection;
    FApiKey: string;
    FInstanceName: string;
    FQueueRoot: string;
    FAppVersion: string;
    function CreateLoggerFor(const ATenantId: string): TExeWatch;
  public
    /// <param name="AInstanceName">
    ///   Identifies this running copy of the server. Several copies on one host
    ///   must not share a queue root, so this name becomes the first path
    ///   segment, and it also becomes the DeviceId every tenant reports.
    /// </param>
    /// <param name="AAppVersion">
    ///   Release tag of this deployment. A server binary rarely carries a
    ///   meaningful VERSIONINFO, and "which release is failing" is the first
    ///   question an incident asks, so it is set explicitly.
    /// </param>
    /// <param name="ATenantIds">
    ///   The tenants this process serves. Nothing outside this list gets a
    ///   logger.
    /// </param>
    constructor Create(const AApiKey, AInstanceName, AQueueRoot, AAppVersion: string;
      const ATenantIds: TArray<string>);
    destructor Destroy; override;

    function IsKnownTenant(const ATenantId: string): Boolean;

    /// <summary>
    ///   The logger that belongs to ATenantId, created on first use. Safe to
    ///   call from any request thread. Raises EUnknownTenant for a tenant this
    ///   process does not serve.
    /// </summary>
    function ForTenant(const ATenantId: string): TExeWatch;

    /// <summary>
    ///   Drains every tenant queue before the server stops. Freeing the loggers
    ///   already shuts them down, but that makes a single send attempt; this
    ///   waits instead. ATimeoutSec is the budget for the whole shutdown, not
    ///   per tenant: a service manager kills a process that takes too long to
    ///   stop, and per-tenant timeouts multiply by the number of tenants.
    ///   Tenants past the budget still get their buffer written to disk, they
    ///   just are not waited for. Returns the number of events still queued.
    /// </summary>
    function FlushAll(ATimeoutSec: Integer): Integer;
  end;

implementation

uses
  System.IOUtils,
  System.Diagnostics;

function SafeFolderName(const AValue: string): string;
var
  I: Integer;
begin
  // Belt and braces: the tenant id is checked against the known list before it
  // ever reaches here, but it still ends up as a path segment.
  Result := AValue;
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      Result[I] := '_';
end;

{ TTenantLoggers }

constructor TTenantLoggers.Create(const AApiKey, AInstanceName, AQueueRoot, AAppVersion: string;
  const ATenantIds: TArray<string>);
var
  TenantId: string;
begin
  inherited Create;
  FApiKey := AApiKey;
  FInstanceName := AInstanceName;
  FQueueRoot := AQueueRoot;
  FAppVersion := AAppVersion;
  FLock := TCriticalSection.Create;
  FLoggers := TObjectDictionary<string, TExeWatch>.Create([doOwnsValues]);
  FKnownTenants := TDictionary<string, Boolean>.Create;
  for TenantId in ATenantIds do
  begin
    if TenantId = '' then
      raise EUnknownTenant.Create('TTenantLoggers: empty tenant id in the tenant list');
    FKnownTenants.AddOrSetValue(TenantId, True);
  end;
end;

destructor TTenantLoggers.Destroy;
begin
  // TExeWatch.Destroy calls Shutdown, which stops each shipper thread.
  FLoggers.Free;
  FKnownTenants.Free;
  FLock.Free;
  inherited;
end;

function TTenantLoggers.IsKnownTenant(const ATenantId: string): Boolean;
begin
  Result := FKnownTenants.ContainsKey(ATenantId);
end;

function TTenantLoggers.CreateLoggerFor(const ATenantId: string): TExeWatch;
var
  Cfg: TExeWatchConfig;
begin
  Cfg := TExeWatchConfig.Create(FApiKey, ATenantId);

  // AppBinaryVersion is read from the executable's VERSIONINFO; AppVersion is
  // the tag you choose, and it is the one the dashboard shows per customer.
  Cfg.AppVersion := FAppVersion;

  // One queue folder per instance, per tenant. Both coordinates are needed: the
  // instance name keeps the copies of this server apart, the tenant folder
  // keeps the loggers inside this process apart.
  Cfg.StoragePath := TPath.Combine(TPath.Combine(FQueueRoot, FInstanceName),
    SafeFolderName(ATenantId));

  // The default DeviceId is username@hostname, so every copy of a server
  // running under the same account would report as one device. The useful unit
  // is the process, not the tenant: all tenants inside this process share a
  // DeviceId and are told apart by their customer id.
  Cfg.DeviceInfo.DeviceId := FInstanceName + '@' + TExeWatchHelper.GetHostname;

  // Lets you filter the dashboard down to one running copy.
  SetLength(Cfg.GlobalTags, 1);
  Cfg.GlobalTags[0] := TPair<string, string>.Create('instance', FInstanceName);

  Result := TExeWatch.Create(Cfg);
end;

function TTenantLoggers.ForTenant(const ATenantId: string): TExeWatch;
begin
  if not FKnownTenants.ContainsKey(ATenantId) then
    raise EUnknownTenant.CreateFmt('Unknown tenant "%s"', [ATenantId]);

  FLock.Enter;
  try
    if not FLoggers.TryGetValue(ATenantId, Result) then
    begin
      Result := CreateLoggerFor(ATenantId);
      FLoggers.Add(ATenantId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TTenantLoggers.FlushAll(ATimeoutSec: Integer): Integer;
var
  Logger: TExeWatch;
  SW: TStopwatch;
  Remaining: Integer;
begin
  Result := 0;
  SW := TStopwatch.StartNew;
  FLock.Enter;
  try
    for Logger in FLoggers.Values do
    begin
      // One deadline for all of them. WaitForSending(0) still writes the
      // buffer out to disk before returning, so a tenant that gets no time
      // left loses nothing: its queue is retried on the next start.
      Remaining := ATimeoutSec - Trunc(SW.Elapsed.TotalSeconds);
      if Remaining < 0 then
        Remaining := 0;
      Inc(Result, Logger.WaitForSending(Remaining));
    end;
  finally
    FLock.Leave;
  end;
end;

end.
