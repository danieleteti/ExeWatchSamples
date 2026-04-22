/* *****************************************************************************
   ExeWatch SDK DLL -- C/C++ Header

   Import header for ExeWatchSDKv1DLL.dll.
   Compatible with C++Builder, MSVC, MinGW, Clang, and any C/C++ compiler
   on Windows.

   All functions use stdcall calling convention and PWideChar (wchar_t*) strings.

   ============================================================================
   Two loading modes -- pick one and stick with it across your project
   ============================================================================

   1) RUNTIME DYNAMIC LOADING (recommended -- no linker fuss, works with every
      compiler, graceful degradation if the DLL is missing):

          #define EW_DYNAMIC_LOAD
          #include "ExeWatchSDKv1.h"

          // Add ExeWatchSDKv1.dynload.c to your project (shipped next to
          // this header). It defines the function-pointer variables and
          // implements ew_LoadSDK() / ew_UnloadSDK() with LoadLibrary +
          // GetProcAddress.

          // At startup, once:
          if (ew_LoadSDK() != EW_OK) { ... handle error ... }

          // From then on, call ew_* as usual -- they are function pointers
          // resolved at runtime, but the call-site syntax is identical to
          // the static case:
          ew_Initialize(L"ew_win_xxx", L"ACME", L"1.0.0");
          ew_Info(L"Application started", L"startup");

          // Before exit:
          ew_UnloadSDK();

   2) STATIC IMPORT (you know your toolchain accepts the bundled import
      library -- e.g. old C++Builder bcc32 with ExeWatchSDKv1DLL.lib):

          #include "ExeWatchSDKv1.h"

          // The linker resolves ew_* against the import library; the DLL
          // must be present at process start-up (no graceful degradation).

   The dynamic-loading mode is strongly preferred -- it sidesteps every
   import-library format mismatch (.lib vs .a vs COFF vs OMF) and makes the
   same source compile on every Windows C/C++ toolchain.

   SDK Version: 0.20.0 | ABI Version: 2

   Copyright (c) 2026 - bit Time Professionals
***************************************************************************** */

#ifndef EXEWATCH_SDK_V1_H
#define EXEWATCH_SDK_V1_H

#include <windows.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --- Error codes --- */
#define EW_OK                       0
#define EW_ERR_NOT_INITIALIZED     -1
#define EW_ERR_ALREADY_INITIALIZED -2
#define EW_ERR_INVALID_PARAM       -3
#define EW_ERR_EXCEPTION           -4
#define EW_ERR_BUFFER_TOO_SMALL    -5
#define EW_ERR_VERSION_MISMATCH    -6

/* --- Log levels --- */
#define EW_LOG_DEBUG    0
#define EW_LOG_INFO     1
#define EW_LOG_WARNING  2
#define EW_LOG_ERROR    3
#define EW_LOG_FATAL    4

/* --- Breadcrumb types --- */
#define EW_BT_CLICK        0
#define EW_BT_NAVIGATION   1
#define EW_BT_HTTP         2
#define EW_BT_CONSOLE      3
#define EW_BT_CUSTOM       4
#define EW_BT_ERROR        5
#define EW_BT_QUERY        6
#define EW_BT_TRANSACTION  7
#define EW_BT_USER         8
#define EW_BT_SYSTEM       9
#define EW_BT_FILE        10
#define EW_BT_STATE       11
#define EW_BT_FORM        12
#define EW_BT_CONFIG      13
#define EW_BT_MESSAGE     14
#define EW_BT_DEBUG       15

/* --- ABI version (must match DLL) --- */
#define EW_IMPORT_ABI_VERSION 2

/* --- DLL name --- */
#ifdef _WIN64
  #define EXEWATCH_DLL_NAME L"ExeWatchSDKv1DLL_x64.dll"
#else
  #define EXEWATCH_DLL_NAME L"ExeWatchSDKv1DLL.dll"
#endif

/* --- Config record (must match DLL layout exactly) --- */
#pragma pack(push, 1)
typedef struct {
    int         StructSize;
    const wchar_t* ApiKey;
    const wchar_t* CustomerId;
    const wchar_t* AppVersion;
    const wchar_t* StoragePath;
    int         BufferSize;
    int         FlushIntervalMs;
    int         RetryIntervalMs;
    double      SampleRate;
    int         GaugeSamplingIntervalSec;
    int         MaxPendingAgeDays;
    BOOL        AnonymizeDeviceId;
} TEWDLLConfig;
#pragma pack(pop)

/* --- Callback types --- */
typedef void (__stdcall *TEWErrorCallback)(const wchar_t* ErrorMsg);
typedef void (__stdcall *TEWLogsSentCallback)(int AcceptedCount, int RejectedCount);
typedef void (__stdcall *TEWDeviceInfoSentCallback)(BOOL Success, const wchar_t* ErrorMsg);

/* --- Helper: initialize config with defaults --- */
static inline void EWConfigInit(TEWDLLConfig* config) {
    memset(config, 0, sizeof(TEWDLLConfig));
    config->StructSize = sizeof(TEWDLLConfig);
    config->MaxPendingAgeDays = -1;  /* -1 = DLL uses default (7 days) */
}

/* ==========================================================================
   Function types -- used by both static and dynamic loading modes.
   ========================================================================== */

typedef int  (__stdcall *PFN_ew_Initialize)       (const wchar_t* ApiKey, const wchar_t* CustomerId, const wchar_t* AppVersion);
typedef int  (__stdcall *PFN_ew_InitializeEx)     (TEWDLLConfig* Config);
typedef int  (__stdcall *PFN_ew_Shutdown)         (void);
typedef int  (__stdcall *PFN_ew_Flush)            (void);
typedef int  (__stdcall *PFN_ew_GetVersion)       (wchar_t* Buffer, int BufLen);
typedef int  (__stdcall *PFN_ew_GetLastError)     (wchar_t* Buffer, int BufLen);
typedef int  (__stdcall *PFN_ew_GetABIVersion)    (void);

typedef int  (__stdcall *PFN_ew_Log)              (int Level, const wchar_t* Msg, const wchar_t* Tag, const wchar_t* ExtraDataJson);
typedef int  (__stdcall *PFN_ew_LogLevel)         (const wchar_t* Msg, const wchar_t* Tag);  /* Debug/Info/Warning/Error/Fatal */
/* Per-function aliases — all identical signature to PFN_ew_LogLevel,
   but named after each function so the loader's PFN_##name macro works. */
typedef PFN_ew_LogLevel PFN_ew_Debug;
typedef PFN_ew_LogLevel PFN_ew_Info;
typedef PFN_ew_LogLevel PFN_ew_Warning;
typedef PFN_ew_LogLevel PFN_ew_Error;
typedef PFN_ew_LogLevel PFN_ew_Fatal;
typedef int  (__stdcall *PFN_ew_ErrorWithStackTrace)(const wchar_t* Msg, const wchar_t* Tag, const wchar_t* StackTrace, const wchar_t* ExceptionClass);

typedef int  (__stdcall *PFN_ew_AddBreadcrumb)    (int BreadcrumbType, const wchar_t* Category, const wchar_t* Msg, const wchar_t* DataJson);
typedef int  (__stdcall *PFN_ew_ClearBreadcrumbs) (void);

typedef int  (__stdcall *PFN_ew_StartTiming)      (const wchar_t* Id, const wchar_t* Tag);
typedef int  (__stdcall *PFN_ew_EndTiming)        (const wchar_t* Id, double* ElapsedMs);
typedef int  (__stdcall *PFN_ew_EndLastTiming)    (double* ElapsedMs);
typedef int  (__stdcall *PFN_ew_CancelTiming)     (const wchar_t* Id);
typedef BOOL (__stdcall *PFN_ew_IsTimingActive)   (const wchar_t* Id);

typedef int  (__stdcall *PFN_ew_IncrementCounter) (const wchar_t* Name, double Value, const wchar_t* Tag);
typedef int  (__stdcall *PFN_ew_RecordGauge)      (const wchar_t* Name, double Value, const wchar_t* Tag);

typedef int  (__stdcall *PFN_ew_SetUser)          (const wchar_t* Id, const wchar_t* Email, const wchar_t* Name);
typedef int  (__stdcall *PFN_ew_ClearUser)        (void);

typedef int  (__stdcall *PFN_ew_SetTag)           (const wchar_t* Key, const wchar_t* Value);
typedef int  (__stdcall *PFN_ew_RemoveTag)        (const wchar_t* Key);
typedef int  (__stdcall *PFN_ew_ClearTags)        (void);

typedef int  (__stdcall *PFN_ew_SetCustomerId)    (const wchar_t* Id);
typedef int  (__stdcall *PFN_ew_GetCustomerId)    (wchar_t* Buffer, int BufLen);

typedef int  (__stdcall *PFN_ew_SendDeviceInfo)   (void);
typedef int  (__stdcall *PFN_ew_SetCustomDeviceInfo)(const wchar_t* Key, const wchar_t* Value);
typedef int  (__stdcall *PFN_ew_SendCustomDeviceInfo)(void);

typedef int  (__stdcall *PFN_ew_SetEnabled)       (BOOL Value);
typedef BOOL (__stdcall *PFN_ew_GetEnabled)       (void);
typedef int  (__stdcall *PFN_ew_GetPendingCount)  (void);

typedef int  (__stdcall *PFN_ew_SetOnError)       (TEWErrorCallback Callback);
typedef int  (__stdcall *PFN_ew_SetOnLogsSent)    (TEWLogsSentCallback Callback);
typedef int  (__stdcall *PFN_ew_SetOnDeviceInfoSent)(TEWDeviceInfoSentCallback Callback);

/* ==========================================================================
   Function declarations

   Two modes, controlled by EW_DYNAMIC_LOAD:

     - EW_DYNAMIC_LOAD defined:
           each name below is an extern function-POINTER variable,
           initially NULL. Call ew_LoadSDK() once at startup to have
           them resolved via GetProcAddress. Implementation lives in
           ExeWatchSDKv1.dynload.c (ship it alongside this header).

     - EW_DYNAMIC_LOAD not defined (default):
           each name below is a normal stdcall function declaration.
           The linker resolves them against the DLL's import library.
   ========================================================================== */

#ifdef EW_DYNAMIC_LOAD

/* Loader API -- only available in dynamic mode. */
int  ew_LoadSDK(void);                        /* LoadLibrary + resolve every pointer. Returns EW_OK or EW_ERR_*. */
int  ew_LoadSDKFromPath(const wchar_t* Path); /* Same, but loads the DLL from an explicit path (full or relative). */
void ew_UnloadSDK(void);                      /* FreeLibrary + null out every pointer. Safe to call multiple times. */
BOOL ew_IsSDKLoaded(void);                    /* TRUE once ew_LoadSDK has succeeded, FALSE before/after unload. */

/* Function-pointer variables -- defined in ExeWatchSDKv1.dynload.c. */
extern PFN_ew_Initialize           ew_Initialize;
extern PFN_ew_InitializeEx         ew_InitializeEx;
extern PFN_ew_Shutdown             ew_Shutdown;
extern PFN_ew_Flush                ew_Flush;
extern PFN_ew_GetVersion           ew_GetVersion;
extern PFN_ew_GetLastError         ew_GetLastError;
extern PFN_ew_GetABIVersion        ew_GetABIVersion;

extern PFN_ew_Log                  ew_Log;
extern PFN_ew_LogLevel             ew_Debug;
extern PFN_ew_LogLevel             ew_Info;
extern PFN_ew_LogLevel             ew_Warning;
extern PFN_ew_LogLevel             ew_Error;
extern PFN_ew_LogLevel             ew_Fatal;
extern PFN_ew_ErrorWithStackTrace  ew_ErrorWithStackTrace;

extern PFN_ew_AddBreadcrumb        ew_AddBreadcrumb;
extern PFN_ew_ClearBreadcrumbs     ew_ClearBreadcrumbs;

extern PFN_ew_StartTiming          ew_StartTiming;
extern PFN_ew_EndTiming            ew_EndTiming;
extern PFN_ew_EndLastTiming        ew_EndLastTiming;
extern PFN_ew_CancelTiming         ew_CancelTiming;
extern PFN_ew_IsTimingActive       ew_IsTimingActive;

extern PFN_ew_IncrementCounter     ew_IncrementCounter;
extern PFN_ew_RecordGauge          ew_RecordGauge;

extern PFN_ew_SetUser              ew_SetUser;
extern PFN_ew_ClearUser             ew_ClearUser;

extern PFN_ew_SetTag               ew_SetTag;
extern PFN_ew_RemoveTag            ew_RemoveTag;
extern PFN_ew_ClearTags            ew_ClearTags;

extern PFN_ew_SetCustomerId        ew_SetCustomerId;
extern PFN_ew_GetCustomerId        ew_GetCustomerId;

extern PFN_ew_SendDeviceInfo       ew_SendDeviceInfo;
extern PFN_ew_SetCustomDeviceInfo  ew_SetCustomDeviceInfo;
extern PFN_ew_SendCustomDeviceInfo ew_SendCustomDeviceInfo;

extern PFN_ew_SetEnabled           ew_SetEnabled;
extern PFN_ew_GetEnabled           ew_GetEnabled;
extern PFN_ew_GetPendingCount      ew_GetPendingCount;

extern PFN_ew_SetOnError           ew_SetOnError;
extern PFN_ew_SetOnLogsSent        ew_SetOnLogsSent;
extern PFN_ew_SetOnDeviceInfoSent  ew_SetOnDeviceInfoSent;

#else  /* static-import mode (legacy) */

/* Lifecycle */
int __stdcall ew_Initialize(const wchar_t* ApiKey, const wchar_t* CustomerId, const wchar_t* AppVersion);
int __stdcall ew_InitializeEx(TEWDLLConfig* Config);
int __stdcall ew_Shutdown(void);
int __stdcall ew_Flush(void);
int __stdcall ew_GetVersion(wchar_t* Buffer, int BufLen);
int __stdcall ew_GetLastError(wchar_t* Buffer, int BufLen);
int __stdcall ew_GetABIVersion(void);

/* Logging */
int __stdcall ew_Log(int Level, const wchar_t* Msg, const wchar_t* Tag, const wchar_t* ExtraDataJson);
int __stdcall ew_Debug(const wchar_t* Msg, const wchar_t* Tag);
int __stdcall ew_Info(const wchar_t* Msg, const wchar_t* Tag);
int __stdcall ew_Warning(const wchar_t* Msg, const wchar_t* Tag);
int __stdcall ew_Error(const wchar_t* Msg, const wchar_t* Tag);
int __stdcall ew_Fatal(const wchar_t* Msg, const wchar_t* Tag);
int __stdcall ew_ErrorWithStackTrace(const wchar_t* Msg, const wchar_t* Tag,
                                     const wchar_t* StackTrace, const wchar_t* ExceptionClass);

/* Breadcrumbs */
int __stdcall ew_AddBreadcrumb(int BreadcrumbType, const wchar_t* Category,
                               const wchar_t* Msg, const wchar_t* DataJson);
int __stdcall ew_ClearBreadcrumbs(void);

/* Timing */
int  __stdcall ew_StartTiming(const wchar_t* Id, const wchar_t* Tag);
int  __stdcall ew_EndTiming(const wchar_t* Id, double* ElapsedMs);
int  __stdcall ew_EndLastTiming(double* ElapsedMs);
int  __stdcall ew_CancelTiming(const wchar_t* Id);
BOOL __stdcall ew_IsTimingActive(const wchar_t* Id);

/* Metrics */
int __stdcall ew_IncrementCounter(const wchar_t* Name, double Value, const wchar_t* Tag);
int __stdcall ew_RecordGauge(const wchar_t* Name, double Value, const wchar_t* Tag);

/* User Identity */
int __stdcall ew_SetUser(const wchar_t* Id, const wchar_t* Email, const wchar_t* Name);
int __stdcall ew_ClearUser(void);

/* Tags */
int __stdcall ew_SetTag(const wchar_t* Key, const wchar_t* Value);
int __stdcall ew_RemoveTag(const wchar_t* Key);
int __stdcall ew_ClearTags(void);

/* Customer ID */
int __stdcall ew_SetCustomerId(const wchar_t* Id);
int __stdcall ew_GetCustomerId(wchar_t* Buffer, int BufLen);

/* Device Info */
int __stdcall ew_SendDeviceInfo(void);
int __stdcall ew_SetCustomDeviceInfo(const wchar_t* Key, const wchar_t* Value);
int __stdcall ew_SendCustomDeviceInfo(void);

/* Config */
int  __stdcall ew_SetEnabled(BOOL Value);
BOOL __stdcall ew_GetEnabled(void);
int  __stdcall ew_GetPendingCount(void);

/* Callbacks */
int __stdcall ew_SetOnError(TEWErrorCallback Callback);
int __stdcall ew_SetOnLogsSent(TEWLogsSentCallback Callback);
int __stdcall ew_SetOnDeviceInfoSent(TEWDeviceInfoSentCallback Callback);

#endif /* EW_DYNAMIC_LOAD */

#ifdef __cplusplus
}
#endif

#endif /* EXEWATCH_SDK_V1_H */
