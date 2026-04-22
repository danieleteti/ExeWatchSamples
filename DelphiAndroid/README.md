# ExeWatch - Delphi Android Sample

A FireMonkey (FMX) application targeting **Android** that exercises every feature of the ExeWatch Delphi SDK in one scrollable screen.

## What this sample demonstrates

Every button on the screen calls a different SDK entry point, so you can tap your way through the full API while watching events appear in the ExeWatch dashboard:

- **Log levels** - Debug, Info, Warning, Error, Fatal (plus a formatted-message variant)
- **Exceptions** - caught + `ErrorWithException`, and an unhandled FMX exception that is auto-captured by `ExeWatchSDKv1.FMX`
- **Breadcrumbs** - add plain and typed breadcrumbs, inspect/clear the queue, and trigger an Error that attaches the last ones
- **Timing / profiling** - `StartTiming` / `EndTiming`, a quick 500 ms measurement from a background thread, listing active timings
- **User identity** - set, read, and clear the current user
- **Global tags** - set, read, and clear tags
- **Customer ID** - change the customer identifier at runtime
- **Device info** - send the automatic device payload + attach custom key/value pairs
- **Metrics** - counters, one-off gauges, and a periodic gauge registered with a closure
- **Background thread** - the same feature set invoked from a `TThread` to verify thread-safety
- **Flush & diagnostics** - force a flush, read the pending-file count, and the current session id

## Why a dedicated Android sample

The `DelphiFMX` sample targets FMX desktop (Windows / macOS / Linux). Android adds mobile-specific concerns:

- **Screen layout** - the UI is built programmatically in `FormCreate` as a narrow vertical `TVertScrollBox`, which renders correctly on phones without depending on a specific FireMonkey form-factor preview.
- **Device info** - the payload you will see in the dashboard is Android-flavoured (manufacturer, model, OS version, screen density, mobile locale, etc.).
- **Unhandled-exception capture** - Android tears processes down differently from Windows. The "Unhandled Exception (FMX)" button is the quickest way to verify that `ExeWatchSDKv1.FMX` captures the crash *before* the app dies.
- **Background threads** - mobile code almost always does I/O off the UI thread; the "Background Thread" section proves every SDK entry point is thread-safe on Android too.

## Prerequisites

- Embarcadero Delphi 11+ (Community, Professional, Enterprise or Architect - any edition that ships FMX mobile targets).
- Android platform SDK configured in the IDE (Tools > Options > Deployment > SDK Manager).
- An Android device connected via USB in developer mode, **or** the Android emulator.
- An ExeWatch API key for an application whose platform is **Android**. Free Hobby plan works: <https://exewatch.com>. Keys are prefixed with `ew_and_`.

## How to run

1. Open `ExeWatchAndroidSample.dproj` in Delphi.
2. Open `MainFormU.pas` and replace `EXEWATCH_API_KEY` with your real key. Optionally tweak `CUSTOMER_ID`.
3. In the Project Manager, expand **Target Platforms** and set **Android (64-bit)** (or 32-bit for older devices) as active.
4. Select your physical device or emulator under **Target**.
5. Deploy and run (F9). If the key placeholder is still in place the app shows a dialog and exits on startup.
6. Tap through the buttons and watch the **Logs**, **Devices**, **Metrics**, and **Timings** pages in the ExeWatch dashboard update in real time.

## File layout

```
DelphiAndroid/
|-- ExeWatchAndroidSample.dpr        Program entry
|-- ExeWatchAndroidSample.dproj      Project file (Android 32 + 64 targets)
|-- ExeWatchAndroidSample.deployproj Deployment manifest
|-- ExeWatchAndroidSample.res        Compiled resources
|-- AndroidManifest.template.xml     Manifest template (includes permissions)
|-- MainFormU.pas / .fmx             Demo form with all feature buttons
`-- README.md                        This file
```

The SDK source units (`ExeWatchSDKv1.pas`, `ExeWatchSDKv1.FMX.pas`) are referenced from `../DelphiCommons/` - they are shipped with this repository.

## SDK pattern - FMX vs VCL

For Android (and every FMX target) the only change compared to the VCL sample is the uses clause:

```pascal
uses
  ExeWatchSDKv1,
  ExeWatchSDKv1.FMX;   // <-- FMX-specific; NOT ExeWatchSDKv1.VCL
```

Everything else (logging, breadcrumbs, timings, metrics, etc.) is identical to VCL. The FMX unit installs a hook into FMX's `Application.OnException` so unhandled GUI exceptions are captured automatically as Fatal logs.

## Full docs

<https://exewatch.com/ui/docs>
