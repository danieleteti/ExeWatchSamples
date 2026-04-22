# ExeWatch Samples

Official sample projects demonstrating how to integrate [ExeWatch](https://exewatch.com) into your applications.

## What is ExeWatch?

ExeWatch is a real-time application monitoring platform for **Delphi**, **.NET / C#**, and **JavaScript** applications. It captures errors, logs, performance timings, hardware info, and user behavior — giving you full visibility into what happens in production, without needing to reproduce issues locally.

Key capabilities:

- **Logging** with five severity levels (Debug, Info, Warning, Error, Fatal)
- **Automatic exception capture** — unhandled errors are caught and reported
- **Breadcrumb trails** — see exactly what happened before an error
- **Performance timings** — measure operations with Avg/Min/Max/P95 stats
- **Hardware intelligence** — CPU, RAM, disk, OS, monitor details
- **Multi-customer tracking** — filter logs by customer ID
- **Email and timing alerts** — get notified when things go wrong

For full documentation, visit: **https://exewatch.com/ui/docs**

## Prerequisites

You need an ExeWatch account to run these samples. **The free Hobby plan requires no credit card** and includes:

- 1 application
- 10,000 events/month
- 7-day log retention
- 2 alerts (email + timing)

This is enough for personal projects and small commercial applications. Sign up at **https://exewatch.com**.

**Important:** Once registered, create an application in the ExeWatch dashboard and copy your **API Key**. Every sample requires a valid API key to send data — without it, the app will show an error and exit.

## Samples

### Delphi

| Sample | Description | Details |
|--------|-------------|---------|
| [Delphi VCL](DelphiVCL/) | Windows desktop app with buttons for every SDK feature: logging, timing, breadcrumbs, user identity, tags, metrics, and automatic VCL exception capture. | [README](DelphiVCL/README.md) |
| [Delphi FMX](DelphiFMX/) | Cross-platform FireMonkey app — same feature coverage as the VCL sample but using the FMX framework. Uses `ExeWatchSDKv1.FMX` for GUI exception capture. Can target Windows, macOS, Linux, iOS, and Android. | [README](DelphiFMX/README.md) |
| [Delphi Android](DelphiAndroid/) | FMX application targeting **Android** specifically. Narrow scrollable UI built programmatically; exercises every SDK entry point (logs, exceptions, breadcrumbs, timings, identity, tags, customer id, device info, metrics, background-thread usage, flush) so you can tap through the full API on a phone or emulator. | [README](DelphiAndroid/README.md) |
| [Delphi WebBroker](DelphiWebBroker/) | REST API server that wraps every HTTP request with ExeWatch timing, error tracking, and request counters. 6 demo endpoints included. | [README](DelphiWebBroker/README.md) |
| [Delphi DMVCFramework](DelphiDMVCFramework/) | Full web app with TemplatePro + HTMX. People CRUD, heavy reports with nested timings, simulated external services with realistic failures, batch imports with structured extra data, breadcrumb trails, counters, and periodic gauges. The most complete server-side sample. | [README](DelphiDMVCFramework/README.md) |

**Requirements:** Embarcadero Delphi 11+ (DMVCFramework sample also requires [DMVCFramework](https://github.com/danieleteti/delphimvcframework))

### .NET / C#

| Sample | Description | Details |
|--------|-------------|---------|
| [.NET Console](DotNetConsole/) | Console app that runs through all SDK features sequentially. Includes 20 timed iterations with random failures to generate meaningful Avg/Min/Max/P95 stats. | [README](DotNetConsole/README.md) |
| [.NET Windows Forms](DotNetWindowsForms/) | Interactive desktop app with a tabbed GUI. API key entered at runtime — no code editing needed. Covers logging, nested timings, metrics, device info, and version upgrades. | [README](DotNetWindowsForms/README.md) |
| [.NET Windows Service](DotNetWindowsService/) | Worker Service with a 10-second processing cycle. Shows nested timings, try/catch error handling, counters, gauges, and graceful shutdown. Can be installed as a real Windows Service. | [README](DotNetWindowsService/README.md) |

**Requirements:** .NET 8.0+ — Visual Studio 2022 (17.8+) or JetBrains Rider 2024.1+

### JavaScript

| Sample | Description | Details |
|--------|-------------|---------|
| [JavaScript Browser](JS/) | Single HTML page — no build tools, no npm. Loads the SDK from CDN and provides buttons for every feature. | [README](JS/README.md) |

**Requirements:** Any modern browser (Chrome, Firefox, Edge, Safari)

## API Comparison

The API is intentionally similar across all SDKs:

| Feature | Delphi | C# / .NET | JavaScript |
|---------|--------|-----------|------------|
| Initialize | `InitializeExeWatch(key, id)` | `ExeWatchSdk.Initialize(config)` | `window.ewConfig = { apiKey, customerId }` |
| Log | `EW.Info(...)` | `EW.Info(...)` | `ew.info(...)` |
| Breadcrumbs | `EW.AddBreadcrumb(...)` | `EW.AddBreadcrumb(...)` | `ew.addBreadcrumb(...)` |
| Timing | `EW.StartTiming` / `EW.EndTiming` | `EW.StartTiming` / `EW.EndTiming` | `ew.startTiming` / `ew.endTiming` |
| User identity | `EW.SetUser(id, email, name)` | `EW.SetUser(id, email, name)` | `ew.setUser({ id, email, name })` |
| Tags | `EW.SetTag(key, value)` | `EW.SetTag(key, value)` | `ew.setTag(key, value)` |
| Metrics | `EW.IncrementCounter` / `EW.RecordGauge` | `EW.IncrementCounter` / `EW.RecordGauge` | `ew.incrementCounter` / `ew.recordGauge` |
| Exceptions | Automatic | Automatic | Automatic |

### Specific Scenarios (HowTo)

| Scenario | Question |
|----------|----------|
| [InitialCustomDeviceInfo](SpecificScenarios/InitialCustomDeviceInfo/) | How do I attach tags and environment info (RDP, Terminal Server, desktop mode) to the first log event and device info at startup? |

See the [SpecificScenarios README](SpecificScenarios/README.md) for the full list.

## Learn More

- **Documentation**: https://exewatch.com/ui/docs
- **Pricing**: https://exewatch.com/ui/pricing
- **Changelog**: https://exewatch.com/ui/changelog
- **Contact**: exewatch@bittime.it
