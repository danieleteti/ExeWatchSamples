# ExeWatch — Delphi WebBroker Sample

A REST API server built with Delphi WebBroker that demonstrates monitoring a web service with ExeWatch.

## Requirements

- Embarcadero Delphi 12.3+ (Community Edition works fine)

## Step-by-step

**Step 1** — Open `WebBrokerSample.dproj` in the Delphi IDE.

**Step 2** — Open `WebBrokerSample.dpr` and replace the `EXEWATCH_API_KEY` constant with your own API key (from [exewatch.com](https://exewatch.com)).

**Step 3** — Build and run. The server starts on port 8080 (use `-p 9000` for a different port).

**Step 4** — Test the endpoints:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/api/info
curl http://localhost:8080/api/time
```

**Step 5** — Open the ExeWatch dashboard to see logs, timings, and metrics appear in real time.

## Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML page listing all endpoints |
| `/health` | GET | Health check with request/error counts |
| `/api/info` | GET | Application information |
| `/api/echo` | POST | Echo back the request |
| `/api/time` | GET | Current server timestamp |
| `/api/delay` | GET | Simulate slow response (`?ms=500`) |

## How It Works

The WebModule wraps every request through `HandleRequest`, which:

1. Increments `http.requests` counter
2. Adds a breadcrumb for the request
3. Starts timing the endpoint
4. Executes the handler
5. Records timing (success or failure)

On errors: increments `http.errors` counter, logs the exception, returns HTTP 500.

```pascal
function TWebModule1.HandleRequest(Request: TWebRequest; Response: TWebResponse;
  const Endpoint: string; Handler: TProc): Boolean;
begin
  Result := True;
  EW.IncrementCounter('http.requests', 1);
  EW.AddBreadcrumb('request: ' + Endpoint, 'http');
  EW.StartTiming(Endpoint);
  try
    Handler;
    EW.EndTiming(Endpoint, nil, True);
  except
    on E: Exception do
    begin
      EW.IncrementCounter('http.errors', 1);
      EW.EndTiming(Endpoint, nil, False);
      EW.ErrorWithException(E, Endpoint);
      Response.StatusCode := 500;
    end;
  end;
end;
```

## Files

| File | Role |
|------|------|
| `WebBrokerSample.dpr` | Main program — initializes SDK, starts server |
| `WebModuleU.pas` | WebModule — endpoints and ExeWatch integration |
| `ServerConstU.pas` | Server string constants |
