/* *****************************************************************************
   ExeWatch SDK DLL -- runtime dynamic-loading implementation

   Ship this file alongside ExeWatchSDKv1.h in your project. Compile it as
   part of your target; it has no dependencies beyond the Windows SDK and
   can be compiled as C or C++.

   Usage (in any number of .c/.cpp files in your project):

       #define EW_DYNAMIC_LOAD
       #include "ExeWatchSDKv1.h"

       // Call once at startup:
       if (ew_LoadSDK() != EW_OK) { ... }

       // Call ew_* functions normally:
       ew_Initialize(L"ew_win_xxx", L"ACME", L"1.0.0");
       ew_Info(L"hello", L"main");

       // Call once at shutdown:
       ew_UnloadSDK();

   All ew_* symbols below are real variables, initially NULL.
   ew_LoadSDK() resolves them with GetProcAddress and only returns EW_OK
   after every required entry point has been found.

   SDK Version: 0.20.0 | ABI Version: 2

   Copyright (c) 2026 - bit Time Professionals
***************************************************************************** */

#define EW_DYNAMIC_LOAD
#include "ExeWatchSDKv1.h"

/* -----------------------------------------------------------------------------
   Function-pointer variables. Extern-declared in the header.
   ----------------------------------------------------------------------------- */

PFN_ew_Initialize           ew_Initialize           = NULL;
PFN_ew_InitializeEx         ew_InitializeEx         = NULL;
PFN_ew_Shutdown             ew_Shutdown             = NULL;
PFN_ew_Flush                ew_Flush                = NULL;
PFN_ew_GetVersion           ew_GetVersion           = NULL;
PFN_ew_GetLastError         ew_GetLastError         = NULL;
PFN_ew_GetABIVersion        ew_GetABIVersion        = NULL;

PFN_ew_Log                  ew_Log                  = NULL;
PFN_ew_LogLevel             ew_Debug                = NULL;
PFN_ew_LogLevel             ew_Info                 = NULL;
PFN_ew_LogLevel             ew_Warning              = NULL;
PFN_ew_LogLevel             ew_Error                = NULL;
PFN_ew_LogLevel             ew_Fatal                = NULL;
PFN_ew_ErrorWithStackTrace  ew_ErrorWithStackTrace  = NULL;

PFN_ew_AddBreadcrumb        ew_AddBreadcrumb        = NULL;
PFN_ew_ClearBreadcrumbs     ew_ClearBreadcrumbs     = NULL;

PFN_ew_StartTiming          ew_StartTiming          = NULL;
PFN_ew_EndTiming            ew_EndTiming            = NULL;
PFN_ew_EndLastTiming        ew_EndLastTiming        = NULL;
PFN_ew_CancelTiming         ew_CancelTiming         = NULL;
PFN_ew_IsTimingActive       ew_IsTimingActive       = NULL;

PFN_ew_IncrementCounter     ew_IncrementCounter     = NULL;
PFN_ew_RecordGauge          ew_RecordGauge          = NULL;

PFN_ew_SetUser              ew_SetUser              = NULL;
PFN_ew_ClearUser            ew_ClearUser            = NULL;

PFN_ew_SetTag               ew_SetTag               = NULL;
PFN_ew_RemoveTag            ew_RemoveTag            = NULL;
PFN_ew_ClearTags            ew_ClearTags            = NULL;

PFN_ew_SetCustomerId        ew_SetCustomerId        = NULL;
PFN_ew_GetCustomerId        ew_GetCustomerId        = NULL;

PFN_ew_SendDeviceInfo       ew_SendDeviceInfo       = NULL;
PFN_ew_SetCustomDeviceInfo  ew_SetCustomDeviceInfo  = NULL;
PFN_ew_SendCustomDeviceInfo ew_SendCustomDeviceInfo = NULL;

PFN_ew_SetEnabled           ew_SetEnabled           = NULL;
PFN_ew_GetEnabled           ew_GetEnabled           = NULL;
PFN_ew_GetPendingCount      ew_GetPendingCount      = NULL;

PFN_ew_SetOnError           ew_SetOnError           = NULL;
PFN_ew_SetOnLogsSent        ew_SetOnLogsSent        = NULL;
PFN_ew_SetOnDeviceInfoSent  ew_SetOnDeviceInfoSent  = NULL;

/* -----------------------------------------------------------------------------
   Loader state
   ----------------------------------------------------------------------------- */

static HMODULE g_ewDll = NULL;

/* Helper: resolve one symbol. Returns FALSE if GetProcAddress failed. */
#define EW_BIND(name) \
    do { \
        name = (PFN_##name)(void*)GetProcAddress(g_ewDll, #name); \
        if (!name) goto resolve_failed; \
    } while (0)

static int EwResolveAll(void) {
    EW_BIND(ew_Initialize);
    EW_BIND(ew_InitializeEx);
    EW_BIND(ew_Shutdown);
    EW_BIND(ew_Flush);
    EW_BIND(ew_GetVersion);
    EW_BIND(ew_GetLastError);
    EW_BIND(ew_GetABIVersion);

    EW_BIND(ew_Log);
    EW_BIND(ew_Debug);
    EW_BIND(ew_Info);
    EW_BIND(ew_Warning);
    EW_BIND(ew_Error);
    EW_BIND(ew_Fatal);
    EW_BIND(ew_ErrorWithStackTrace);

    EW_BIND(ew_AddBreadcrumb);
    EW_BIND(ew_ClearBreadcrumbs);

    EW_BIND(ew_StartTiming);
    EW_BIND(ew_EndTiming);
    EW_BIND(ew_EndLastTiming);
    EW_BIND(ew_CancelTiming);
    EW_BIND(ew_IsTimingActive);

    EW_BIND(ew_IncrementCounter);
    EW_BIND(ew_RecordGauge);

    EW_BIND(ew_SetUser);
    EW_BIND(ew_ClearUser);

    EW_BIND(ew_SetTag);
    EW_BIND(ew_RemoveTag);
    EW_BIND(ew_ClearTags);

    EW_BIND(ew_SetCustomerId);
    EW_BIND(ew_GetCustomerId);

    EW_BIND(ew_SendDeviceInfo);
    EW_BIND(ew_SetCustomDeviceInfo);
    EW_BIND(ew_SendCustomDeviceInfo);

    EW_BIND(ew_SetEnabled);
    EW_BIND(ew_GetEnabled);
    EW_BIND(ew_GetPendingCount);

    EW_BIND(ew_SetOnError);
    EW_BIND(ew_SetOnLogsSent);
    EW_BIND(ew_SetOnDeviceInfoSent);

    /* ABI sanity check -- make sure the header we compiled against matches
       what the DLL actually exports. */
    if (ew_GetABIVersion() != EW_IMPORT_ABI_VERSION)
        return EW_ERR_VERSION_MISMATCH;

    return EW_OK;

resolve_failed:
    return EW_ERR_VERSION_MISMATCH;
}

#undef EW_BIND

/* -----------------------------------------------------------------------------
   Public loader API
   ----------------------------------------------------------------------------- */

int ew_LoadSDKFromPath(const wchar_t* Path) {
    int rc;
    if (g_ewDll)
        return EW_OK;  /* idempotent */
    if (!Path)
        return EW_ERR_INVALID_PARAM;

    g_ewDll = LoadLibraryW(Path);
    if (!g_ewDll)
        return EW_ERR_NOT_INITIALIZED;

    rc = EwResolveAll();
    if (rc != EW_OK) {
        FreeLibrary(g_ewDll);
        g_ewDll = NULL;
    }
    return rc;
}

int ew_LoadSDK(void) {
    return ew_LoadSDKFromPath(EXEWATCH_DLL_NAME);
}

void ew_UnloadSDK(void) {
    if (g_ewDll) {
        FreeLibrary(g_ewDll);
        g_ewDll = NULL;
    }

    ew_Initialize = NULL;           ew_InitializeEx = NULL;
    ew_Shutdown = NULL;             ew_Flush = NULL;
    ew_GetVersion = NULL;           ew_GetLastError = NULL;
    ew_GetABIVersion = NULL;

    ew_Log = NULL;                  ew_Debug = NULL;
    ew_Info = NULL;                 ew_Warning = NULL;
    ew_Error = NULL;                ew_Fatal = NULL;
    ew_ErrorWithStackTrace = NULL;

    ew_AddBreadcrumb = NULL;        ew_ClearBreadcrumbs = NULL;

    ew_StartTiming = NULL;          ew_EndTiming = NULL;
    ew_EndLastTiming = NULL;        ew_CancelTiming = NULL;
    ew_IsTimingActive = NULL;

    ew_IncrementCounter = NULL;     ew_RecordGauge = NULL;

    ew_SetUser = NULL;              ew_ClearUser = NULL;

    ew_SetTag = NULL;               ew_RemoveTag = NULL;
    ew_ClearTags = NULL;

    ew_SetCustomerId = NULL;        ew_GetCustomerId = NULL;

    ew_SendDeviceInfo = NULL;       ew_SetCustomDeviceInfo = NULL;
    ew_SendCustomDeviceInfo = NULL;

    ew_SetEnabled = NULL;           ew_GetEnabled = NULL;
    ew_GetPendingCount = NULL;

    ew_SetOnError = NULL;           ew_SetOnLogsSent = NULL;
    ew_SetOnDeviceInfoSent = NULL;
}

BOOL ew_IsSDKLoaded(void) {
    return g_ewDll != NULL;
}
