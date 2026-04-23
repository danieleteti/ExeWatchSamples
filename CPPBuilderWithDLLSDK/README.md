# C++Builder VCL Sample — ExeWatch DLL SDK (dynamic loading)

Minimal C++Builder 12/13 VCL sample that talks to ExeWatch through
`ExeWatchSDKv1DLL.dll` using runtime dynamic loading (`LoadLibrary` +
`GetProcAddress`). No import library required — the same source compiles
under bcc32, bcc64 and bcc64x without fighting the linker.

## Project layout

    CPPBuilderWithDLLSDK/
      EWCppBuilderDLL.cbproj         project file
      EWCppBuilderDLL.cpp            WinMain
      MainFormU.h/.cpp/.dfm          main form
      EWCppBuilderDLLPCH1.h          PCH
    ..\DLLSDKCommons/                shared across all DLL samples
      ExeWatchSDKv1.h                dual-mode C/C++ header
      ExeWatchSDKv1.dynload.c        loader (`ew_LoadSDK`, `ew_UnloadSDK`)
      ExeWatchSDKv1DLL.dll           32-bit runtime
      ExeWatchSDKv1DLL_x64.dll       64-bit runtime

The `.cbproj` pulls the header via `IncludePath=..\DLLSDKCommons` and
includes `..\DLLSDKCommons\ExeWatchSDKv1.dynload.c` as a project unit — so
there is exactly one copy of the DLL SDK C header in the repo.

## Run

1. Open `EWCppBuilderDLL.cbproj` in C++Builder 12 or 13.
2. In `MainFormU.cpp` replace `EXEWATCH_API_KEY` with your own key from
   https://exewatch.com.
3. Build and run (F9). The DLL must sit next to the executable — the
   easiest way is to copy it once from `..\DLLSDKCommons\`:

       copy ..\DLLSDKCommons\ExeWatchSDKv1DLL_x64.dll Win64\Debug\
       copy ..\DLLSDKCommons\ExeWatchSDKv1DLL.dll     Win32\Debug\

   (For the Win64x/clang target use `Win64x\Debug\`.)

4. Click the buttons and watch the events appear in the ExeWatch
   dashboard.

## How the dynamic loading works

`MainFormU.cpp` does:

```cpp
#define EW_DYNAMIC_LOAD
#include "ExeWatchSDKv1.h"
...
if (ew_LoadSDK() != EW_OK) { /* DLL missing -> show friendly error */ }
ew_Initialize(EXEWATCH_API_KEY, L"Sample C++ Customer", L"");
```

- `#define EW_DYNAMIC_LOAD` before the header turns every `ew_*` into a
  function-pointer variable.
- `ExeWatchSDKv1.dynload.c` defines those variables and implements
  `ew_LoadSDK()` / `ew_UnloadSDK()` with `LoadLibraryW` +
  `GetProcAddress`.
- `ew_IsSDKLoaded()` lets you gate shutdown (see `FormDestroy`).

Because loading is runtime, the executable starts even when the DLL is
missing — useful for graceful degradation.

## Why bother with dynamic loading?

- **No import library mismatch**: `.lib` (MSVC/OMF COFF) and `.a` (MinGW
  / bcc64x) are not interchangeable. Dynamic loading sidesteps the
  problem entirely.
- **Same code across compilers**: the `ExeWatchSDKv1.h` +
  `ExeWatchSDKv1.dynload.c` pair works under C++Builder, MSVC, MinGW,
  Clang, Rust (via `libloading`), Python ctypes…
- **Graceful missing-DLL behaviour**: the app keeps running; you decide
  how to surface the error.

## Full docs

- Dashboard: https://exewatch.com
- Docs: https://exewatch.com/ui/docs
