# Quick Start

## Build

```bash
cd C:\DEV\exewatchsamples\DelphiWebBroker
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc32.exe" -B -W- WebBrokerSample.dpr
```

## Run

```bash
WebBrokerSample.exe
```

Server starts on port 8080.

## Test

```bash
curl http://localhost:8080/health
curl http://localhost:8080/api/time
curl http://localhost:8080/api/delay?ms=500
```

## API Key

Already configured in `WebBrokerSample.dpr`. To change:

```pascal
InitializeExeWatch(TExeWatchConfig.Create(
  'YOUR_API_KEY',
  'customer_id'
));
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML page |
| `/health` | GET | Health check |
| `/api/info` | GET | App info |
| `/api/echo` | POST | Echo request |
| `/api/time` | GET | Server time |
| `/api/delay` | GET | Delayed response |
