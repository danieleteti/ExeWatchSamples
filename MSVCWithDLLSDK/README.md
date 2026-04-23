# MSVC — ExeWatch DLL SDK Quickstart (Microsoft Visual C++)

Console sample that shows how to use the ExeWatch DLL from a pure MSVC
toolchain (`cl.exe`). No Embarcadero runtime, no import library, no
linker gymnastics: the DLL is loaded at runtime via `LoadLibrary` +
`GetProcAddress`.

## What the sample does

A one-shot console app that walks through the common SDK surface:

1. Loads `ExeWatchSDKv1DLL_x64.dll` dynamically.
2. Registers an SDK error callback (internal SDK errors -> stderr).
3. `ew_Initialize` with an API key, customer id, app version.
4. Sets user identity + global tags (attached to every subsequent event).
5. Adds breadcrumbs and emits an `Info` log.
6. Wraps a simulated operation with `ew_StartTiming` / `ew_EndTiming`.
7. Records a counter + a gauge.
8. Emits an `Error` log — the breadcrumbs from step 5-7 auto-attach.
9. Flushes pending events and shuts the SDK down cleanly.

Everything surfaces in your ExeWatch dashboard within a few seconds.

## Prerequisites

- **Windows 10 / 11** (x64).
- **Visual Studio 2022** — **Build Tools** edition is enough (no IDE
  required). Install the "Desktop development with C++" workload so
  `cl.exe` is available.
- An ExeWatch API key. Sign up at <https://exewatch.com> — the Hobby
  plan is free.

## Quick start

1. Open `main.cpp` and replace `EXEWATCH_API_KEY` with your real key
   (it starts with `ew_win_`).
2. Build and run:

   **Easy path** — double-click or run `run_msvc.cmd`. It finds
   `vcvars64.bat` automatically, compiles, and runs.

   **Manual path** — open an "x64 Native Tools Command Prompt for
   VS 2022", then:

   ```cmd
   cd path\to\exewatchsamples\MSVCWithDLLSDK
   cl /EHsc /W4 /nologo /I..\DLLSDKCommons main.cpp ^
      ..\DLLSDKCommons\ExeWatchSDKv1.dynload.c
   main.exe
   ```

3. Check the ExeWatch dashboard. You should see an `Info`, a `Warning`,
   and an `Error` within a few seconds. The `Error` carries the
   breadcrumbs that were added before it.

## Project layout

    MSVCWithDLLSDK/
      main.cpp             the sample
      run_msvc.cmd         build + run helper
      README.md            this file
    ..\DLLSDKCommons\     shared across all DLL samples
      ExeWatchSDKv1DLL.dll           32-bit runtime
      ExeWatchSDKv1DLL_x64.dll       64-bit runtime  <- loaded by this sample
      ExeWatchSDKv1.h                dual-mode C/C++ header
      ExeWatchSDKv1.dynload.c        loader (LoadLibrary + GetProcAddress)

The sample picks up the header via `/I..\DLLSDKCommons` and compiles
`ExeWatchSDKv1.dynload.c` in the same command. There is no copy of the
header or loader in this folder.

## How the dynamic loading works

```cpp
#define EW_DYNAMIC_LOAD
#include "ExeWatchSDKv1.h"
...
if (ew_LoadSDK() != EW_OK) { /* DLL missing -> show friendly error */ }
ew_Initialize(...);
```

- `#define EW_DYNAMIC_LOAD` before the header turns every `ew_*` into a
  function-pointer variable.
- `ExeWatchSDKv1.dynload.c` defines those variables and implements
  `ew_LoadSDK()` / `ew_LoadSDKFromPath()` / `ew_UnloadSDK()` with
  `LoadLibraryW` + `GetProcAddress`.
- `ew_LoadSDK()` uses the Windows DLL search path (exe dir, System32,
  PATH). This sample then falls back to `ew_LoadSDKFromPath(L"..\\DLLSDKCommons\\ExeWatchSDKv1DLL_x64.dll")`
  so a fresh clone runs out-of-box without copying the DLL around.

## Why dynamic loading?

- **No import-library mismatch**: `.lib` (MSVC COFF) and `.a` (MinGW /
  bcc64x) are not interchangeable. Dynamic loading sidesteps the whole
  problem.
- **Portable across compilers**: MSVC, MinGW, Clang on Windows, and
  C++Builder all eat the same two files (`.h` + `.dynload.c`).
- **Graceful missing-DLL behaviour**: your exe still starts and can
  surface a clean error to the user.

## Works with other Windows C/C++ toolchains too

The DLL exposes the lowest-common-denominator Windows ABI
(`extern "C"` + `__stdcall` + `wchar_t*` + `#pragma pack(1)`). Any
compiler that follows that ABI can consume it:

- **Embarcadero C++Builder** — see [`../CPPBuilderWithDLLSDK/`](../CPPBuilderWithDLLSDK/)
- **MinGW-w64 gcc/g++**
- **Clang on Windows**
- **Rust** via `extern "stdcall"`
- **Go** via `syscall.NewLazyDLL`
- **C#** via `[DllImport(CallingConvention = StdCall)]`
- **Python** via `ctypes.WinDLL` — see [`../SpecificScenarios/DllFromOtherLanguages/python/`](../SpecificScenarios/DllFromOtherLanguages/python/)

## Full docs

- Dashboard: <https://exewatch.com>
- Docs: <https://exewatch.com/ui/docs>
