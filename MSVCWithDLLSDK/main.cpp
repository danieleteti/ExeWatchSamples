// ExeWatch DLL SDK - MSVC (Microsoft Visual C++) Quickstart
//
// A realistic console sample that exercises every common feature of the
// ExeWatch DLL SDK from a pure-MSVC toolchain (no Embarcadero runtime).
//
// Dynamic loading:
//   We include `ExeWatchSDKv1.h` with `EW_DYNAMIC_LOAD` defined, so every
//   `ew_*` symbol becomes a function-pointer variable. The pointers are
//   defined + resolved by `ExeWatchSDKv1.dynload.c`, which is compiled
//   together with this source (see run_msvc.cmd). No import library is
//   involved -- the same code compiles under cl.exe, clang, MinGW, and
//   bcc64x without touching the linker.
//
// Build + run:
//   run_msvc.cmd       (picks up vcvars64 automatically)
//
// Or manually, from an "x64 Native Tools Command Prompt for VS 2022":
//   cl /EHsc /W4 /nologo /I..\DLLSDKCommons main.cpp ^
//      ..\DLLSDKCommons\ExeWatchSDKv1.dynload.c
//   main.exe
//
// Configure your API key below, then run. Data appears in the ExeWatch
// dashboard within a few seconds.

#define EW_DYNAMIC_LOAD
#include "ExeWatchSDKv1.h"

#include <windows.h>
#include <cstdio>

// ---------------------------------------------------------------------------
// CONFIGURE ME -- replace with your own API key from https://exewatch.com
// ---------------------------------------------------------------------------
#define EXEWATCH_API_KEY  L"ew_win_xxxxxx_USE_YOUR_OWN_KEY"
#define CUSTOMER_ID       L"MsvcSampleApp"
#define APP_VERSION       L"1.0.0"
// ---------------------------------------------------------------------------

// SDK may push internal errors (network, disk, queue) through this callback.
// It fires on the shipper thread -- keep it short and thread-safe.
static void __stdcall on_sdk_error(const wchar_t* msg)
{
    fwprintf(stderr, L"[ExeWatch] %ls\n", msg ? msg : L"(null)");
}

int wmain()
{
    if (wcscmp(EXEWATCH_API_KEY, L"ew_win_xxxxxx_USE_YOUR_OWN_KEY") == 0)
    {
        fwprintf(stderr,
            L"API key not configured.\n"
            L"Open main.cpp and replace EXEWATCH_API_KEY with your real key\n"
            L"from https://exewatch.com, then rebuild.\n");
        return 1;
    }

    // 1. Load the DLL at runtime (LoadLibrary + GetProcAddress under the hood).
    //    ew_LoadSDK() uses the Windows DLL search path (exe dir, System32, PATH).
    //    In this repo the DLL lives in ..\DLLSDKCommons\, so we fall back to
    //    ew_LoadSDKFromPath() if the default lookup misses.
    int rc = ew_LoadSDK();
    if (rc != EW_OK)
        rc = ew_LoadSDKFromPath(L"..\\DLLSDKCommons\\ExeWatchSDKv1DLL_x64.dll");
    if (rc != EW_OK)
    {
        fwprintf(stderr,
            L"Cannot load ExeWatchSDKv1DLL_x64.dll (rc=%d).\n"
            L"Copy it next to main.exe or run from a folder where\n"
            L"..\\DLLSDKCommons\\ExeWatchSDKv1DLL_x64.dll exists.\n", rc);
        return 1;
    }

    ew_SetOnError(on_sdk_error);

    // 2. Initialize with your API key + customer id + app version.
    rc = ew_Initialize(EXEWATCH_API_KEY, CUSTOMER_ID, APP_VERSION);
    if (rc != EW_OK)
    {
        wchar_t err[1024] = {};
        ew_GetLastError(err, 1024);
        fwprintf(stderr, L"Init failed: %ls (rc=%d)\n", err, rc);
        ew_UnloadSDK();
        return 1;
    }

    wchar_t ver[64] = {};
    if (ew_GetVersion(ver, 64) == EW_OK)
        wprintf(L"ExeWatch SDK %ls initialised.\n", ver);

    // 3. User identity + global tags (attached to every subsequent event).
    ew_SetUser(L"alice@example.com", L"alice@example.com", L"Alice Example");
    ew_SetTag(L"environment", L"dev");
    ew_SetTag(L"build",       L"msvc-x64");

    // 4. Breadcrumbs + informational log.
    //    Breadcrumbs are a FIFO of up to 20 per thread and are auto-attached
    //    to any Error/Fatal log emitted afterwards (see step 7).
    ew_AddBreadcrumb(EW_BT_NAVIGATION, L"nav", L"Opened main screen",   NULL);
    ew_Info(L"Sample app started", L"startup");

    // 5. Timing around a simulated operation (shows up as Avg/Min/Max/P95
    //    in the dashboard's Timings tab).
    ew_AddBreadcrumb(EW_BT_CLICK, L"ui", L"Clicked 'Run report'", NULL);
    ew_StartTiming(L"generate_report", L"reports");
    Sleep(150); // pretend work
    double elapsed_ms = 0.0;
    ew_EndTiming(L"generate_report", &elapsed_ms);
    wprintf(L"Report generated in %.1f ms\n", elapsed_ms);

    // 6. Metrics: counter (monotonic) + gauge (point-in-time).
    ew_IncrementCounter(L"reports.generated", 1.0, L"reports");
    ew_RecordGauge     (L"queue.depth",       3.0, L"reports");

    // 7. A handled error. The three breadcrumbs above are automatically
    //    attached to this log event and shown next to it in the dashboard.
    ew_AddBreadcrumb(EW_BT_CLICK, L"ui", L"Clicked 'Save'", NULL);
    ew_Error(L"Validation failed: missing customer field", L"reports");

    // 8. Make sure everything is shipped before we exit.
    //    ew_WaitForSending(sec) flushes the in-memory buffer to disk and
    //    then blocks until the shipper thread has drained the queue (or the
    //    timeout elapses). Returns the number of events still pending on
    //    return -- 0 means everything made it to the server.
    int remaining = ew_WaitForSending(15);
    if (remaining > 0)
        fwprintf(stderr,
                 L"Warning: %d event(s) still queued after 15 s -- they will\n"
                 L"be retried on next run (ExeWatch queues persist to disk).\n",
                 remaining);
    else
        wprintf(L"All events shipped.\n");

    ew_Shutdown();
    ew_UnloadSDK();

    wprintf(L"Done. Check your dashboard at https://exewatch.com\n");
    return 0;
}
