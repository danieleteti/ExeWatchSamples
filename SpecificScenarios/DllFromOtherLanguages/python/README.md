# Python — ExeWatch DLL via ctypes

This folder proves that the ExeWatch DLL can be called from a completely non-Embarcadero runtime (CPython) using only the `ctypes` module from the standard library.

## Do you actually need this?

**Probably not.** If you are building a real Python application, use the native ExeWatch Python SDK:

```bash
pip install exewatch
```

The native SDK has zero dependencies, a richer API, and doesn't require you to marshal every string and struct by hand. See <https://exewatch.com/ui/docs#python-sdk>.

This ctypes sample exists for two specific cases:

1. **You already have a Delphi DLL distribution pipeline** and you want to keep Python uniform with the rest of your stack (all consumers going through the same DLL).
2. **You are porting this pattern to another FFI-capable language** (Rust, Go, VBA, Julia, Lua-LuaJIT, …). This script is the cleanest ctypes-like reference you can copy and translate.

## Prerequisites

- Python **3.7+** (64-bit recommended — the 64-bit DLL is loaded by default on 64-bit Python).
- Windows. The DLL is Windows-only; for Linux/macOS use the native Python SDK (or the Delphi SDK source compiled for Linux).
- An ExeWatch API key. Sign up at <https://exewatch.com> — Hobby plan is free.

## Quick start

1. Open `test_ctypes.py` and replace `EXEWATCH_API_KEY` with your key (must start with `ew_win_`).
2. Run:

   ```bash
   python test_ctypes.py
   ```

3. Check the ExeWatch dashboard — you should see an Info, a Warning, and an Error (the Error carries the breadcrumbs accumulated before it).

## What the script demonstrates

The script walks through all five Windows ABI axes explicitly. Each is labelled `[axis N]` in the output:

| Axis | What is tested |
|------|----------------|
| 1. Calling convention   | `WinDLL` = stdcall. If it were wrong, `ew_GetABIVersion` would crash or return garbage. |
| 2. Name decoration      | `GetProcAddress("ew_Info")` with plain names. If the DLL mangled them (e.g. `_ew_Info@8`), ctypes would fail to resolve. |
| 3. String marshalling   | `c_wchar_p` = UTF-16 LE `wchar_t*`. `ew_GetVersion` roundtrips `'0.21.0'` through a buffer. |
| 4. Struct packing       | `TEWDLLConfig` with `_pack_=1`. If packing mismatches, `ew_InitializeEx` returns `EW_ERR_VERSION_MISMATCH` (-6). |
| 5. Callback ABI         | `WINFUNCTYPE` = stdcall callback. `ew_SetOnError` registers a Python function as the DLL's error sink. |

If all five pass, the DLL is genuinely language-agnostic — any language with a competent Windows FFI can call it.

## Expected output (with a valid key)

```
Loading .../ExeWatchSDKv1DLL_x64.dll
Loaded. handle=0x...
[axis 1+2] ew_GetABIVersion() = 2
[axis 3]   ew_GetVersion rc=0, version='0.21.0'
[axis 5]   ew_SetOnError rc=0
[axis 4]   sizeof(TEWDLLConfig) = 68 bytes
[axis 4]   ew_InitializeEx rc=0
           ew_GetPendingCount = 4
All five ABI axes validated — Python ctypes <-> ExeWatch DLL works.
```

## Troubleshooting

- **`OSError: [WinError 126] module not found`** → wrong bitness: 32-bit Python must load `ExeWatchSDKv1DLL.dll`, 64-bit Python must load `ExeWatchSDKv1DLL_x64.dll`. The script auto-selects, but make sure the right DLL is present in one of the `SEARCH_PATHS`.
- **`ew_InitializeEx rc=-6`** → `EW_ERR_VERSION_MISMATCH`, means either the `StructSize` field is wrong or `_pack_=1` is missing from the `Structure` subclass. Double-check the class definition.
- **Callback fires with "invalid API key"** → expected if you didn't change `EXEWATCH_API_KEY`. The ABI test still passes in that case — the DLL just rejects the data server-side.
