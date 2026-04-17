# madExcept Integration

> **Question:** *I already use madExcept in my Delphi VCL app. How do I forward intercepted exceptions to ExeWatch with the stack trace madExcept has already resolved (unit names + line numbers), instead of the raw addresses the SDK captures on its own?*

This sample answers exactly that.

## What this sample demonstrates

- A **single bridge unit** (`ExeWatchMadExceptBridgeU.pas`) that registers a madExcept callback and forwards every intercepted exception to ExeWatch.
- Use of the new SDK method `EW.ErrorWithStackTrace(Message, Tag, StackTrace, ExceptionClass)` — the SDK stores the caller-provided stack verbatim and **skips its own capture**, so what you see in the ExeWatch dashboard is madExcept's symbolicated stack.
- Three buttons to trigger: a regular `Exception.Create`, a nil-pointer access violation (hardware exception — bypasses `try/except`), and a plain `EW.Info` log for baseline comparison.

## Why forward madExcept's stack

madExcept installs low-level hooks **before** the VCL's `Application.OnException`. When it fires, Delphi's standard handler never runs, so the SDK's auto-capture path never triggers. Even if you manually call `EW.ErrorWithException(E)`, the SDK falls back to a raw `StackWalk` — which typically produces hex addresses in a production build, because most Delphi shops don't ship debug symbols.

madExcept already resolved that same stack with the JDBG/MAP info embedded at link time. Sending *that* string to ExeWatch gives you a searchable, symbolicated stack in the dashboard with zero extra setup on the server side.

## How the bridge works

```pascal
procedure ExeWatchMadExceptHandler(const ExceptIntf: IMEException;
  var Handled: Boolean);
var
  StackTrace, ExClass, ExMsg: string;
  E: TObject;
begin
  if (ExceptIntf = nil) or (not ExeWatchIsInitialized) then
    Exit;

  StackTrace := ExceptIntf.BugReport;

  E := ExceptIntf.ExceptObject;
  if Assigned(E) and (E is Exception) then
  begin
    ExClass := E.ClassName;
    ExMsg   := Exception(E).Message;
  end
  else
  begin
    ExClass := ExceptIntf.ExceptClass;
    ExMsg   := ExceptIntf.ExceptMessage;
  end;

  EW.ErrorWithStackTrace(ExMsg, 'exception', StackTrace, ExClass);
  // Handled is left untouched — madExcept's dialog / bug report still runs.
end;

initialization
  RegisterExceptionHandler(ExeWatchMadExceptHandler, stDontSync);
```

`stDontSync` tells madExcept not to marshal to the main thread — ExeWatch's `Log` APIs are thread-safe.

## Prerequisites

- Delphi 12.3+ (RAD Studio)
- **madExcept installed in the IDE** (install from <https://madshi.net/madExceptDownload.htm>)
- An ExeWatch API key (<https://exewatch.com>)
- SDK version **0.22.0+** (adds `ErrorWithStackTrace`, which lets the caller supply a pre-built stack). Older SDKs only expose `ErrorWithException(E)`, which forces SDK-side capture.

## How to run

1. Open `EWMadExceptIntegration.dproj` in Delphi.
2. Enable madExcept for the project: **Project > madExcept settings > "madExcept enabled"** — this embeds the hooks and the debug info used to resolve frames.
3. Replace `EXEWATCH_API_KEY` in `MainFormU.pas` with your real key.
4. Build and run (F9).
5. Click each button in turn. For each exception:
   - madExcept's usual dialog appears (bug report, optional email, etc.).
   - An `ERROR`-level log appears in your ExeWatch dashboard with a `stack_trace` field containing the madExcept-resolved frames.

## Variations

### Send the full madExcept bug report instead of just the stack

If you want the extra context (module list, thread list, registers, CPU), replace `ExtractMadExceptStackTrace` with:

```pascal
Result := string(ExceptIntf.BugReport);
```

Tradeoff: `BugReport` can be 50–100 KB per exception. ExeWatch's default `max_message_length` truncates anything longer than 50 000 chars — the stack field is not truncated but bandwidth and storage add up. The dedicated call stack (`CallStack.ToString`) is usually a few KB and is the recommended default.

### Forward only crashes, not regular exceptions

```pascal
if not ExceptIntf.Crashed then
  Exit;
```

Add this as the first guard in the handler. This drops everything that a `try/except` would normally catch and lets only actual crashes through to ExeWatch — useful if your app legitimately raises a lot of exceptions.

### Coexist with EurekaLog instead of madExcept

EurekaLog exposes an equivalent callback: `RegisterEventExceptionNotify`. The principle is identical — extract EurekaLog's resolved stack, then call `EW.ErrorWithStackTrace(E.Message, 'exception', Stack, E.ClassName)`.

## File layout

```
madExceptIntegration/
├── EWMadExceptIntegration.dpr        Program entry — "uses madExcept, ..."
├── EWMadExceptIntegration.dproj      Project file (Win32 + Win64)
├── MainFormU.pas / .dfm              Demo form with three buttons
├── ExeWatchMadExceptBridgeU.pas      The bridge — drop this into your own app
└── README.md                         This file
```

`ExeWatchMadExceptBridgeU.pas` is the only file you need in your own project. Add it to your uses clause (or just to the project file) and you are done — the `initialization` section installs the callback.

## Full docs

<https://exewatch.com/ui/docs> — search for "Coexisting with madExcept".
