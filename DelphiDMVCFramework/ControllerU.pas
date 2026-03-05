// ***************************************************************************
//
// ExeWatch - DMVCFramework Integration Sample
//
// Controller: demonstrates ExeWatch instrumentation on every action.
//
//   - OnBeforeAction: breadcrumb + start timing for every request
//   - OnAfterAction: end timing for every request
//   - CRUD actions: explicit Info/Warning/Error logs
//   - Reports: nested timings, heavy operations, partial failures
//   - Services: simulated external calls with timeouts and errors
//   - Simulate: trigger errors, slow ops, and warnings on demand
//
// ***************************************************************************

unit ControllerU;

interface

uses
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.HTMX,
  EntitiesU,
  ServicesU,
  System.Generics.Collections;

type
  [MVCPath('/web')]
  TWebController = class(TMVCController)
  public
    // --- Pages ---

    [MVCPath]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function Index: String;

    [MVCPath('/people')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function PeopleList([MVCInject] PeopleService: IPeopleService): String;

    [MVCPath('/people')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    function CreatePerson(
      [MVCFromContentField('firstname', '')] const FirstName: String;
      [MVCFromContentField('lastname', '')]  const LastName: String;
      [MVCInject] PeopleService: IPeopleService
    ): String;

    [MVCPath('/people/($ID)')]
    [MVCHTTPMethod([httpDELETE])]
    function DeletePerson(ID: Integer;
      [MVCInject] PeopleService: IPeopleService): String;

    [MVCPath('/people/search')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function SearchPeople(
      [MVCFromQueryString('q', '')] const Query: String;
      [MVCInject] PeopleService: IPeopleService
    ): String;

    [MVCPath('/people/import')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function ImportPeople([MVCInject] PeopleService: IPeopleService): String;

    // --- Reports (heavy operations with nested timings) ---

    [MVCPath('/reports')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function ReportsPage: String;

    [MVCPath('/reports/sales')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function GenerateSalesReport: String;

    [MVCPath('/reports/inventory')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function GenerateInventoryReport: String;

    [MVCPath('/reports/audit')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function GenerateAuditReport: String;

    // --- External Services (simulated calls that can fail) ---

    [MVCPath('/services')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function ServicesPage: String;

    [MVCPath('/services/payment')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function CallPaymentGateway: String;

    [MVCPath('/services/email')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function CallEmailService: String;

    [MVCPath('/services/geocoding')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function CallGeocodingAPI: String;

    [MVCPath('/services/all')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function CallAllServices: String;

    // --- Simulate actions (for ExeWatch demo) ---

    [MVCPath('/simulate/error')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function SimulateError: String;

    [MVCPath('/simulate/slow')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function SimulateSlow: String;

    [MVCPath('/simulate/warning')]
    [MVCHTTPMethod([httpPOST])]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    function SimulateWarning: String;

    // --- JSON API ---

    [MVCPath('/api/health')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.APPLICATION_JSON)]
    function HealthCheck: String;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.DateUtils,
  System.JSON,
  System.SyncObjs,
  System.Math,
  MVCFramework.Logger,
  ExeWatchSDKv1;

var
  GRequestCount: Int64 = 0;
  GErrorCount: Int64 = 0;


{ TWebController }


// ---------------------------------------------------------------------------
//  Pages
// ---------------------------------------------------------------------------

function TWebController.Index: String;
begin
  ViewData['page_title'] := 'Dashboard';
  ViewData['request_count'] := IntToStr(GRequestCount);
  ViewData['error_count'] := IntToStr(GErrorCount);
  ViewData['dmvc_version'] := DMVCFRAMEWORK_VERSION;
  ViewData['compiler_version'] := Format('Delphi %.1f', [CompilerVersion]);
  ViewData['current_time'] := FormatDateTime('hh:nn:ss', Now);
  if Context.Request.IsHTMX then
    Result := RenderView('partials/dashboard_content')
  else
    Result := RenderView('index');
end;


// ---------------------------------------------------------------------------
//  People CRUD
// ---------------------------------------------------------------------------

function TWebController.PeopleList(PeopleService: IPeopleService): String;
var
  LPeople: TObjectList<TPerson>;
begin
  LPeople := PeopleService.GetAll;
  try
    ViewData['people'] := LPeople;
    ViewData['people_count'] := IntToStr(LPeople.Count);
    ViewData['page_title'] := 'People';

    EW.Info(Format('Listed %d people', [LPeople.Count]), 'people');

    if Context.Request.IsHTMX then
      Result := RenderView('partials/people_content')
    else
      Result := RenderView('people');
  finally
    LPeople.Free;
  end;
end;

function TWebController.CreatePerson(const FirstName, LastName: String;
  PeopleService: IPeopleService): String;
var
  LPeople: TObjectList<TPerson>;
begin
  if FirstName.IsEmpty or LastName.IsEmpty then
  begin
    EW.Warning('Create person failed: empty name fields', 'people');
    Context.Response.StatusCode := 400;
    Result := '<div class="alert alert-warning">First name and last name are required.</div>';
    Exit;
  end;

  PeopleService.Add(FirstName, LastName);
  EW.Info(Format('Created person: %s %s', [FirstName, LastName]), 'people');

  LPeople := PeopleService.GetAll;
  try
    ViewData['people'] := LPeople;
    ViewData['people_count'] := IntToStr(LPeople.Count);
    Result := RenderView('partials/people_table');
  finally
    LPeople.Free;
  end;
end;

function TWebController.DeletePerson(ID: Integer;
  PeopleService: IPeopleService): String;
var
  LPeople: TObjectList<TPerson>;
begin
  PeopleService.Delete(ID);
  EW.Info(Format('Deleted person ID %d', [ID]), 'people');

  LPeople := PeopleService.GetAll;
  try
    ViewData['people'] := LPeople;
    ViewData['people_count'] := IntToStr(LPeople.Count);
    Result := RenderView('partials/people_table');
  finally
    LPeople.Free;
  end;
end;

function TWebController.SearchPeople(const Query: String;
  PeopleService: IPeopleService): String;
var
  LPeople: TObjectList<TPerson>;
begin
  EW.AddBreadcrumb('Search: "' + Query + '"', 'people');

  // Time the search operation separately from the HTTP request
  EW.StartTiming('people.search', 'database');
  LPeople := PeopleService.Search(Query);
  EW.EndTiming('people.search', nil, True);

  try
    ViewData['people'] := LPeople;
    ViewData['people_count'] := IntToStr(LPeople.Count);

    EW.Info(Format('Search "%s" returned %d results', [Query, LPeople.Count]), 'people');

    Result := RenderView('partials/people_table');
  finally
    LPeople.Free;
  end;
end;

function TWebController.ImportPeople(PeopleService: IPeopleService): String;
var
  LImported, LFailed, I: Integer;
  LFirstName, LLastName, LReason: string;
  LPeople: TObjectList<TPerson>;
  LNames: TArray<string>;
  LExtra: TJSONObject;
  LFailedRows: TJSONArray;
  LRowExtra: TJSONObject;
  LReasons: TArray<string>;
begin
  // Simulate a batch import that can partially fail
  EW.AddBreadcrumb('Starting batch import (10 records)', 'people');
  EW.StartTiming('people.batch_import', 'database');

  LImported := 0;
  LFailed := 0;
  LFailedRows := TJSONArray.Create;
  LNames := TArray<string>.Create(
    'Alice,Johnson', 'Bob,Williams', 'Carol,Brown', 'David,Jones',
    'Eva,Garcia', 'Frank,Martinez', 'Grace,Anderson', 'Hank,Taylor',
    'Iris,Thomas', 'Jack,Hernandez'
  );
  LReasons := TArray<string>.Create(
    'duplicate key constraint',
    'validation error: name too short',
    'database timeout',
    'foreign key violation'
  );

  for I := 0 to Length(LNames) - 1 do
  begin
    LFirstName := LNames[I].Split([','])[0];
    LLastName := LNames[I].Split([','])[1];

    // Simulate ~20% chance of failure per record
    if Random(100) < 20 then
    begin
      Inc(LFailed);
      LReason := LReasons[Random(Length(LReasons))];

      // Log each failed row with structured extra_data
      LRowExtra := TJSONObject.Create;
      LRowExtra.AddPair('row_number', TJSONNumber.Create(I + 1));
      LRowExtra.AddPair('first_name', LFirstName);
      LRowExtra.AddPair('last_name', LLastName);
      LRowExtra.AddPair('error', LReason);
      LRowExtra.AddPair('operation', 'batch_import');
      EW.Log(llWarning, Format('Import failed for row %d: %s %s (%s)',
        [I + 1, LFirstName, LLastName, LReason]), 'people', LRowExtra);

      // Collect for summary
      LFailedRows.Add(TJSONObject.Create
        .AddPair('row', TJSONNumber.Create(I + 1))
        .AddPair('name', LFirstName + ' ' + LLastName)
        .AddPair('error', LReason));
    end
    else
    begin
      PeopleService.Add(LFirstName, LLastName);
      Inc(LImported);
    end;
    Sleep(50 + Random(100)); // Simulate per-row processing time
  end;

  EW.EndTiming('people.batch_import', nil, LFailed = 0);

  // Summary log with extra_data containing all failed rows
  LExtra := TJSONObject.Create;
  LExtra.AddPair('total_rows', TJSONNumber.Create(Length(LNames)));
  LExtra.AddPair('imported', TJSONNumber.Create(LImported));
  LExtra.AddPair('failed', TJSONNumber.Create(LFailed));
  LExtra.AddPair('failed_rows', LFailedRows);
  LExtra.AddPair('operation', 'batch_import');

  if LFailed > 0 then
    EW.Log(llWarning, Format('Batch import completed with errors: %d imported, %d failed',
      [LImported, LFailed]), 'people', LExtra)
  else
    EW.Log(llInfo, Format('Batch import completed: %d imported', [LImported]),
      'people', LExtra);

  // Return updated list
  LPeople := PeopleService.GetAll;
  try
    ViewData['people'] := LPeople;
    ViewData['people_count'] := IntToStr(LPeople.Count);
    ViewData['import_result'] := Format(
      '<div class="alert %s">' +
      '<strong>Import complete:</strong> %d imported, %d failed' +
      '</div>',
      [IfThen(LFailed > 0, 'alert-warning', 'alert-success'), LImported, LFailed]);

    Result := RenderView('partials/people_import_result');
  finally
    LPeople.Free;
  end;
end;


// ---------------------------------------------------------------------------
//  Reports (heavy operations with nested timings)
// ---------------------------------------------------------------------------

function TWebController.ReportsPage: String;
begin
  ViewData['page_title'] := 'Reports';

  if Context.Request.IsHTMX then
    Result := RenderView('partials/reports_content')
  else
    Result := RenderView('reports');
end;

function TWebController.GenerateSalesReport: String;
var
  LTotalMs: Integer;
begin
  EW.AddBreadcrumb('Generating sales report', 'reports');

  // Top-level timing for the whole report
  EW.StartTiming('report.sales', 'reports');

  // Step 1: Query orders from database
  EW.StartTiming('report.sales.query_orders', 'database');
  Sleep(300 + Random(500));  // 300-800 ms
  EW.EndTiming('report.sales.query_orders', nil, True);
  EW.Info('Queried 12,847 orders from database', 'reports');

  // Step 2: Aggregate revenue by region
  EW.StartTiming('report.sales.aggregate', 'compute');
  Sleep(200 + Random(400));  // 200-600 ms
  EW.EndTiming('report.sales.aggregate', nil, True);

  // Step 3: Generate charts (heaviest step)
  EW.StartTiming('report.sales.render_charts', 'compute');
  Sleep(500 + Random(1000)); // 500-1500 ms
  EW.EndTiming('report.sales.render_charts', nil, True);

  // Step 4: Export to PDF
  EW.StartTiming('report.sales.export_pdf', 'io');
  Sleep(200 + Random(300));  // 200-500 ms
  EW.EndTiming('report.sales.export_pdf', nil, True);

  LTotalMs := 1200 + Random(2200);
  EW.EndTiming('report.sales', nil, True);

  EW.Info(Format('Sales report generated in ~%d ms (4 steps)', [LTotalMs]), 'reports');

  Result := Format(
    '<div class="alert alert-success">' +
    '<strong>Sales Report generated</strong><br>' +
    '4 steps completed: query_orders, aggregate, render_charts, export_pdf<br>' +
    '<small class="text-muted">Each step was timed separately. ' +
    'Check the Timing page to see nested timings and identify bottlenecks.</small></div>',
    []);
end;

function TWebController.GenerateInventoryReport: String;
var
  LFailed: Boolean;
begin
  EW.AddBreadcrumb('Generating inventory report', 'reports');
  EW.StartTiming('report.inventory', 'reports');

  // Step 1: Connect to warehouse API
  EW.StartTiming('report.inventory.warehouse_api', 'external');
  Sleep(100 + Random(200));
  // 30% chance the warehouse API is down
  LFailed := Random(100) < 30;
  EW.EndTiming('report.inventory.warehouse_api', nil, not LFailed);

  if LFailed then
  begin
    EW.EndTiming('report.inventory', nil, False);
    EW.Error('Inventory report failed: warehouse API returned 503 Service Unavailable', 'reports');
    EW.IncrementCounter('report.failures', 1);
    TInterlocked.Increment(GErrorCount);

    Result :=
      '<div class="alert alert-danger">' +
      '<strong>Inventory Report failed</strong><br>' +
      'Warehouse API returned 503 Service Unavailable<br>' +
      '<small class="text-muted">This error was logged to ExeWatch with the timing marked as failed. ' +
      'Check Logs filtered by tag "reports" to see the error.</small></div>';
    Exit;
  end;

  // Step 2: Cross-reference with local stock
  EW.StartTiming('report.inventory.cross_reference', 'database');
  Sleep(400 + Random(600));
  EW.EndTiming('report.inventory.cross_reference', nil, True);

  // Step 3: Flag discrepancies
  EW.StartTiming('report.inventory.discrepancies', 'compute');
  Sleep(150 + Random(250));
  EW.EndTiming('report.inventory.discrepancies', nil, True);

  EW.EndTiming('report.inventory', nil, True);
  EW.Info('Inventory report generated: 3 discrepancies found', 'reports');
  EW.IncrementCounter('report.successes', 1);

  Result :=
    '<div class="alert alert-success">' +
    '<strong>Inventory Report generated</strong><br>' +
    '3 discrepancies found between warehouse and local stock.<br>' +
    '<small class="text-muted">The warehouse_api step can randomly fail (30% chance). ' +
    'Try clicking again to see a failure logged to ExeWatch.</small></div>';
end;

function TWebController.GenerateAuditReport: String;
var
  LWarnings: Integer;
begin
  EW.AddBreadcrumb('Generating audit report (multi-source)', 'reports');
  EW.StartTiming('report.audit', 'reports');

  LWarnings := 0;

  // Step 1: Fetch user activity logs
  EW.StartTiming('report.audit.user_activity', 'database');
  Sleep(200 + Random(300));
  EW.EndTiming('report.audit.user_activity', nil, True);
  EW.Info('Loaded 5,230 user activity records', 'reports');

  // Step 2: Fetch financial transactions
  EW.StartTiming('report.audit.transactions', 'database');
  Sleep(300 + Random(500));
  // Sometimes slow — log a warning if > 500ms simulated
  if Random(100) < 40 then
  begin
    Sleep(800);
    EW.Warning('Slow query: transactions took > 1s (consider adding index)', 'reports');
    Inc(LWarnings);
  end;
  EW.EndTiming('report.audit.transactions', nil, True);

  // Step 3: Check compliance rules
  EW.StartTiming('report.audit.compliance_check', 'compute');
  Sleep(100 + Random(200));
  // Check for violations
  if Random(100) < 50 then
  begin
    EW.Warning('Compliance: 2 transactions missing approval signature', 'audit');
    Inc(LWarnings);
  end;
  EW.EndTiming('report.audit.compliance_check', nil, True);

  // Step 4: Cross-reference with external audit service
  EW.StartTiming('report.audit.external_verification', 'external');
  Sleep(400 + Random(600));
  EW.EndTiming('report.audit.external_verification', nil, True);

  EW.EndTiming('report.audit', nil, True);

  if LWarnings > 0 then
    EW.Warning(Format('Audit report completed with %d warnings', [LWarnings]), 'reports')
  else
    EW.Info('Audit report completed — all checks passed', 'reports');

  Result := Format(
    '<div class="alert %s">' +
    '<strong>Audit Report generated</strong><br>' +
    '4 data sources analyzed: user_activity, transactions, compliance_check, external_verification<br>' +
    '%d warning(s) found.<br>' +
    '<small class="text-muted">This report produces nested timings AND warnings. ' +
    'Check both the Timing and Logs pages.</small></div>',
    [IfThen(LWarnings > 0, 'alert-warning', 'alert-success'), LWarnings]);
end;


// ---------------------------------------------------------------------------
//  External Services (simulated calls that can fail)
// ---------------------------------------------------------------------------

function TWebController.ServicesPage: String;
begin
  ViewData['page_title'] := 'Services';

  if Context.Request.IsHTMX then
    Result := RenderView('partials/services_content')
  else
    Result := RenderView('services');
end;

function TWebController.CallPaymentGateway: String;
var
  LOutcome: Integer;
begin
  EW.AddBreadcrumb('Calling payment gateway (amount: EUR 149.99)', 'payment');
  EW.StartTiming('service.payment_gateway', 'external');

  LOutcome := Random(100);

  if LOutcome < 60 then
  begin
    // Success (60%)
    Sleep(200 + Random(300));
    EW.EndTiming('service.payment_gateway', nil, True);
    EW.Info('Payment processed: EUR 149.99 (txn: TXN-' + IntToStr(10000 + Random(90000)) + ')', 'payment');
    EW.IncrementCounter('payment.success', 1);
    Result :=
      '<div class="alert alert-success">' +
      '<strong>Payment successful</strong><br>' +
      'Transaction processed in ~300ms</div>';
  end
  else if LOutcome < 80 then
  begin
    // Timeout (20%)
    Sleep(3000 + Random(2000));
    EW.EndTiming('service.payment_gateway', nil, False);
    EW.Error('Payment gateway timeout after 4s (EUR 149.99)', 'payment');
    EW.IncrementCounter('payment.timeout', 1);
    TInterlocked.Increment(GErrorCount);
    Result :=
      '<div class="alert alert-danger">' +
      '<strong>Payment timeout</strong><br>' +
      'Gateway did not respond within 5 seconds.<br>' +
      '<small class="text-muted">Logged as ERROR with "payment" tag. The timing is marked as failed.</small></div>';
  end
  else if LOutcome < 95 then
  begin
    // Declined (15%)
    Sleep(150 + Random(100));
    EW.EndTiming('service.payment_gateway', nil, False);
    EW.Warning('Payment declined: insufficient funds (EUR 149.99)', 'payment');
    EW.IncrementCounter('payment.declined', 1);
    Result :=
      '<div class="alert alert-warning">' +
      '<strong>Payment declined</strong><br>' +
      'Insufficient funds on the card.<br>' +
      '<small class="text-muted">Logged as WARNING — declined is a business event, not a system error.</small></div>';
  end
  else
  begin
    // Gateway error (5%)
    Sleep(100 + Random(100));
    EW.EndTiming('service.payment_gateway', nil, False);
    try
      raise Exception.Create('Payment gateway returned HTTP 502 Bad Gateway');
    except
      on E: Exception do
      begin
        EW.ErrorWithException(E, 'payment');
        EW.IncrementCounter('payment.errors', 1);
        TInterlocked.Increment(GErrorCount);
        Result :=
          '<div class="alert alert-danger">' +
          '<strong>Gateway error (502)</strong><br>' +
          E.Message + '<br>' +
          '<small class="text-muted">Logged with ErrorWithException — includes stack trace in ExeWatch.</small></div>';
      end;
    end;
  end;
end;

function TWebController.CallEmailService: String;
var
  LOutcome: Integer;
begin
  EW.AddBreadcrumb('Sending email to customer@example.com', 'email');
  EW.StartTiming('service.email', 'external');

  LOutcome := Random(100);

  if LOutcome < 75 then
  begin
    // Success (75%)
    Sleep(100 + Random(200));
    EW.EndTiming('service.email', nil, True);
    EW.Info('Email sent to customer@example.com (template: order_confirmation)', 'email');
    EW.IncrementCounter('email.sent', 1);
    Result :=
      '<div class="alert alert-success">' +
      '<strong>Email sent</strong><br>' +
      'Order confirmation delivered to customer@example.com</div>';
  end
  else if LOutcome < 90 then
  begin
    // Rate limited (15%)
    Sleep(50);
    EW.EndTiming('service.email', nil, False);
    EW.Warning('Email service rate limited (429 Too Many Requests), will retry in 60s', 'email');
    EW.IncrementCounter('email.rate_limited', 1);
    Result :=
      '<div class="alert alert-warning">' +
      '<strong>Rate limited (429)</strong><br>' +
      'Email service is throttling requests. Queued for retry.<br>' +
      '<small class="text-muted">Logged as WARNING with counter "email.rate_limited".</small></div>';
  end
  else
  begin
    // SMTP error (10%)
    Sleep(2000 + Random(1000));
    EW.EndTiming('service.email', nil, False);
    try
      raise Exception.Create('SMTP connection refused: mail.example.com:587');
    except
      on E: Exception do
      begin
        EW.ErrorWithException(E, 'email');
        EW.IncrementCounter('email.errors', 1);
        TInterlocked.Increment(GErrorCount);
        Result :=
          '<div class="alert alert-danger">' +
          '<strong>SMTP error</strong><br>' +
          E.Message + '<br>' +
          '<small class="text-muted">Connection refused after 2s timeout. Logged with full exception.</small></div>';
      end;
    end;
  end;
end;

function TWebController.CallGeocodingAPI: String;
var
  LLatency: Integer;
begin
  EW.AddBreadcrumb('Geocoding address: "Via Roma 1, Milano"', 'geocoding');
  EW.StartTiming('service.geocoding', 'external');

  // Simulate variable latency
  LLatency := 50 + Random(150);

  if Random(100) < 15 then
  begin
    // Simulate cache hit
    Sleep(5 + Random(10));
    EW.EndTiming('service.geocoding', nil, True);
    EW.Debug('Geocoding cache hit for "Via Roma 1, Milano"', 'geocoding');
    EW.IncrementCounter('geocoding.cache_hit', 1);
    Result :=
      '<div class="alert alert-success">' +
      '<strong>Geocoding result (cache hit, ~10ms)</strong><br>' +
      'Lat: 45.4642, Lon: 9.1900<br>' +
      '<small class="text-muted">Logged as DEBUG — cache hits are low-priority information.</small></div>';
  end
  else if Random(100) < 85 then
  begin
    // Normal response
    Sleep(LLatency);
    EW.EndTiming('service.geocoding', nil, True);
    EW.Info(Format('Geocoded "Via Roma 1, Milano" in %d ms', [LLatency]), 'geocoding');
    EW.IncrementCounter('geocoding.success', 1);
    Result := Format(
      '<div class="alert alert-success">' +
      '<strong>Geocoding result (%d ms)</strong><br>' +
      'Lat: 45.4642, Lon: 9.1900<br>' +
      '<small class="text-muted">Normal API response. Check timing distribution on the dashboard.</small></div>',
      [LLatency]);
  end
  else
  begin
    // API key quota exceeded
    Sleep(30);
    EW.EndTiming('service.geocoding', nil, False);
    EW.Error('Geocoding API quota exceeded (10,000/day limit reached)', 'geocoding');
    EW.IncrementCounter('geocoding.quota_exceeded', 1);
    TInterlocked.Increment(GErrorCount);
    Result :=
      '<div class="alert alert-danger">' +
      '<strong>Quota exceeded</strong><br>' +
      'Daily API limit (10,000 requests) reached.<br>' +
      '<small class="text-muted">Logged as ERROR with counter "geocoding.quota_exceeded".</small></div>';
  end;
end;

function TWebController.CallAllServices: String;
var
  LSuccessCount, LFailCount: Integer;
  LResults: string;

  procedure CallService(const AName, ATimingId: string;
    AMinMs, AMaxMs: Integer; AFailPct: Integer);
  begin
    EW.StartTiming(ATimingId, 'external');
    Sleep(AMinMs + Random(AMaxMs - AMinMs));

    if Random(100) < AFailPct then
    begin
      EW.EndTiming(ATimingId, nil, False);
      EW.Error(Format('%s call failed', [AName]), 'services');
      Inc(LFailCount);
      LResults := LResults + Format(
        '<div class="service-result service-fail">%s — FAILED</div>', [AName]);
    end
    else
    begin
      EW.EndTiming(ATimingId, nil, True);
      Inc(LSuccessCount);
      LResults := LResults + Format(
        '<div class="service-result service-ok">%s — OK</div>', [AName]);
    end;
  end;

begin
  LSuccessCount := 0;
  LFailCount := 0;
  LResults := '';

  EW.AddBreadcrumb('Calling all services sequentially', 'services');
  EW.StartTiming('service.orchestration', 'services');

  CallService('Payment Gateway', 'service.payment_gateway', 150, 500, 20);
  CallService('Email Service',   'service.email',           80, 300, 15);
  CallService('Geocoding API',   'service.geocoding',       30, 200, 10);
  CallService('Inventory Check',  'service.inventory',      200, 800, 25);
  CallService('Notification Push', 'service.push',          50, 150, 5);

  EW.EndTiming('service.orchestration', nil, LFailCount = 0);

  if LFailCount > 0 then
  begin
    EW.Warning(Format('Service orchestration: %d/%d succeeded, %d failed',
      [LSuccessCount, LSuccessCount + LFailCount, LFailCount]), 'services');
    TInterlocked.Add(GErrorCount, LFailCount);
  end
  else
    EW.Info(Format('All %d services responded successfully', [LSuccessCount]), 'services');

  Result := Format(
    '<div class="alert %s">' +
    '<strong>Service Orchestration: %d/%d succeeded</strong>' +
    '%s' +
    '<br><small class="text-muted">Each service was timed individually inside the ' +
    'parent "service.orchestration" timing. Check the Timing page.</small></div>',
    [IfThen(LFailCount > 0, 'alert-warning', 'alert-success'),
     LSuccessCount, LSuccessCount + LFailCount, LResults]);
end;


// ---------------------------------------------------------------------------
//  Simulate actions
// ---------------------------------------------------------------------------

function TWebController.SimulateError: String;
begin
  TInterlocked.Increment(GErrorCount);
  EW.IncrementCounter('http.errors', 1);

  try
    raise Exception.Create('Connection to database lost (simulated)');
  except
    on E: Exception do
    begin
      EW.ErrorWithException(E, 'database');
      Result := '<div class="alert alert-danger">' +
                '<strong>Simulated Error:</strong> ' + E.Message +
                '<br><small class="text-muted">Sent to ExeWatch with full exception info.</small></div>';
    end;
  end;
end;

function TWebController.SimulateSlow: String;
var
  LDelayMs: Integer;
begin
  LDelayMs := 800 + Random(1200);

  EW.AddBreadcrumb(Format('Starting slow operation (%d ms)', [LDelayMs]), 'simulate');
  EW.StartTiming('heavy_computation', 'simulate');
  Sleep(LDelayMs);
  EW.EndTiming('heavy_computation', nil, True);
  EW.Info(Format('Slow operation completed in %d ms', [LDelayMs]), 'simulate');

  Result := Format(
    '<div class="alert alert-info">' +
    '<strong>Slow Operation:</strong> Completed in %d ms' +
    '<br><small class="text-muted">Check the Timing page for this entry.</small></div>',
    [LDelayMs]);
end;

function TWebController.SimulateWarning: String;
begin
  EW.Warning('Disk space running low on drive C: — 2.1 GB remaining (simulated)', 'system');
  EW.AddBreadcrumb('Disk space warning triggered', 'simulate');

  Result := '<div class="alert alert-warning">' +
            '<strong>Simulated Warning:</strong> Disk space running low on drive C:' +
            '<br><small class="text-muted">Sent to ExeWatch as a WARNING log entry.</small></div>';
end;


// ---------------------------------------------------------------------------
//  JSON API
// ---------------------------------------------------------------------------

function TWebController.HealthCheck: String;
var
  LJSON: TJSONObject;
begin
  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('status', 'healthy');
    LJSON.AddPair('timestamp', DateToISO8601(Now));
    LJSON.AddPair('requests_total', TJSONNumber.Create(GRequestCount));
    LJSON.AddPair('errors_total', TJSONNumber.Create(GErrorCount));
    LJSON.AddPair('dmvc_version', DMVCFRAMEWORK_VERSION);
    Result := LJSON.ToString;
  finally
    LJSON.Free;
  end;
end;

end.
