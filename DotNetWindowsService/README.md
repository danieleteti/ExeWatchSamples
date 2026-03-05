# ExeWatch — .NET Windows Service Sample

A Worker Service that demonstrates monitoring a long-running background process with ExeWatch. It can run as a console app during development or be installed as a real Windows Service.

## Requirements

- .NET 8.0 or later
- Visual Studio 2022 (17.8+) or JetBrains Rider 2024.1+

## Step-by-step

**Step 1** — Open `DotNetWindowsService.csproj` in Visual Studio.

**Step 2** — Open `Worker.cs` and replace `ew_win_YOUR_API_KEY_HERE` with your API key (from [exewatch.com](https://exewatch.com)).

**Step 3** — Press F5 to run as a console app. The service processes a cycle every 10 seconds, generating timing and metric data continuously.

**Step 4** — To install as a real Windows Service:

```bash
dotnet publish -c Release -o C:\Services\ExeWatchDemo
sc create ExeWatchDemo binPath="C:\Services\ExeWatchDemo\DotNetWindowsService.exe"
sc start ExeWatchDemo
```

**Step 5** — Open the ExeWatch dashboard to see logs, timings, and metrics from each processing cycle.

## How it works

The service follows the recommended pattern for long-running .NET services:

| Method | ExeWatch integration |
|--------|---------------------|
| `StartAsync` | Initialize SDK, set tags, send device info |
| `ExecuteAsync` | Main loop — each cycle is timed and monitored |
| `ProcessCycleAsync` | Nested timings for sub-operations (fetch, transform) |
| `StopAsync` | Shut down SDK (flushes remaining logs) |

Each processing cycle demonstrates:

- **Outer timing** (`process_cycle`) wrapping the entire cycle
- **Nested timings** (`fetch_data`, `transform_data`) for individual sub-operations
- **try/catch pattern** — success marks timing as passed, exception marks it as failed with error details
- **Counters** (`items_processed`) and **gauges** (`batch_size`) for metrics
- **Graceful error handling** — failed cycles don't crash the service

## Files

| File | Role |
|------|------|
| `Program.cs` | Host builder — configures Windows Service support |
| `Worker.cs` | Background worker — main processing loop with ExeWatch instrumentation |
