# DLL from Other Languages

> **Question:** *We have the ExeWatch DLL SDK — can I really call it from languages that aren't Delphi or C++Builder? How do I prove it works with my own toolchain?*

Short answer: **yes, from any language that can call a Windows DLL**. The DLL exports an `extern "C"` + `__stdcall` + `wchar_t*` + `#pragma pack(1)` surface — the lowest common denominator of the Windows ABI. This folder contains runnable smoke tests that prove it from runtimes completely outside the Embarcadero toolchain.

## What's in this folder

| Folder | Runtime | Setup cost | What it proves |
|--------|---------|------------|----------------|
| [`python/`](python/) | CPython 3.7+ via `ctypes` | `python` on PATH | Pure-stdlib runtime with no Embarcadero footprint at all. |

Each sub-folder has its own README with build instructions, configuration, and expected output.

> Looking for the **Microsoft Visual C++** smoke test? It lives at the repo
> root under [`../../MSVCWithDLLSDK/`](../../MSVCWithDLLSDK/) — same idea,
> moved out of `SpecificScenarios/` because it is a fully-fledged sample
> on its own.

## The five ABI axes each sample validates

Every function call touches at least one of these. The two scripts label them `[axis N]` in their output so you can tell at a glance which dimension was exercised.

| Axis | Broken looks like | Test |
|------|-------------------|------|
| 1. Calling convention (stdcall) | Stack imbalance, crash, garbage return | `ew_GetABIVersion() == 2` |
| 2. Name decoration (undecorated) | `GetProcAddress` returns NULL | `GetProcAddress("ew_Info")` resolves |
| 3. String marshalling (UTF-16 `wchar_t*`) | Mojibake in the dashboard | `ew_GetVersion` fills a `wchar_t[]` with `"0.21.0"` |
| 4. Struct packing (`#pragma pack(1)`) | `ew_InitializeEx` returns `EW_ERR_VERSION_MISMATCH` (-6) | `sizeof(TEWDLLConfig) == 68` and `InitializeEx` returns 0 |
| 5. Callback ABI (`__stdcall` fn pointer) | Stack crash when the DLL fires the callback | `ew_SetOnError(on_error)` + trigger an error |

If all five pass on both MSVC and Python, the DLL is genuinely language-agnostic.

## Are you really going to consume the DLL from Python?

Probably not. If you are writing a real Python application, use the native ExeWatch Python SDK (`pip install exewatch`) — see <https://exewatch.com/ui/docs#python-sdk>. This ctypes sample is here as a reference for:

- Porting the import pattern to other FFI-capable languages (Rust, Go, Julia, VBA, etc.).
- Edge cases where your Python tool must share the same DLL as your Delphi / C++ executables.

## Where is the DLL?

The samples look for `ExeWatchSDKv1DLL_x64.dll` (or `_x86`) in the `../../../DLLSDKCommons/` folder inside this repository. They also fall back to script-local and a few other layouts — you can drop the scripts into the DLL SDK ZIP downloaded from <https://exewatch.com> and they will work there too.

## Full docs

<https://exewatch.com/ui/docs>
