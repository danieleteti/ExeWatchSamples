# ExeWatch — .NET Windows Forms Sample

An interactive desktop application that demonstrates every ExeWatch SDK feature through a tabbed GUI. The API key is entered at runtime — no code editing needed.

## Requirements

- .NET 8.0 or later
- Visual Studio 2022 (17.8+) or JetBrains Rider 2024.1+

## Step-by-step

**Step 1** — Open `DotNetWindowsForms.csproj` in Visual Studio.

**Step 2** — Press F5 to run.

**Step 3** — Enter your API key (from [exewatch.com](https://exewatch.com)) and Customer ID in the connection panel, then click **Use**.

**Step 4** — Explore the tabs:

- **Logging** — send individual logs or generate a batch with breadcrumbs; test automatic exception capture
- **Timing** — nested timings, parallel timings, LIFO stack, cancel, metadata, and a "Run All" button
- **Device Info** — send custom key-value pairs alongside the standard hardware info
- **Metrics** — counters (increment, batch, tagged), gauges (single, multiple, tagged), periodic gauges
- **Updates** — simulate version upgrades/downgrades, populate simulated devices

**Step 5** — Open the ExeWatch dashboard to see your events arrive in real time.

## How it works

The WinForms sample uses two SDK packages:

| Package | Role |
|---------|------|
| `ExeWatch` | Core SDK — logging, timing, metrics, device info |
| `ExeWatch.WinForms` | WinForms hook — captures `Application.ThreadException` automatically |

`ExeWatchWinForms.Install()` is called in `Program.cs` before `Application.Run()` to ensure unhandled GUI exceptions are captured.

## Files

| File | Role |
|------|------|
| `Program.cs` | Entry point — installs WinForms exception hook |
| `MainForm.cs` | Main form — all SDK feature demos |
| `MainForm.Designer.cs` | Visual Studio designer (auto-generated) |
