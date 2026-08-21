unit ExeWatchTenantU;

{
  How the tenant reaches the code, on a stateless server.

  The tenant is a property of the request, not of the thread and not of the
  process. A middleware resolves it once and puts it in the request context,
  which dies with the request; a controller base class reads it back. Nothing
  is stored per thread on purpose: the threads here come from a pool, and
  anything parked on one is still there when it serves the next request.
}

interface

uses
  System.SysUtils,
  MVCFramework,
  ExeWatchSDKv1,
  TenantLoggersU;

const
  // Where the resolved tenant lives for the duration of the request.
  // TWebContext.Data is a TMVCStringDictionary: strings only, per request.
  CTX_TENANT_ID = 'exewatch.tenant_id';

  // Real deployments read the tenant from a JWT claim or the subdomain. A
  // header keeps the sample runnable with curl; everything downstream is the
  // same either way.
  TENANT_HEADER = 'X-Tenant-Id';

type
  TExeWatchTenantMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private
    FLoggers: TTenantLoggers;
  public
    constructor Create(ALoggers: TTenantLoggers);
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

  /// <summary>
  ///   Base class for controllers that log. EW is the logger of the tenant this
  ///   request belongs to, and it holds no state between requests.
  /// </summary>
  TTenantController = class(TMVCController)
  protected
    function EW: TExeWatch;
    function TenantId: string;
  end;

/// <summary>Reads the tenant a request was resolved to. Empty before routing.</summary>
function TenantOf(AContext: TWebContext): string;

var
  // One registry for the process, built at startup with the tenants this copy
  // of the server serves.
  GLoggers: TTenantLoggers = nil;

implementation

uses
  MVCFramework.Commons;

function TenantOf(AContext: TWebContext): string;
begin
  Result := AContext.Data[CTX_TENANT_ID];
end;

{ TExeWatchTenantMiddleware }

constructor TExeWatchTenantMiddleware.Create(ALoggers: TTenantLoggers);
begin
  inherited Create;
  FLoggers := ALoggers;
end;

procedure TExeWatchTenantMiddleware.OnBeforeRouting(AContext: TWebContext;
  var AHandled: Boolean);
var
  TenantId: string;
begin
  TenantId := AContext.Request.Headers[TENANT_HEADER];

  // An unknown tenant is refused before anything allocates for it. Without this
  // check, whoever can set the header decides how many shipper threads this
  // process runs.
  if not FLoggers.IsKnownTenant(TenantId) then
  begin
    AContext.Response.StatusCode := HTTP_STATUS.BadRequest;
    AContext.Response.ContentType := TMVCMediaType.TEXT_PLAIN;
    AContext.Response.Content := Format('Unknown or missing %s header', [TENANT_HEADER]);
    AHandled := True;
    Exit;
  end;

  AContext.Data[CTX_TENANT_ID] := TenantId;

  // This thread came from the pool. Whatever the previous request left on it
  // does not belong to this one: breadcrumbs are kept per thread and are only
  // cleared when an error consumes them, so a request that ended without an
  // error leaves its trail behind.
  FLoggers.ForTenant(TenantId).ClearBreadcrumbs;
end;

procedure TExeWatchTenantMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string;
  var AHandled: Boolean);
begin
  // Nothing to do: the tenant was resolved before routing.
end;

procedure TExeWatchTenantMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string;
  const AHandled: Boolean);
var
  TenantId: string;
begin
  TenantId := TenantOf(AContext);
  if TenantId <> '' then
    FLoggers.ForTenant(TenantId).IncrementCounter('http.requests', 1, 'http');
end;

procedure TExeWatchTenantMiddleware.OnAfterRouting(AContext: TWebContext;
  const AHandled: Boolean);
begin
  // Nothing to do.
end;

{ TTenantController }

function TTenantController.TenantId: string;
begin
  Result := TenantOf(Context);
end;

function TTenantController.EW: TExeWatch;
begin
  Result := GLoggers.ForTenant(TenantId);
end;

end.
