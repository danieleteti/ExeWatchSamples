{ ============================================================================
  CustomersFormU - Customer Management Module Form

  This form is compiled into the ModuleCustomers.bpl runtime package
  and loaded on demand by the host application via LoadPackage.

  It demonstrates that ExeWatch logging, breadcrumbs, timing and metrics
  work seamlessly from within a dynamically loaded package.
  ============================================================================ }

unit CustomersFormU;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  ExeWatchSDKv1;

type
  TCustomersForm = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    pnlClient: TPanel;
    lstCustomers: TListBox;
    pnlButtons: TPanel;
    btnAddCustomer: TButton;
    btnRemoveCustomer: TButton;
    btnSearchCustomer: TButton;
    btnSimulateError: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnAddCustomerClick(Sender: TObject);
    procedure btnRemoveCustomerClick(Sender: TObject);
    procedure btnSearchCustomerClick(Sender: TObject);
    procedure btnSimulateErrorClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

uses
  ModuleRegistryU;

procedure TCustomersForm.FormCreate(Sender: TObject);
begin
  if ExeWatchIsInitialized then
  begin
    EW.Info('Customers module form opened', 'customers');
    EW.AddBreadcrumb(btForm, 'navigation', 'Opened Customers form');
  end;
  lstCustomers.Items.Add('ACME Corporation');
  lstCustomers.Items.Add('Globex Industries');
  lstCustomers.Items.Add('Initech LLC');
  lstCustomers.Items.Add('Umbrella Corp');
end;

procedure TCustomersForm.FormDestroy(Sender: TObject);
begin
  if ExeWatchIsInitialized then
    EW.Info('Customers module form closed', 'customers');
end;

procedure TCustomersForm.btnAddCustomerClick(Sender: TObject);
var
  CustomerName: string;
begin
  CustomerName := InputBox('Add Customer', 'Customer name:', '');
  if CustomerName <> '' then
  begin
    lstCustomers.Items.Add(CustomerName);
    if ExeWatchIsInitialized then
    begin
      EW.Info('Customer added: ' + CustomerName, 'customers');
      EW.AddBreadcrumb(btClick, 'customers', 'Added customer: ' + CustomerName);
      EW.IncrementCounter('customers.added', 1.0, 'customers');
    end;
  end;
end;

procedure TCustomersForm.btnRemoveCustomerClick(Sender: TObject);
var
  Idx: Integer;
  CustomerName: string;
begin
  Idx := lstCustomers.ItemIndex;
  if Idx < 0 then
  begin
    ShowMessage('Select a customer first');
    Exit;
  end;

  CustomerName := lstCustomers.Items[Idx];
  lstCustomers.Items.Delete(Idx);
  if ExeWatchIsInitialized then
  begin
    EW.Warning('Customer removed: ' + CustomerName, 'customers');
    EW.AddBreadcrumb(btClick, 'customers', 'Removed customer: ' + CustomerName);
    EW.IncrementCounter('customers.removed', 1.0, 'customers');
  end;
end;

procedure TCustomersForm.btnSearchCustomerClick(Sender: TObject);
var
  SearchTerm: string;
  I: Integer;
  Found: Boolean;
begin
  SearchTerm := InputBox('Search Customer', 'Search term:', '');
  if SearchTerm = '' then
    Exit;

  if ExeWatchIsInitialized then
    EW.StartTiming('customer.search', 'customers');

  Found := False;
  for I := 0 to lstCustomers.Items.Count - 1 do
  begin
    if Pos(UpperCase(SearchTerm), UpperCase(lstCustomers.Items[I])) > 0 then
    begin
      lstCustomers.ItemIndex := I;
      Found := True;
      Break;
    end;
  end;

  if ExeWatchIsInitialized then
  begin
    EW.EndTiming('customer.search');
    if Found then
      EW.Debug('Customer search hit: "' + SearchTerm + '"', 'customers')
    else
      EW.Debug('Customer search miss: "' + SearchTerm + '"', 'customers');
  end;

  if not Found then
    ShowMessage('Customer not found: ' + SearchTerm);
end;

procedure TCustomersForm.btnSimulateErrorClick(Sender: TObject);
var
  List: TStringList;
begin
  if ExeWatchIsInitialized then
    EW.AddBreadcrumb(btClick, 'customers', 'Clicked Simulate Error');
  List := nil;
  try
    List.Add('test');  // Access Violation
  except
    on E: Exception do
    begin
      if ExeWatchIsInitialized then
        EW.ErrorWithException(E, 'customers', 'Simulated error in Customers module');
      ShowMessage('Error captured by ExeWatch: ' + E.Message);
    end;
  end;
end;

initialization
  RegisterModule('Customers', 'Customer management module', TCustomersForm);

end.
