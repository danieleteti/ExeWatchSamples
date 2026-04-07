{ *******************************************************************************
  ExeWatch SDK DLL

  Wraps the ExeWatch Delphi SDK into a standard Windows DLL with flat
  stdcall exports. This allows usage from any Delphi version (including
  Delphi 7) or any language that can call Windows DLLs.

  Compile with: dcc32 ExeWatchSDKv1DLL.dpr  (32-bit)
                dcc64 ExeWatchSDKv1DLL.dpr  (64-bit)

  Copyright (c) 2026 - bit Time Professionals
******************************************************************************* }

library ExeWatchSDKv1DLL;

uses
  System.SysUtils,
  Windows,
  ExeWatchSDKv1 in '..\ExeWatchSDKv1.pas',
  ExeWatchSDKv1DLL.Bridge in 'ExeWatchSDKv1DLL.Bridge.pas';

exports
  // Lifecycle
  ew_Initialize,
  ew_InitializeEx,
  ew_Shutdown,
  ew_Flush,
  ew_GetVersion,
  ew_GetLastError,
  ew_GetABIVersion,

  // Logging
  ew_Log,
  ew_Debug,
  ew_Info,
  ew_Warning,
  ew_Error,
  ew_Fatal,
  ew_ErrorWithStackTrace,

  // Breadcrumbs
  ew_AddBreadcrumb,
  ew_ClearBreadcrumbs,

  // Timing
  ew_StartTiming,
  ew_EndTiming,
  ew_EndLastTiming,
  ew_CancelTiming,
  ew_IsTimingActive,

  // Metrics
  ew_IncrementCounter,
  ew_RecordGauge,

  // User Identity
  ew_SetUser,
  ew_ClearUser,

  // Tags
  ew_SetTag,
  ew_RemoveTag,
  ew_ClearTags,

  // Customer ID
  ew_SetCustomerId,
  ew_GetCustomerId,

  // Device Info
  ew_SendDeviceInfo,
  ew_SetCustomDeviceInfo,
  ew_SendCustomDeviceInfo,

  // Config
  ew_SetEnabled,
  ew_GetEnabled,
  ew_GetPendingCount,

  // Callbacks
  ew_SetOnError,
  ew_SetOnLogsSent,
  ew_SetOnDeviceInfoSent;

procedure DLLMain(Reason: Integer);
begin
  case Reason of
    DLL_PROCESS_DETACH:
      DLLCleanup;
  end;
end;

begin
  DllProc := @DLLMain;
end.
