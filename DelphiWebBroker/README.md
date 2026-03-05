# ExeWatch WebBroker Sample

A demonstration Delphi WebBroker application integrated with ExeWatch SDK for logging, metrics, and error tracking.

## What It Demonstrates

This sample application showcases how to integrate ExeWatch into a Delphi WebBroker server to monitor:

- **Request Logging**: Every HTTP request is logged with breadcrumbs
- **Timing**: Each endpoint's response time is measured and recorded
- **Error Tracking**: Exceptions are automatically captured and reported with full context
- **Metrics**: Counters track total requests and errors
- **Global Tags**: Context tags are added to all events

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML page listing all endpoints |
| `/health` | GET | Health check with request/error counts |
| `/api/info` | GET | Application information |
| `/api/echo` | POST | Echo back the request |
| `/api/time` | GET | Current server timestamp |
| `/api/delay` | GET | Simulate slow response (optional `?ms=500` parameter) |

## Building

```bash
cd C:\DEV\exewatchsamples\DelphiWebBroker
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc32.exe" -B -W- WebBrokerSample.dpr
```

## Running

```bash
WebBrokerSample.exe
```

The server starts automatically on port 8080.

To change the port:

```bash
WebBrokerSample.exe -p 9000
```

Press Ctrl+C to stop the server.

## ExeWatch Integration Details

### Initialization

The SDK is initialized in `WebBrokerSample.dpr`:

```pascal
InitializeExeWatch(TExeWatchConfig.Create(
  'YOUR_API_KEY',
  'demo_customer'
));
EW.SetTag('app', 'WebBrokerSample');
EW.SetTag('platform', 'Delphi');
EW.IncrementCounter('http.requests', 0);
EW.IncrementCounter('http.errors', 0);
```

### Request Handling

Every request goes through `HandleRequest` which:

1. Increments the request counter
2. Adds a breadcrumb for the request
3. Starts timing the request
4. Executes the handler
5. Records the timing result (success/failure)

### Error Handling

If an exception occurs:

- Error counter is incremented
- Exception is logged with full details
- Error breadcrumb is added
- HTTP 500 response is returned

### Metrics

Two counters are tracked:

- `http.requests` - Total number of HTTP requests
- `http.errors` - Total number of errors

These are automatically flushed to ExeWatch every 30 seconds.

## Files

- `WebBrokerSample.dpr` - Main program
- `WebModuleU.pas` - WebModule with endpoints and ExeWatch integration
- `WebModuleU.dfm` - Action definitions
- `ExeWatchSDKv1.pas` - ExeWatch SDK
- `ServerConstU.pas` - Server constants
