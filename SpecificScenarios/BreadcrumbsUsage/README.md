# Breadcrumbs Usage

> **Question:** *How exactly do breadcrumbs work in the Delphi SDK? Do I add them in batches? Does `EW.Error` fire automatically, or do I call it myself?*

This sample answers the three most common breadcrumb questions in one runnable project.

## What this sample demonstrates

Four buttons exercise the four patterns you will encounter in real code:

| Button | What it does | Breadcrumbs attached? |
|--------|--------------|------------------------|
| 1. Open Settings (navigation)   | Adds a single `btNavigation` breadcrumb. No log sent. | No — just buffered. |
| 2. Save — caught exception      | Adds breadcrumbs inside `try..except`, then the `except` branch calls `EW.ErrorWithException(E)`. | **Yes** — attached to the Error log. |
| 3. Crash — unhandled exception  | Adds breadcrumbs, then dereferences a `nil` pointer **without** `try..except`. The SDK's VCL hook (`Application.OnException`) auto-logs it as **Fatal**. | **Yes** — attached automatically. |
| 4. Info log                     | Adds a breadcrumb, then calls `EW.Info(...)`. | **No** — breadcrumbs only attach to Error/Fatal. |

## The three rules to remember

1. **Scatter, don't batch.** Place `AddBreadcrumb` where the action happens — in event handlers, before a DB query, before an HTTP call. Four `AddBreadcrumb` calls in a row (as in some documentation snippets) is an artificial compression; real code spreads them out.
2. **Manual *or* automatic, both paths lead to the same attachment.**
   - *Unhandled* exceptions are auto-captured by the SDK (`System.ExceptProc` hook; and `Application.OnException` for VCL/FMX when you `uses ExeWatchSDKv1.VCL` / `ExeWatchSDKv1.FMX`). They become **Fatal** logs. No user code needed.
   - *Caught* exceptions and *logical* errors require you to call `EW.Error(...)` or `EW.ErrorWithException(E)` yourself.
3. **Only Error and Fatal attach breadcrumbs.** Info/Warning/Debug logs do **not** — breadcrumbs stay in the per-thread FIFO (max 20) waiting for the next Error/Fatal.

## Prerequisites

- Embarcadero Delphi 12 (or any XE8+ in principle — the `.dproj` targets Delphi 12, but the code is compatible with XE8+).
- An ExeWatch API key ([get one here](https://exewatch.com)).
- ExeWatch SDK v0.18.0 or newer (for per-thread breadcrumb isolation).

## How to run

1. Open `EWBreadcrumbsUsage.dproj` in Delphi.
2. Open `MainFormU.pas` and replace the `EXEWATCH_API_KEY` constant with your real key.
3. Build and run (F9).
4. Click the buttons **in order** and watch the ExeWatch dashboard:
   - Buttons 1 and 4 produce no Error/Fatal, so no breadcrumbs are sent.
   - Button 2 produces an **Error** log with the breadcrumbs accumulated since app start.
   - Button 3 produces a **Fatal** log auto-captured by the VCL hook, with its own breadcrumbs attached.

## File layout

```
BreadcrumbsUsage/
├── EWBreadcrumbsUsage.dpr        Program entry
├── EWBreadcrumbsUsage.dproj      Project file (Win32 + Win64)
├── MainFormU.pas / .dfm          Demo form with four buttons
└── README.md                     This file
```

## Full docs

<https://exewatch.com/ui/docs#breadcrumbs>
