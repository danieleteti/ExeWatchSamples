unit WebModuleU;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.DateUtils, System.SyncObjs,
  Web.HTTPApp, ExeWatchSDKv1;

type
  TWebModule1 = class(TWebModule)
    procedure WebModule1DefaultHandlerAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1HealthAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1APIInfoAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1APIEchoAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1APITimeAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1APIDelayAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1APITraceAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
  private
    function HandleRequest(Request: TWebRequest; Response: TWebResponse;
      const Endpoint: string; Handler: TProc): Boolean;
  public
    { Public declarations }
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;
  GRequestCount: Int64 = 0;
  GErrorCount: Int64 = 0;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

function TWebModule1.HandleRequest(Request: TWebRequest; Response: TWebResponse;
  const Endpoint: string; Handler: TProc): Boolean;
begin
  Result := True;
  TInterlocked.Increment(GRequestCount);
  EW.IncrementCounter('http.requests', 1);
  try
    EW.AddBreadcrumb('request: ' + Endpoint, 'http');
    EW.StartTiming(Endpoint);
    try
      Handler;
      EW.EndTiming(Endpoint, nil, True);
    except
      on E: Exception do
      begin
        TInterlocked.Increment(GErrorCount);
        EW.IncrementCounter('http.errors', 1);
        EW.EndTiming(Endpoint, nil, False);
        EW.ErrorWithException(E, Endpoint);
        Response.StatusCode := 500;
        Response.Content := '{"error":"Internal Server Error","message":"' + E.Message + '"}';
        Response.ContentType := 'application/json';
      end;
    end;
  except
    on E: Exception do
    begin
      Response.StatusCode := 500;
      Response.Content := '{"error":"Internal Server Error","message":"' + E.Message + '"}';
      Response.ContentType := 'application/json';
    end;
  end;
end;

procedure TWebModule1.WebModule1DefaultHandlerAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, 'GET /', procedure
    var
      HTML: string;
    begin
      HTML := '<!DOCTYPE html>' +
              '<html>' +
              '<head>' +
              '  <title>ExeWatch WebBroker Sample</title>' +
              '  <style>' +
              '    body { font-family: Arial, sans-serif; margin: 40px; }' +
              '    h1 { color: #333; }' +
              '    .endpoint { background: #f5f5f5; padding: 10px; margin: 5px 0; border-radius: 4px; }' +
              '    .method { color: #0066cc; font-weight: bold; }' +
              '  </style>' +
              '</head>' +
              '<body>' +
              '  <h1>ExeWatch WebBroker Sample</h1>' +
              '  <p>Available endpoints:</p>' +
              '  <div class="endpoint"><span class="method">GET</span> / - This page</div>' +
              '  <div class="endpoint"><span class="method">GET</span> /health - Health check</div>' +
              '  <div class="endpoint"><span class="method">GET</span> /api/info - API information</div>' +
              '  <div class="endpoint"><span class="method">POST</span> /api/echo - Echo back request</div>' +
              '  <div class="endpoint"><span class="method">GET</span> /api/time - Current server time</div>' +
              '  <div class="endpoint"><span class="method">GET</span> /api/delay - Simulate slow response</div>' +
              '</body>' +
              '</html>';
      Response.Content := HTML;
      Response.ContentType := 'text/html';
    end);
end;

procedure TWebModule1.WebModule1HealthAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, 'GET /health', procedure
    var
      JSON: TJSONObject;
    begin
      JSON := TJSONObject.Create;
      try
        JSON.AddPair('status', 'healthy');
        JSON.AddPair('timestamp', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now));
        JSON.AddPair('uptime', '0');
        JSON.AddPair('requests_total', TJSONNumber.Create(GRequestCount));
        JSON.AddPair('errors_total', TJSONNumber.Create(GErrorCount));
        Response.Content := JSON.ToString;
        Response.ContentType := 'application/json';
        Response.StatusCode := 200;
      finally
        JSON.Free;
      end;
    end);
end;

procedure TWebModule1.WebModule1APIInfoAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, 'GET /api/info', procedure
    var
      JSON: TJSONObject;
    begin
      JSON := TJSONObject.Create;
      try
        JSON.AddPair('application', 'ExeWatch WebBroker Sample');
        JSON.AddPair('version', '1.0.0');
        JSON.AddPair('platform', 'Delphi WebBroker');
        JSON.AddPair('endpoints', TJSONArray.Create
          .Add('/health')
          .Add('/api/info')
          .Add('/api/echo')
          .Add('/api/time')
          .Add('/api/delay'));
        Response.Content := JSON.ToString;
        Response.ContentType := 'application/json';
        Response.StatusCode := 200;
      finally
        JSON.Free;
      end;
    end);
end;

procedure TWebModule1.WebModule1APIEchoAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, Request.Method + ' /api/echo', procedure
    var
      JSON: TJSONObject;
      I: Integer;
    begin
      JSON := TJSONObject.Create;
      try
        JSON.AddPair('method', Request.Method);
        JSON.AddPair('path', Request.PathInfo);
        JSON.AddPair('query', Request.Query);

        if Request.Authorization <> '' then
          JSON.AddPair('authorization', '(hidden)');

        if Request.QueryFields.Count > 0 then
        begin
          for I := 0 to Request.QueryFields.Count - 1 do
            JSON.AddPair('param_' + Request.QueryFields.Names[I], Request.QueryFields.ValueFromIndex[I]);
        end;

        if Request.ContentLength > 0 then
        begin
          JSON.AddPair('content_length', TJSONNumber.Create(Request.ContentLength));
          JSON.AddPair('content_type', Request.ContentType);
          if (Pos('application/x-www-form-urlencoded', Request.ContentType) > 0) or
             (Pos('text/', Request.ContentType) > 0) then
            JSON.AddPair('body', Request.Content);
        end;

        Response.Content := JSON.ToString;
        Response.ContentType := 'application/json';
        Response.StatusCode := 200;
      finally
        JSON.Free;
      end;
    end);
end;

procedure TWebModule1.WebModule1APITimeAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, 'GET /api/time', procedure
    var
      JSON: TJSONObject;
    begin
      JSON := TJSONObject.Create;
      try
        JSON.AddPair('unixtime', TJSONNumber.Create(DateTimeToUnix(Now)));
        JSON.AddPair('datetime', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
        JSON.AddPair('iso8601', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now));
        Response.Content := JSON.ToString;
        Response.ContentType := 'application/json';
        Response.StatusCode := 200;
      finally
        JSON.Free;
      end;
    end);
end;

procedure TWebModule1.WebModule1APIDelayAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Handled := HandleRequest(Request, Response, 'GET /api/delay', procedure
    var
      DelayMs: Integer;
      JSON: TJSONObject;
    begin
      DelayMs := 100;
      if Request.QueryFields.Count > 0 then
        TryStrToInt(Request.QueryFields.Values['ms'], DelayMs);

      if DelayMs < 0 then DelayMs := 0;
      if DelayMs > 10000 then DelayMs := 10000;

      Sleep(DelayMs);

      JSON := TJSONObject.Create;
      try
        JSON.AddPair('delayed_ms', TJSONNumber.Create(DelayMs));
        JSON.AddPair('timestamp', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now));
        Response.Content := JSON.ToString;
        Response.ContentType := 'application/json';
        Response.StatusCode := 200;
      finally
        JSON.Free;
      end;
    end);
end;

// ---------------------------------------------------------------------------
//  GET /api/trace  ->  Nested Timing Trace demo
// ---------------------------------------------------------------------------
//
//  Produces a profiler-style "waterfall" of one request's work in ExeWatch.
//  EW.StartTrace opens a named ROOT trace and returns a 16-hex trace id; every
//  EW.StartTiming / EW.EndTiming run before EW.EndTrace auto-nests under it via
//  the SDK's per-thread LIFO stack. A WebBroker action runs entirely on the
//  request thread, so the whole tree is captured in order: ValidateRequest,
//  then QueryDatabase (with OpenConnection + RunQuery as children), then
//  SerializeJson. This action handles the trace directly (instead of the shared
//  HandleRequest helper) so the trace is a clean ROOT span; the existing flat
//  StartTiming/EndTiming endpoints are untouched. EndTrace runs on every path.
//
procedure TWebModule1.WebModule1APITraceAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  LTraceId: string;
  LTotalMs: Double;
  JSON: TJSONObject;
begin
  Handled := True;
  TInterlocked.Increment(GRequestCount);
  EW.IncrementCounter('http.requests', 1);
  EW.AddBreadcrumb('request: GET /api/trace', 'http');

  LTraceId := EW.StartTrace('HandleApiTrace');
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
      TInterlocked.Increment(GErrorCount);
      EW.IncrementCounter('http.errors', 1);
      EW.EndTrace;
      EW.ErrorWithException(E, 'GET /api/trace');
      Response.StatusCode := 500;
      Response.Content := '{"error":"Internal Server Error","message":"' + E.Message + '"}';
      Response.ContentType := 'application/json';
      Exit;
    end;
  end;

  EW.Info(Format('Trace "HandleApiTrace" completed (id %s) in ~%.0f ms',
    [LTraceId, LTotalMs]), 'trace');

  JSON := TJSONObject.Create;
  try
    JSON.AddPair('trace_id', LTraceId);
    JSON.AddPair('total_ms', TJSONNumber.Create(LTotalMs));
    JSON.AddPair('spans', TJSONArray.Create
      .Add('ValidateRequest')
      .Add('QueryDatabase')
      .Add('QueryDatabase.OpenConnection')
      .Add('QueryDatabase.RunQuery')
      .Add('SerializeJson'));
    JSON.AddPair('note', 'Open the Timing / Traces page in ExeWatch to see the waterfall.');
    Response.Content := JSON.ToString;
    Response.ContentType := 'application/json';
    Response.StatusCode := 200;
  finally
    JSON.Free;
  end;
end;

end.
