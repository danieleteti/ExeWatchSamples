unit Controllers.OrdersU;

{
  A small API whose only job is to show what per-request instrumentation looks
  like when the tenant changes on every call. The action code never asks which
  tenant it is serving: EW already is that tenant's logger.
}

interface

uses
  System.Generics.Collections,
  MVCFramework,
  MVCFramework.Commons,
  ExeWatchTenantU;

type
  TOrder = class
  private
    FId: Integer;
    FCustomerRef: string;
    FTotal: Currency;
  public
    property Id: Integer read FId write FId;
    property CustomerRef: string read FCustomerRef write FCustomerRef;
    property Total: Currency read FTotal write FTotal;
    constructor Create(AId: Integer; const ACustomerRef: string; ATotal: Currency);
  end;

  [MVCPath('/orders')]
  TOrdersController = class(TTenantController)
  public
    [MVCPath]
    [MVCHTTPMethod([httpGET])]
    function GetAll: TObjectList<TOrder>;

    [MVCPath('/($Id)')]
    [MVCHTTPMethod([httpGET])]
    function GetById(const Id: Integer): TOrder;

    [MVCDoc('Always fails, to show the error landing under the right customer')]
    [MVCPath('/broken')]
    [MVCHTTPMethod([httpGET])]
    function Broken: IMVCResponse;
  end;

implementation

uses
  System.SysUtils,
  ExeWatchSDKv1;

{ TOrder }

constructor TOrder.Create(AId: Integer; const ACustomerRef: string; ATotal: Currency);
begin
  inherited Create;
  FId := AId;
  FCustomerRef := ACustomerRef;
  FTotal := ATotal;
end;

{ TOrdersController }

function TOrdersController.GetAll: TObjectList<TOrder>;
var
  TimingId: string;
begin
  EW.AddBreadcrumb('Listing orders', 'orders');

  // The thread is shared with every other tenant. A timing left open would be
  // inherited by whatever this thread serves next, so it is closed in a
  // finally, not on the happy path.
  TimingId := 'orders.list';
  EW.StartTiming(TimingId, 'orders');
  try
    Result := TObjectList<TOrder>.Create(True);   // the framework frees it
    Result.Add(TOrder.Create(1, TenantId + '-0001', 120.50));
    Result.Add(TOrder.Create(2, TenantId + '-0002', 89.90));
  finally
    EW.EndTiming(TimingId);
  end;

  EW.Info(Format('Listed %d orders', [Result.Count]), 'orders');
end;

function TOrdersController.GetById(const Id: Integer): TOrder;
begin
  EW.AddBreadcrumb(Format('Fetching order %d', [Id]), 'orders');

  if Id <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Order id must be positive');

  Result := TOrder.Create(Id, Format('%s-%.4d', [TenantId, Id]), 42.00);
  EW.Info(Format('Fetched order %d', [Id]), 'orders');
end;

function TOrdersController.Broken: IMVCResponse;
begin
  EW.AddBreadcrumb('About to touch the price list', 'orders');
  // Unhandled on purpose: the engine's exception handler attributes it to the
  // tenant of this request, with the breadcrumbs of this request attached.
  raise Exception.Create('Order 4711 references an unknown price list');
end;

end.
