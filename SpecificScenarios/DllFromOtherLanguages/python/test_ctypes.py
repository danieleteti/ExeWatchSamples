"""ExeWatch DLL — Python smoke test via ctypes.

Proves the DLL is callable from a completely non-Embarcadero runtime
(CPython) and validates all five Windows ABI axes:

  1. Calling convention    — WinDLL = stdcall
  2. Name decoration       — GetProcAddress with plain names
  3. String marshalling    — c_wchar_p = UTF-16 LE wchar_t*
  4. Struct packing        — TEWDLLConfig with _pack_=1
  5. Callback ABI          — WINFUNCTYPE = stdcall fn pointer

Usage:

    1. Replace EXEWATCH_API_KEY with your own key from https://exewatch.com
       (the Hobby plan is free and takes 30 seconds to sign up for).
    2. Run:   python test_ctypes.py
    3. Open the ExeWatch dashboard — the "Hello from Python ctypes"
       Info and the Error with breadcrumbs should appear within a few
       seconds.

Note: if you are building a real Python application you are probably
better off with the native ExeWatch Python SDK (pip install exewatch) —
it gives you the full API without the marshalling boilerplate below.
This script exists to prove the DLL works from any language, so you
can use it as a template for Rust, Go, VBA, or any other FFI-capable
runtime you have around.

Exit code 0 = all axes pass. Non-zero = ABI issue — inspect output.
"""
from __future__ import annotations

import ctypes
import os
import sys
import time
from ctypes import (
    POINTER, Structure, WINFUNCTYPE, WinDLL,
    byref, c_double, c_int, c_wchar_p, create_unicode_buffer, sizeof,
)

# -----------------------------------------------------------------------------
# CONFIGURE ME — replace with your real key from https://exewatch.com
# The platform for your application must be set to "Windows" (ew_win_ prefix).
# -----------------------------------------------------------------------------
EXEWATCH_API_KEY = 'ew_win_xxxxxx_USE_YOUR_OWN_KEY'
CUSTOMER_ID      = 'PythonCtypesSmokeTest'
# -----------------------------------------------------------------------------

DLL_NAME = 'ExeWatchSDKv1DLL_x64.dll' if sys.maxsize > 2**32 else 'ExeWatchSDKv1DLL.dll'

# Multi-location search so this script runs unchanged in three layouts:
#   1. ZIP extracted from exewatch.com: DLL is two levels up (samples/python -> ExeWatchSDKv1DLL/)
#   2. exewatchsamples repo:            DLL is in ../../../DLLSDKCommons/
#   3. Side-by-side:                    DLL next to this script
SEARCH_PATHS = [
    os.path.dirname(os.path.abspath(__file__)),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'DLLSDKCommons'),
]


def locate_dll() -> str:
    for d in SEARCH_PATHS:
        candidate = os.path.normpath(os.path.join(d, DLL_NAME))
        if os.path.isfile(candidate):
            return candidate
    raise FileNotFoundError(
        f'Could not find {DLL_NAME}. Looked in:\n  ' + '\n  '.join(SEARCH_PATHS)
    )


BOOL = c_int  # Win32 BOOL is always 32-bit


class TEWDLLConfig(Structure):
    # pack(1) — MUST match #pragma pack(push, 1) in ExeWatchSDKv1.h
    _pack_ = 1
    _fields_ = [
        ('StructSize',               c_int),
        ('ApiKey',                   c_wchar_p),
        ('CustomerId',               c_wchar_p),
        ('AppVersion',               c_wchar_p),
        ('StoragePath',              c_wchar_p),
        ('BufferSize',               c_int),
        ('FlushIntervalMs',          c_int),
        ('RetryIntervalMs',          c_int),
        ('SampleRate',               c_double),
        ('GaugeSamplingIntervalSec', c_int),
        ('MaxPendingAgeDays',        c_int),
        ('AnonymizeDeviceId',        BOOL),
    ]


TEWErrorCallback = WINFUNCTYPE(None, c_wchar_p)  # __stdcall on Windows


def main() -> int:
    dll_path = locate_dll()
    print(f'Loading {dll_path}')
    dll = WinDLL(dll_path)
    print(f'Loaded. handle=0x{dll._handle:X}')

    # --- Signatures (ctypes does NOT read them from the C header) ---
    sigs = [
        ('ew_GetABIVersion',    [],                                        c_int),
        ('ew_GetVersion',       [c_wchar_p, c_int],                        c_int),
        ('ew_Initialize',       [c_wchar_p, c_wchar_p, c_wchar_p],         c_int),
        ('ew_InitializeEx',     [POINTER(TEWDLLConfig)],                   c_int),
        ('ew_Info',             [c_wchar_p, c_wchar_p],                    c_int),
        ('ew_Warning',          [c_wchar_p, c_wchar_p],                    c_int),
        ('ew_Error',            [c_wchar_p, c_wchar_p],                    c_int),
        ('ew_AddBreadcrumb',    [c_int, c_wchar_p, c_wchar_p, c_wchar_p],  c_int),
        ('ew_SetTag',           [c_wchar_p, c_wchar_p],                    c_int),
        ('ew_IncrementCounter', [c_wchar_p, c_double, c_wchar_p],          c_int),
        ('ew_GetPendingCount',  [],                                        c_int),
        ('ew_Flush',            [],                                        c_int),
        ('ew_Shutdown',         [],                                        c_int),
    ]
    for name, argtypes, restype in sigs:
        fn = getattr(dll, name)
        fn.argtypes = argtypes
        fn.restype = restype

    dll.ew_SetOnError.argtypes = [TEWErrorCallback]
    dll.ew_SetOnError.restype = c_int

    # --- Axes 1 + 2: stdcall + undecorated names ---
    abi = dll.ew_GetABIVersion()
    print(f'[axis 1+2] ew_GetABIVersion() = {abi}')
    assert abi == 2, f'ABI mismatch: header expects 2, DLL reports {abi}'

    # --- Axis 3: wchar_t* round-trip ---
    buf = create_unicode_buffer(128)
    rc = dll.ew_GetVersion(buf, 128)
    print(f'[axis 3]   ew_GetVersion rc={rc}, version={buf.value!r}')
    assert rc == 0 and buf.value

    # --- Axis 5: callback registration ---
    errors: list[str] = []

    def on_error(msg: str) -> None:
        print(f'[callback] DLL pushed error: {msg!r}')
        errors.append(msg or '')

    err_cb = TEWErrorCallback(on_error)  # keep a reference alive
    rc = dll.ew_SetOnError(err_cb)
    print(f'[axis 5]   ew_SetOnError rc={rc}')
    assert rc == 0

    # --- Axis 4: struct packing ---
    print(f'[axis 4]   sizeof(TEWDLLConfig) = {sizeof(TEWDLLConfig)} bytes')

    cfg = TEWDLLConfig()
    cfg.StructSize = sizeof(TEWDLLConfig)
    cfg.ApiKey = EXEWATCH_API_KEY
    cfg.CustomerId = CUSTOMER_ID
    cfg.AppVersion = '0.1.0'
    cfg.SampleRate = 1.0
    cfg.MaxPendingAgeDays = -1

    rc = dll.ew_InitializeEx(byref(cfg))
    print(f'[axis 4]   ew_InitializeEx rc={rc}')
    # rc == -6 (EW_ERR_VERSION_MISMATCH) = struct layout is wrong (pack mismatch).
    # rc == 0 or -2 (ALREADY_INITIALIZED) = struct was read correctly.
    assert rc in (0, -2), f'InitializeEx rc={rc} (likely struct packing)'

    # --- Exercise the API surface ---
    EW_BT_CLICK = 0
    dll.ew_SetTag('environment', 'abi-test')
    dll.ew_AddBreadcrumb(EW_BT_CLICK, 'ui', 'Clicked smoke-test button', None)
    dll.ew_Info('Hello from Python ctypes', 'smoke')
    dll.ew_Warning('Warning from Python ctypes', 'smoke')
    dll.ew_Error('Error from Python ctypes (breadcrumbs should attach)', 'smoke')
    dll.ew_IncrementCounter('python_ctypes_ticks', 1.0, 'test')

    time.sleep(0.2)
    dll.ew_Flush()
    pending = dll.ew_GetPendingCount()
    print(f'           ew_GetPendingCount = {pending}')

    dll.ew_Shutdown()

    if errors:
        print(f'\n[info] DLL reported {len(errors)} error(s) via callback '
              f'(e.g. "bad api key" if you didn\'t change the placeholder).')

    print('\nAll five ABI axes validated — Python ctypes <-> ExeWatch DLL works.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
