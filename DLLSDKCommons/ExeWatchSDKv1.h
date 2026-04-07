/* *****************************************************************************
   ExeWatch SDK DLL — C/C++ Header

   Import header for ExeWatchSDKv1DLL.dll.
   Compatible with C++Builder, MSVC, MinGW, and any C/C++ compiler on Windows.

   All functions use stdcall calling convention and PWideChar (wchar_t*) strings.

   Usage:
     #include "ExeWatchSDKv1.h"

   Link against ExeWatchSDKv1DLL.lib (import library) or load dynamically
   with LoadLibrary/GetProcAddress.

   SDK Version: 0.20.0 | ABI Version: 2

   Copyright (c) 2026 - bit Time Professionals
***************************************************************************** */

#ifndef EXEWATCH_SDK_V1_H
#define EXEWATCH_SDK_V1_H

#include <windows.h>

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
   Function declarations
   ========================================================================== */

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

#ifdef __cplusplus
}
#endif

#endif /* EXEWATCH_SDK_V1_H */
