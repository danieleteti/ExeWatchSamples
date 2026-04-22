# MSVC — ExeWatch DLL from Visual C++

This folder shows how to call the ExeWatch DLL from Microsoft Visual C++ (`cl.exe`). It is the "truth test" for cross-language compatibility: if MSVC can load and call the DLL without any Embarcadero runtime, the DLL implements the plain Windows ABI and every other Windows-FFI-capable language/toolchain will work too.

## Prerequisites

- **Windows** 10 / 11.
- **Visual Studio 2022** — the **Build Tools** edition is enough (no IDE required). Community is also fine. Install the "Desktop development with C++" workload so you get `cl.exe`.
- An ExeWatch API key. Sign up at <https://exewatch.com> — Hobby plan is free.

## Quick start

1. Open `test_msvc.cpp` and replace `EXEWATCH_API_KEY` with your real key (starts with `ew_win_`).
2. Build + run:

   **Easy path** — double-click or execute `run_msvc.cmd`. It finds `vcvars64.bat` automatically, compiles, and runs.

   **Manual path** — open a "x64 Native Tools Command Prompt for VS 2022", then:

   ```cmd
   cd path\to\samples\msvc
   cl /EHsc /W4 /nologo test_msvc.cpp
   test_msvc.exe
   ```

3. Check the ExeWatch dashboard. You should see an Info, a Warning, and an Error within a few seconds. The Error carries the breadcrumbs that were added before it.

## What the script demonstrates

Every branch is labelled with `[axis N]` in the output so you can tell at a glance which ABI dimension was validated:

| Axis | What is tested |
|------|----------------|
| 1. Calling convention   | `__stdcall` on every function pointer. Wrong convention = stack imbalance, crash or garbage return. |
| 2. Name decoration      | `GetProcAddress("ew_Info")` with plain names (no `_ew_Info@8`, no C++ mangling). Fails instantly if Delphi were exporting decorated symbols. |
| 3. String marshalling   | `wchar_t*` buffers both directions. `ew_GetVersion` fills a caller-allocated buffer. |
| 4. Struct packing       | `#pragma pack(push, 1)` around `TEWDLLConfig`. If packing mismatches, `ew_InitializeEx` returns `EW_ERR_VERSION_MISMATCH` (-6). |
| 5. Callback ABI         | `__stdcall` function pointer passed to `ew_SetOnError`. The DLL invokes it from its own threads; wrong convention = crash when the first error bubbles up. |

## How it loads the DLL

The sample uses `LoadLibraryW` + `GetProcAddress`. Advantages:

- No import library needed. Embarcadero's `.lib` is OMF/COFF-style and doesn't always link cleanly against MSVC; regenerating with `LIB /DEF:... /MACHINE:X64` works but adds a build step. `LoadLibrary` sidesteps the issue entirely.
- Works with any Windows C/C++ compiler (MSVC, MinGW, Clang on Windows, Cygwin).
- Lets you distribute a single .exe that picks up the DLL at runtime from a variety of locations (this sample tries four candidate paths before giving up).

If you prefer implicit linking, you can still generate an MSVC-compatible import library from the DLL:

```cmd
dumpbin /exports ExeWatchSDKv1DLL_x64.dll > exports.txt
REM manually extract the names into an ewsdk.def file, then:
lib /DEF:ewsdk.def /MACHINE:X64 /OUT:ExeWatchSDKv1DLL_x64_msvc.lib
cl /EHsc test.cpp ExeWatchSDKv1DLL_x64_msvc.lib
```

## Expected output (valid API key)

```
Loaded ExeWatchSDKv1DLL_x64.dll (handle=...)
[axis 2]   all 13 exports resolved with plain names
[axis 1]   ew_GetABIVersion() = 2
[axis 3]   ew_GetVersion rc=0, version='0.21.0'
[axis 5]   ew_SetOnError rc=0
[axis 4]   sizeof(TEWDLLConfig) = 68 bytes
[axis 4]   ew_InitializeEx rc=0
           ew_GetPendingCount = 7

All five ABI axes validated - MSVC <-> ExeWatch DLL works.
```

## Does it also work with MinGW / Clang / C++Builder?

Yes. The DLL's export layer is deliberately the lowest-common-denominator Windows ABI (`extern "C"` + `__stdcall` + `wchar_t*` + `#pragma pack(1)` structs). Any compiler that respects that ABI can consume the DLL. `cl.exe` is the strictest common case, so if MSVC works, everything else does too.

We have verified:

- **Microsoft Visual C++** (cl.exe v14.44, /W4 = zero warnings) ← this sample
- **Embarcadero C++Builder** ← see `../CPPBuilderWithDLLSDK/` in the samples repo
- **Python ctypes** ← see `../python/` in this ZIP

Expected to work (not in the default test matrix): **MinGW-w64 gcc/g++**, **Clang on Windows**, **LLVM-MinGW**, **Rust `extern "stdcall"`**, **Go `syscall.NewLazyDLL`**, **C# `DllImport`**, **VBA `Declare Function`**, **AutoIt `DllCall`**.
