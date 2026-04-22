// ExeWatch DLL — MSVC C++ smoke test via LoadLibrary + GetProcAddress.
//
// Proves the DLL works from a fully non-Embarcadero C++ toolchain
// (Microsoft Visual C++ / cl.exe). Validates all five Windows ABI
// axes. If this compiles with /W4 and exits 0, the DLL implements
// the plain Windows ABI — any other C/C++ compiler that follows the
// Windows calling convention (MinGW, Clang, etc.) will work too.
//
// Build and run:
//
//   1. Open a Developer Command Prompt for VS 2022 (x64 native).
//   2. cd to this folder.
//   3. cl /EHsc /W4 /nologo test_msvc.cpp
//   4. test_msvc.exe
//
// Or use the helper cmd script in this folder:
//
//   run_msvc.cmd
//
// which auto-activates vcvars64 and compiles + runs the test.
//
// ---------------------------------------------------------------------------
// CONFIGURE ME — replace with your real key from https://exewatch.com
// ---------------------------------------------------------------------------
#define EXEWATCH_API_KEY  L"ew_win_xxxxxx_USE_YOUR_OWN_KEY"
#define CUSTOMER_ID       L"MsvcSmokeTest"
// ---------------------------------------------------------------------------

#include <windows.h>
#include <cstdio>
#include <cstdlib>

// Struct + typedefs must match ExeWatchSDKv1.h exactly.

#pragma pack(push, 1)
struct TEWDLLConfig {
    int            StructSize;
    const wchar_t* ApiKey;
    const wchar_t* CustomerId;
    const wchar_t* AppVersion;
    const wchar_t* StoragePath;
    int            BufferSize;
    int            FlushIntervalMs;
    int            RetryIntervalMs;
    double         SampleRate;
    int            GaugeSamplingIntervalSec;
    int            MaxPendingAgeDays;
    BOOL           AnonymizeDeviceId;
};
#pragma pack(pop)

typedef void (__stdcall *TEWErrorCallback)(const wchar_t*);

typedef int (__stdcall *FnGetABIVersion)(void);
typedef int (__stdcall *FnGetVersion)(wchar_t*, int);
typedef int (__stdcall *FnInitializeEx)(TEWDLLConfig*);
typedef int (__stdcall *FnSetOnError)(TEWErrorCallback);
typedef int (__stdcall *FnInfo)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *FnWarning)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *FnError)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *FnAddBreadcrumb)(int, const wchar_t*, const wchar_t*, const wchar_t*);
typedef int (__stdcall *FnSetTag)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *FnIncrementCounter)(const wchar_t*, double, const wchar_t*);
typedef int (__stdcall *FnFlush)(void);
typedef int (__stdcall *FnGetPendingCount)(void);
typedef int (__stdcall *FnShutdown)(void);

static int g_error_cb_count = 0;

static void __stdcall on_error(const wchar_t* msg) {
    wprintf(L"[callback] DLL pushed error: %s\n", msg ? msg : L"(null)");
    g_error_cb_count++;
}

static void die(const char* what, DWORD code = 0) {
    fprintf(stderr, "FAIL: %s (GetLastError=%lu)\n", what, code ? code : GetLastError());
    ExitProcess(1);
}

template <typename T>
static T resolve(HMODULE h, const char* name) {
    FARPROC p = GetProcAddress(h, name);
    if (!p) die(name);
    return reinterpret_cast<T>(p);
}

// Try loading the DLL from a short list of candidate locations so this
// single source file works whether you build it inside the ZIP layout
// (samples/msvc/..) or in the exewatchsamples repo or side-by-side.
static HMODULE load_dll() {
    const wchar_t* candidates[] = {
        L"ExeWatchSDKv1DLL_x64.dll",
        L"..\\..\\ExeWatchSDKv1DLL_x64.dll",
        L"..\\..\\..\\DLLSDKCommons\\ExeWatchSDKv1DLL_x64.dll",
        L"..\\..\\..\\..\\SDK\\Delphi\\DLL\\ExeWatchSDKv1DLL_x64.dll",
    };
    for (const wchar_t* path : candidates) {
        HMODULE h = LoadLibraryW(path);
        if (h) {
            wprintf(L"Loaded %s (handle=%p)\n", path, (void*)h);
            return h;
        }
    }
    die("LoadLibrary ExeWatchSDKv1DLL_x64.dll (none of the candidate paths worked)");
    return nullptr;
}

int wmain() {
    HMODULE h = load_dll();

    // --- Axis 2: plain names via GetProcAddress (no mangling) ---
    auto fnGetABI = resolve<FnGetABIVersion>(h, "ew_GetABIVersion");
    auto fnGetVer = resolve<FnGetVersion>(h, "ew_GetVersion");
    auto fnInitEx = resolve<FnInitializeEx>(h, "ew_InitializeEx");
    auto fnSetErr = resolve<FnSetOnError>(h, "ew_SetOnError");
    auto fnInfo   = resolve<FnInfo>(h, "ew_Info");
    auto fnWarn   = resolve<FnWarning>(h, "ew_Warning");
    auto fnError  = resolve<FnError>(h, "ew_Error");
    auto fnCrumb  = resolve<FnAddBreadcrumb>(h, "ew_AddBreadcrumb");
    auto fnTag    = resolve<FnSetTag>(h, "ew_SetTag");
    auto fnInc    = resolve<FnIncrementCounter>(h, "ew_IncrementCounter");
    auto fnFlush  = resolve<FnFlush>(h, "ew_Flush");
    auto fnPend   = resolve<FnGetPendingCount>(h, "ew_GetPendingCount");
    auto fnShut   = resolve<FnShutdown>(h, "ew_Shutdown");
    wprintf(L"[axis 2]   all 13 exports resolved with plain names\n");

    // --- Axis 1: stdcall — wrong convention = stack imbalance or garbage ---
    int abi = fnGetABI();
    wprintf(L"[axis 1]   ew_GetABIVersion() = %d\n", abi);
    if (abi != 2) die("ABI mismatch (header expects 2)");

    // --- Axis 3: wchar_t* out-buffer roundtrip ---
    wchar_t verBuf[128] = {};
    int rc = fnGetVer(verBuf, 128);
    wprintf(L"[axis 3]   ew_GetVersion rc=%d, version='%s'\n", rc, verBuf);
    if (rc != 0) die("GetVersion rc != 0");

    // --- Axis 5: callback registration ---
    rc = fnSetErr(&on_error);
    wprintf(L"[axis 5]   ew_SetOnError rc=%d\n", rc);
    if (rc != 0) die("SetOnError rc != 0");

    // --- Axis 4: struct packing — pack(1) must match the DLL side ---
    wprintf(L"[axis 4]   sizeof(TEWDLLConfig) = %zu bytes\n", sizeof(TEWDLLConfig));

    TEWDLLConfig cfg = {};
    cfg.StructSize              = (int)sizeof(TEWDLLConfig);
    cfg.ApiKey                  = EXEWATCH_API_KEY;
    cfg.CustomerId              = CUSTOMER_ID;
    cfg.AppVersion              = L"0.1.0";
    cfg.StoragePath             = nullptr;
    cfg.SampleRate              = 1.0;
    cfg.MaxPendingAgeDays       = -1;
    cfg.AnonymizeDeviceId       = FALSE;

    rc = fnInitEx(&cfg);
    wprintf(L"[axis 4]   ew_InitializeEx rc=%d\n", rc);
    if (rc != 0 && rc != -2) die("InitializeEx rc not in {0,-2}");

    // --- Exercise the real API surface ---
    const int EW_BT_CLICK = 0;

    (void)fnTag(L"environment", L"abi-test");
    (void)fnCrumb(EW_BT_CLICK, L"ui", L"Clicked smoke-test button", nullptr);
    (void)fnInfo(L"Hello from MSVC cl.exe", L"smoke");
    (void)fnWarn(L"Warning from MSVC cl.exe", L"smoke");
    (void)fnError(L"Error from MSVC (breadcrumbs should attach)", L"smoke");
    (void)fnInc(L"msvc_smoke_test_ticks", 1.0, L"test");

    Sleep(200);
    (void)fnFlush();
    int pending = fnPend();
    wprintf(L"           ew_GetPendingCount = %d\n", pending);

    (void)fnShut();
    FreeLibrary(h);

    if (g_error_cb_count)
        wprintf(L"[info]     DLL invoked error callback %d time(s) "
                L"(expected if you didn't change EXEWATCH_API_KEY).\n",
                g_error_cb_count);

    wprintf(L"\nAll five ABI axes validated - MSVC <-> ExeWatch DLL works.\n");
    return 0;
}
