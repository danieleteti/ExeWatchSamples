{ ============================================================================
  OrdersFormU - Order Management Module Form

  This form is compiled into the ModuleOrders.bpl runtime package
  and loaded on demand by the host application via LoadPackage.

  It demonstrates ExeWatch timing/profiling, breadcrumbs, metrics and
  gauges from within a dynamically loaded package.
  ============================================================================ }

unit OrdersFormU;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  ExeWatchSDKv1;

type
  TOrdersForm = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    pnlClient: TPanel;
    lstOrders: TListBox;
    pnlButtons: TPanel;
    btnCreateOrder: TButton;
    btnProcessOrder: TButton;
    btnCancelOrder: TButton;
    btnSimulateSlowQuery: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnCreateOrderClick(Sender: TObject);
    procedure btnProcessOrderClick(Sender: TObject);
    procedure btnCancelOrderClick(Sender: TObject);
    procedure btnSimulateSlowQueryClick(Sender: TObject);
  private
    FOrderCounter: Integer;
  end;

implementation

{$R *.dfm}

uses
  ModuleRegistryU;

procedure TOrdersForm.FormCreate(Sender: TObject);
begin
  FOrderCounter := 1000;
  if ExeWatchIsInitialized then
  begin
    EW.Info('Orders module form opened', 'orders');
    EW.AddBreadcrumb(btForm, 'navigation', 'Opened Orders form');
  end;
  lstOrders.Items.Add('ORD-0997 - ACME Corp - Pending');
  lstOrders.Items.Add('ORD-0998 - Globex - Shipped');
  lstOrders.Items.Add('ORD-0999 - Initech - Delivered');
end;

procedure TOrdersForm.FormDestroy(Sender: TObject);
begin
  if ExeWatchIsInitialized then
    EW.Info('Orders module form closed', 'orders');
end;

procedure TOrdersForm.btnCreateOrderClick(Sender: TObject);
var
  OrderId: string;
begin
  Inc(FOrderCounter);
  OrderId := 'ORD-' + IntToStr(FOrderCounter);

  if ExeWatchIsInitialized then
    EW.StartTiming('order.create.' + OrderId, 'orders');

  Sleep(50 + Random(100));
  lstOrders.Items.Add(OrderId + ' - New Customer - Pending');

  if ExeWatchIsInitialized then
  begin
    EW.EndTiming('order.create.' + OrderId);
    EW.Info('Order created: ' + OrderId, 'orders');
    EW.AddBreadcrumb(btTransaction, 'orders', 'Created order: ' + OrderId);
    EW.IncrementCounter('orders.created', 1.0, 'orders');
  end;
end;

procedure TOrdersForm.btnProcessOrderClick(Sender: TObject);
var
  Idx: Integer;
  OrderLine: string;
begin
  Idx := lstOrders.ItemIndex;
  if Idx < 0 then
  begin
    ShowMessage('Select an order first');
    Exit;
  end;

  OrderLine := lstOrders.Items[Idx];

  if ExeWatchIsInitialized then
  begin
    EW.StartTiming('order.process', 'orders');
    EW.AddBreadcrumb(btTransaction, 'orders', 'Processing: ' + OrderLine);
  end;

  Sleep(100 + Random(200));

  if Pos('Pending', OrderLine) > 0 then
  begin
    lstOrders.Items[Idx] := StringReplace(OrderLine, 'Pending', 'Shipped', []);
    if ExeWatchIsInitialized then
    begin
      EW.EndTiming('order.process');
      EW.Info('Order processed: ' + OrderLine, 'orders');
      EW.IncrementCounter('orders.processed', 1.0, 'orders');
    end;
  end
  else
  begin
    if ExeWatchIsInitialized then
    begin
      EW.EndTiming('order.process');
      EW.Warning('Order not in Pending status: ' + OrderLine, 'orders');
    end;
    ShowMessage('Order is not in Pending status');
  end;
end;

procedure TOrdersForm.btnCancelOrderClick(Sender: TObject);
var
  Idx: Integer;
  OrderLine: string;
begin
  Idx := lstOrders.ItemIndex;
  if Idx < 0 then
  begin
    ShowMessage('Select an order first');
    Exit;
  end;

  OrderLine := lstOrders.Items[Idx];
  lstOrders.Items.Delete(Idx);

  if ExeWatchIsInitialized then
  begin
    EW.Warning('Order cancelled: ' + OrderLine, 'orders');
    EW.AddBreadcrumb(btTransaction, 'orders', 'Cancelled: ' + OrderLine);
    EW.IncrementCounter('orders.cancelled', 1.0, 'orders');
  end;
end;

procedure TOrdersForm.btnSimulateSlowQueryClick(Sender: TObject);
var
  DelayMs: Integer;
begin
  if ExeWatchIsInitialized then
  begin
    EW.StartTiming('order.slow_query', 'orders');
    EW.AddBreadcrumb(btQuery, 'orders', 'Starting slow database query simulation');
  end;

  DelayMs := 500 + Random(1500);
  Sleep(DelayMs);

  if ExeWatchIsInitialized then
  begin
    EW.EndTiming('order.slow_query');
    if DelayMs > 1000 then
      EW.Warning('Slow query detected: ' + IntToStr(DelayMs) + 'ms', 'orders')
    else
      EW.Debug('Query completed: ' + IntToStr(DelayMs) + 'ms', 'orders');
    EW.RecordGauge('orders.query_time_ms', DelayMs, 'orders');
  end;

  ShowMessage('Query completed in ' + IntToStr(DelayMs) + 'ms');
end;

initialization
  RegisterModule('Orders', 'Order management module', TOrdersForm);

end.
