{ *******************************************************************************
  ExeWatch SDK DLL Import Unit

  Delphi 5+ compatible import unit for ExeWatchSDKv1DLL.dll.
  Use this unit in your application to call the ExeWatch SDK via DLL.

  Unit name uses no dots for Delphi 5/6/7 compatibility.

  Loading modes (choose ONE):
  - Static linking (default): DLL must be present at application startup.
  - Dynamic loading: Define EW_DYNAMIC_LOAD before this unit in your project.
    Allows graceful degradation if the DLL is not present.

  String handling:
    All DLL functions use PWideChar (Unicode strings).
    - Delphi 2009+: string = UnicodeString, so PWideChar(string) works directly.
    - Delphi 5-2007: string = AnsiString, use the EWStr() helper or cast
      manually: PWideChar(WideString('my text'))
    - Convenience wrappers (EWInfo, EWDebug, etc.) handle conversion automatically.

  Copyright (c) 2026 - bit Time Professionals
******************************************************************************* }

unit ExeWatchSDKv1Imports;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

// Detect Unicode Delphi (2009+ has UNICODE defined)
{$IFDEF UNICODE}
  {$DEFINE EW_UNICODE_DELPHI}
{$ENDIF}

interface

uses
  Windows;

const
  // --- Error codes ---
  EW_OK                      =  0;
  EW_ERR_NOT_INITIALIZED     = -1;
  EW_ERR_ALREADY_INITIALIZED = -2;
  EW_ERR_INVALID_PARAM       = -3;
  EW_ERR_EXCEPTION           = -4;
  EW_ERR_BUFFER_TOO_SMALL    = -5;
  EW_ERR_VERSION_MISMATCH    = -6;

  // --- Log levels (matches TEWLogLevel ordinals) ---
  EW_LOG_DEBUG   = 0;
  EW_LOG_INFO    = 1;
  EW_LOG_WARNING = 2;
  EW_LOG_ERROR   = 3;
  EW_LOG_FATAL   = 4;

  // --- Breadcrumb types (matches TBreadcrumbType ordinals) ---
  EW_BT_CLICK       = 0;
  EW_BT_NAVIGATION  = 1;
  EW_BT_HTTP        = 2;
  EW_BT_CONSOLE     = 3;
  EW_BT_CUSTOM      = 4;
  EW_BT_ERROR       = 5;
  EW_BT_QUERY       = 6;
  EW_BT_TRANSACTION = 7;
  EW_BT_USER        = 8;
  EW_BT_SYSTEM      = 9;
  EW_BT_FILE        = 10;
  EW_BT_STATE       = 11;
  EW_BT_FORM        = 12;
  EW_BT_CONFIG      = 13;
  EW_BT_MESSAGE     = 14;
  EW_BT_DEBUG       = 15;

  // --- DLL name ---
  {$IFDEF WIN64}
  EXEWATCH_DLL = 'ExeWatchSDKv1DLL_x64.dll';
  {$ELSE}
  EXEWATCH_DLL = 'ExeWatchSDKv1DLL.dll';
  {$ENDIF}

  // --- Import unit ABI version ---
  // IMPORTANT: This MUST match EW_DLL_ABI_VERSION in the DLL.
  // Increment BOTH whenever the DLL interface changes (new exports,
  // changed signatures, changed record layouts, etc.)
  EW_IMPORT_ABI_VERSION = 2;

type
  // --- Config record (must match DLL exactly) ---
  PEWDLLConfig = ^TEWDLLConfig;
  TEWDLLConfig = packed record
    StructSize: Integer;
    ApiKey: PWideChar;
    CustomerId: PWideChar;
    AppVersion: PWideChar;
    StoragePath: PWideChar;
    BufferSize: Integer;
    FlushIntervalMs: Integer;
    RetryIntervalMs: Integer;
    SampleRate: Double;
    GaugeSamplingIntervalSec: Integer;
    MaxPendingAgeDays: Integer;
    AnonymizeDeviceId: LongBool;
  end;

  // --- Callback types ---
  TEWErrorCallback = procedure(ErrorMsg: PWideChar); stdcall;
  TEWLogsSentCallback = procedure(AcceptedCount, RejectedCount: Integer); stdcall;
  TEWDeviceInfoSentCallback = procedure(Success: LongBool; ErrorMsg: PWideChar); stdcall;

  // --- String type alias for cross-version compatibility ---
  // Use EWString for variables that hold strings passed to ew_* functions.
  // In Delphi 2009+, this is UnicodeString (= string). PWideChar(EWString) works.
  // In Delphi 5-2007, this is WideString. PWideChar(EWString) also works.
  {$IFDEF EW_UNICODE_DELPHI}
  EWString = string;  // UnicodeString in Delphi 2009+
  {$ELSE}
  EWString = WideString;  // WideString in Delphi 5-2007
  {$ENDIF}

// --- Helper: initialize config with defaults ---
procedure EWConfigInit(var Config: TEWDLLConfig);

// --- Helper: get last error as WideString ---
function EWGetLastErrorStr: WideString;

// --- String conversion helper ---
// Converts a string to PWideChar-compatible EWString.
// In Delphi 2009+ this is a no-op (string is already UnicodeString).
// In Delphi 5-2007 this converts AnsiString to WideString.
function EWStr(const S: string): EWString;

// --- Convenience wrappers (accept string, handle PWideChar conversion) ---
// These make it easy to call ew_* functions without manual PWideChar casts.
function EWInitialize(const AApiKey, ACustomerId: string; const AAppVersion: string = ''): Integer;
function EWLog(ALevel: Integer; const AMsg: string; const ATag: string = 'main'; const AExtraDataJson: string = ''): Integer;
function EWDebug(const AMsg: string; const ATag: string = 'main'): Integer;
function EWInfo(const AMsg: string; const ATag: string = 'main'): Integer;
function EWWarning(const AMsg: string; const ATag: string = 'main'): Integer;
function EWError(const AMsg: string; const ATag: string = 'main'): Integer;
function EWFatal(const AMsg: string; const ATag: string = 'main'): Integer;
function EWErrorWithStackTrace(const AMsg: string; const ATag: string;
  const AStackTrace: string; const AExceptionClass: string = ''): Integer;
function EWAddBreadcrumb(ABreadcrumbType: Integer; const ACategory, AMsg: string; const ADataJson: string = ''): Integer;
function EWStartTiming(const AId: string; const ATag: string = ''): Integer;
function EWEndTiming(const AId: string; out AElapsedMs: Double): Integer;
function EWSetUser(const AId: string; const AEmail: string = ''; const AName: string = ''): Integer;
function EWSetTag(const AKey, AValue: string): Integer;
function EWRemoveTag(const AKey: string): Integer;
function EWSetCustomerId(const AId: string): Integer;
function EWSetCustomDeviceInfo(const AKey, AValue: string): Integer;
function EWIncrementCounter(const AName: string; AValue: Double = 1.0; const ATag: string = ''): Integer;
function EWRecordGauge(const AName: string; AValue: Double; const ATag: string = ''): Integer;

// --- ABI version check ---
// Returns EW_OK if DLL and import unit are compatible, EW_ERR_VERSION_MISMATCH otherwise.
// Called automatically by EWInitialize. Call manually if using ew_Initialize directly.
function EWCheckABIVersion: Integer;

{$IFNDEF EW_DYNAMIC_LOAD}
// ==========================================================================
// STATIC LINKING (default)
// The DLL must be present at application startup.
// ==========================================================================

// Lifecycle
function ew_Initialize(ApiKey, CustomerId, AppVersion: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_InitializeEx(Config: PEWDLLConfig): Integer; stdcall; external EXEWATCH_DLL;
function ew_Shutdown: Integer; stdcall; external EXEWATCH_DLL;
function ew_Flush: Integer; stdcall; external EXEWATCH_DLL;
function ew_GetVersion(Buffer: PWideChar; BufLen: Integer): Integer; stdcall; external EXEWATCH_DLL;
function ew_GetLastError(Buffer: PWideChar; BufLen: Integer): Integer; stdcall; external EXEWATCH_DLL;
function ew_GetABIVersion: Integer; stdcall; external EXEWATCH_DLL;

// Logging
function ew_Log(Level: Integer; Msg, Tag, ExtraDataJson: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_Debug(Msg, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_Info(Msg, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_Warning(Msg, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_Error(Msg, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_Fatal(Msg, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_ErrorWithStackTrace(Msg, Tag, StackTrace, ExceptionClass: PWideChar): Integer; stdcall; external EXEWATCH_DLL;

// Breadcrumbs
function ew_AddBreadcrumb(BreadcrumbType: Integer; Category, Msg, DataJson: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_ClearBreadcrumbs: Integer; stdcall; external EXEWATCH_DLL;

// Timing
function ew_StartTiming(Id, Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_EndTiming(Id: PWideChar; out ElapsedMs: Double): Integer; stdcall; external EXEWATCH_DLL;
function ew_EndLastTiming(out ElapsedMs: Double): Integer; stdcall; external EXEWATCH_DLL;
function ew_CancelTiming(Id: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_IsTimingActive(Id: PWideChar): LongBool; stdcall; external EXEWATCH_DLL;

// Metrics
function ew_IncrementCounter(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_RecordGauge(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall; external EXEWATCH_DLL;

// User Identity
function ew_SetUser(Id, Email, Name: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_ClearUser: Integer; stdcall; external EXEWATCH_DLL;

// Tags
function ew_SetTag(Key, Value: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_RemoveTag(Key: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_ClearTags: Integer; stdcall; external EXEWATCH_DLL;

// Customer ID
function ew_SetCustomerId(Id: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_GetCustomerId(Buffer: PWideChar; BufLen: Integer): Integer; stdcall; external EXEWATCH_DLL;

// Device Info
function ew_SendDeviceInfo: Integer; stdcall; external EXEWATCH_DLL;
function ew_SetCustomDeviceInfo(Key, Value: PWideChar): Integer; stdcall; external EXEWATCH_DLL;
function ew_SendCustomDeviceInfo: Integer; stdcall; external EXEWATCH_DLL;

// Config
function ew_SetEnabled(Value: LongBool): Integer; stdcall; external EXEWATCH_DLL;
function ew_GetEnabled: LongBool; stdcall; external EXEWATCH_DLL;
function ew_GetPendingCount: Integer; stdcall; external EXEWATCH_DLL;

// Callbacks
function ew_SetOnError(Callback: TEWErrorCallback): Integer; stdcall; external EXEWATCH_DLL;
function ew_SetOnLogsSent(Callback: TEWLogsSentCallback): Integer; stdcall; external EXEWATCH_DLL;
function ew_SetOnDeviceInfoSent(Callback: TEWDeviceInfoSentCallback): Integer; stdcall; external EXEWATCH_DLL;

{$ELSE}
// ==========================================================================
// DYNAMIC LOADING
// Define EW_DYNAMIC_LOAD to use LoadLibrary/GetProcAddress.
// Call EWLoadDLL before using any ew_* function.
// ==========================================================================

type
  // Lifecycle
  Tew_Initialize = function(ApiKey, CustomerId, AppVersion: PWideChar): Integer; stdcall;
  Tew_InitializeEx = function(Config: PEWDLLConfig): Integer; stdcall;
  Tew_Shutdown = function: Integer; stdcall;
  Tew_Flush = function: Integer; stdcall;
  Tew_GetVersion = function(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
  Tew_GetLastError = function(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
  Tew_GetABIVersion = function: Integer; stdcall;
  // Logging
  Tew_Log = function(Level: Integer; Msg, Tag, ExtraDataJson: PWideChar): Integer; stdcall;
  Tew_LogShortcut = function(Msg, Tag: PWideChar): Integer; stdcall;
  Tew_ErrorWithStackTrace = function(Msg, Tag, StackTrace, ExceptionClass: PWideChar): Integer; stdcall;
  // Breadcrumbs
  Tew_AddBreadcrumb = function(BreadcrumbType: Integer; Category, Msg, DataJson: PWideChar): Integer; stdcall;
  Tew_ClearBreadcrumbs = function: Integer; stdcall;
  // Timing
  Tew_StartTiming = function(Id, Tag: PWideChar): Integer; stdcall;
  Tew_EndTiming = function(Id: PWideChar; out ElapsedMs: Double): Integer; stdcall;
  Tew_EndLastTiming = function(out ElapsedMs: Double): Integer; stdcall;
  Tew_CancelTiming = function(Id: PWideChar): Integer; stdcall;
  Tew_IsTimingActive = function(Id: PWideChar): LongBool; stdcall;
  // Metrics
  Tew_IncrementCounter = function(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;
  Tew_RecordGauge = function(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;
  // User
  Tew_SetUser = function(Id, Email, Name: PWideChar): Integer; stdcall;
  Tew_ClearUser = function: Integer; stdcall;
  // Tags
  Tew_SetTag = function(Key, Value: PWideChar): Integer; stdcall;
  Tew_RemoveTag = function(Key: PWideChar): Integer; stdcall;
  Tew_ClearTags = function: Integer; stdcall;
  // Customer
  Tew_SetCustomerId = function(Id: PWideChar): Integer; stdcall;
  Tew_GetCustomerId = function(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
  // Device
  Tew_SendDeviceInfo = function: Integer; stdcall;
  Tew_SetCustomDeviceInfo = function(Key, Value: PWideChar): Integer; stdcall;
  Tew_SendCustomDeviceInfo = function: Integer; stdcall;
  // Config
  Tew_SetEnabled = function(Value: LongBool): Integer; stdcall;
  Tew_GetEnabled = function: LongBool; stdcall;
  Tew_GetPendingCount = function: Integer; stdcall;
  // Callbacks
  Tew_SetOnError = function(Callback: TEWErrorCallback): Integer; stdcall;
  Tew_SetOnLogsSent = function(Callback: TEWLogsSentCallback): Integer; stdcall;
  Tew_SetOnDeviceInfoSent = function(Callback: TEWDeviceInfoSentCallback): Integer; stdcall;

var
  // Lifecycle
  ew_Initialize: Tew_Initialize;
  ew_InitializeEx: Tew_InitializeEx;
  ew_Shutdown: Tew_Shutdown;
  ew_Flush: Tew_Flush;
  ew_GetVersion: Tew_GetVersion;
  ew_GetLastError: Tew_GetLastError;
  ew_GetABIVersion: Tew_GetABIVersion;
  // Logging
  ew_Log: Tew_Log;
  ew_Debug: Tew_LogShortcut;
  ew_Info: Tew_LogShortcut;
  ew_Warning: Tew_LogShortcut;
  ew_Error: Tew_LogShortcut;
  ew_Fatal: Tew_LogShortcut;
  ew_ErrorWithStackTrace: Tew_ErrorWithStackTrace;
  // Breadcrumbs
  ew_AddBreadcrumb: Tew_AddBreadcrumb;
  ew_ClearBreadcrumbs: Tew_ClearBreadcrumbs;
  // Timing
  ew_StartTiming: Tew_StartTiming;
  ew_EndTiming: Tew_EndTiming;
  ew_EndLastTiming: Tew_EndLastTiming;
  ew_CancelTiming: Tew_CancelTiming;
  ew_IsTimingActive: Tew_IsTimingActive;
  // Metrics
  ew_IncrementCounter: Tew_IncrementCounter;
  ew_RecordGauge: Tew_RecordGauge;
  // User
  ew_SetUser: Tew_SetUser;
  ew_ClearUser: Tew_ClearUser;
  // Tags
  ew_SetTag: Tew_SetTag;
  ew_RemoveTag: Tew_RemoveTag;
  ew_ClearTags: Tew_ClearTags;
  // Customer
  ew_SetCustomerId: Tew_SetCustomerId;
  ew_GetCustomerId: Tew_GetCustomerId;
  // Device
  ew_SendDeviceInfo: Tew_SendDeviceInfo;
  ew_SetCustomDeviceInfo: Tew_SetCustomDeviceInfo;
  ew_SendCustomDeviceInfo: Tew_SendCustomDeviceInfo;
  // Config
  ew_SetEnabled: Tew_SetEnabled;
  ew_GetEnabled: Tew_GetEnabled;
  ew_GetPendingCount: Tew_GetPendingCount;
  // Callbacks
  ew_SetOnError: Tew_SetOnError;
  ew_SetOnLogsSent: Tew_SetOnLogsSent;
  ew_SetOnDeviceInfoSent: Tew_SetOnDeviceInfoSent;

/// <summary>
/// Loads the ExeWatch DLL. Returns True on success.
/// Call this before any ew_* function.
/// </summary>
function EWLoadDLL(const ADLLPath: WideString): Boolean; overload;
function EWLoadDLL: Boolean; overload;

/// <summary>
/// Unloads the DLL and clears all function pointers.
/// </summary>
procedure EWUnloadDLL;

/// <summary>
/// Returns True if the DLL is currently loaded.
/// </summary>
function EWDLLLoaded: Boolean;

{$ENDIF}

implementation

procedure EWConfigInit(var Config: TEWDLLConfig);
begin
  FillChar(Config, SizeOf(Config), 0);
  Config.StructSize := SizeOf(TEWDLLConfig);
  Config.MaxPendingAgeDays := -1;  // -1 = DLL uses default (7 days)
end;

function EWGetLastErrorStr: WideString;
var
  Buf: array[0..1023] of WideChar;
  Res: Integer;
begin
  Res := ew_GetLastError(@Buf[0], Length(Buf));
  if Res = EW_OK then
    Result := WideString(PWideChar(@Buf[0]))
  else
    Result := '';
end;

function EWStr(const S: string): EWString;
begin
  {$IFDEF EW_UNICODE_DELPHI}
  Result := S;  // string is already UnicodeString
  {$ELSE}
  Result := WideString(S);  // convert AnsiString to WideString
  {$ENDIF}
end;

// Helper: returns PWideChar for a non-empty EWString, or nil for empty
function EWPChar(const S: EWString): PWideChar;
begin
  if Length(S) > 0 then
    Result := PWideChar(S)
  else
    Result := nil;
end;

// --- Convenience wrappers ---

function EWCheckABIVersion: Integer;
var
  DLLVersion: Integer;
begin
  DLLVersion := ew_GetABIVersion;
  if DLLVersion <> EW_IMPORT_ABI_VERSION then
    Result := EW_ERR_VERSION_MISMATCH
  else
    Result := EW_OK;
end;

function EWInitialize(const AApiKey, ACustomerId: string; const AAppVersion: string): Integer;
var
  WKey, WCust, WVer: EWString;
begin
  // Verify DLL ABI compatibility before initializing
  Result := EWCheckABIVersion;
  if Result <> EW_OK then
    Exit;
  WKey := EWStr(AApiKey);
  WCust := EWStr(ACustomerId);
  WVer := EWStr(AAppVersion);
  Result := ew_Initialize(PWideChar(WKey), EWPChar(WCust), EWPChar(WVer));
end;

function EWLog(ALevel: Integer; const AMsg: string; const ATag: string; const AExtraDataJson: string): Integer;
var
  WMsg, WTag, WJson: EWString;
begin
  WMsg := EWStr(AMsg);
  WTag := EWStr(ATag);
  WJson := EWStr(AExtraDataJson);
  Result := ew_Log(ALevel, PWideChar(WMsg), EWPChar(WTag), EWPChar(WJson));
end;

function EWDebug(const AMsg: string; const ATag: string): Integer;
begin
  Result := EWLog(EW_LOG_DEBUG, AMsg, ATag);
end;

function EWInfo(const AMsg: string; const ATag: string): Integer;
begin
  Result := EWLog(EW_LOG_INFO, AMsg, ATag);
end;

function EWWarning(const AMsg: string; const ATag: string): Integer;
begin
  Result := EWLog(EW_LOG_WARNING, AMsg, ATag);
end;

function EWError(const AMsg: string; const ATag: string): Integer;
begin
  Result := EWLog(EW_LOG_ERROR, AMsg, ATag);
end;

function EWFatal(const AMsg: string; const ATag: string): Integer;
begin
  Result := EWLog(EW_LOG_FATAL, AMsg, ATag);
end;

function EWErrorWithStackTrace(const AMsg: string; const ATag: string;
  const AStackTrace: string; const AExceptionClass: string): Integer;
var
  WMsg, WTag, WST, WEC: EWString;
begin
  WMsg := EWStr(AMsg);
  WTag := EWStr(ATag);
  WST := EWStr(AStackTrace);
  WEC := EWStr(AExceptionClass);
  Result := ew_ErrorWithStackTrace(PWideChar(WMsg), EWPChar(WTag),
    EWPChar(WST), EWPChar(WEC));
end;

function EWAddBreadcrumb(ABreadcrumbType: Integer; const ACategory, AMsg: string; const ADataJson: string): Integer;
var
  WCat, WMsg, WJson: EWString;
begin
  WCat := EWStr(ACategory);
  WMsg := EWStr(AMsg);
  WJson := EWStr(ADataJson);
  Result := ew_AddBreadcrumb(ABreadcrumbType, EWPChar(WCat), PWideChar(WMsg), EWPChar(WJson));
end;

function EWStartTiming(const AId: string; const ATag: string): Integer;
var
  WId, WTag: EWString;
begin
  WId := EWStr(AId);
  WTag := EWStr(ATag);
  Result := ew_StartTiming(PWideChar(WId), EWPChar(WTag));
end;

function EWEndTiming(const AId: string; out AElapsedMs: Double): Integer;
var
  WId: EWString;
begin
  WId := EWStr(AId);
  Result := ew_EndTiming(PWideChar(WId), AElapsedMs);
end;

function EWSetUser(const AId: string; const AEmail: string; const AName: string): Integer;
var
  WId, WEmail, WName: EWString;
begin
  WId := EWStr(AId);
  WEmail := EWStr(AEmail);
  WName := EWStr(AName);
  Result := ew_SetUser(PWideChar(WId), EWPChar(WEmail), EWPChar(WName));
end;

function EWSetTag(const AKey, AValue: string): Integer;
var
  WKey, WVal: EWString;
begin
  WKey := EWStr(AKey);
  WVal := EWStr(AValue);
  Result := ew_SetTag(PWideChar(WKey), PWideChar(WVal));
end;

function EWRemoveTag(const AKey: string): Integer;
var
  WKey: EWString;
begin
  WKey := EWStr(AKey);
  Result := ew_RemoveTag(PWideChar(WKey));
end;

function EWSetCustomerId(const AId: string): Integer;
var
  WId: EWString;
begin
  WId := EWStr(AId);
  Result := ew_SetCustomerId(PWideChar(WId));
end;

function EWSetCustomDeviceInfo(const AKey, AValue: string): Integer;
var
  WKey, WVal: EWString;
begin
  WKey := EWStr(AKey);
  WVal := EWStr(AValue);
  Result := ew_SetCustomDeviceInfo(PWideChar(WKey), PWideChar(WVal));
end;

function EWIncrementCounter(const AName: string; AValue: Double; const ATag: string): Integer;
var
  WName, WTag: EWString;
begin
  WName := EWStr(AName);
  WTag := EWStr(ATag);
  Result := ew_IncrementCounter(PWideChar(WName), AValue, EWPChar(WTag));
end;

function EWRecordGauge(const AName: string; AValue: Double; const ATag: string): Integer;
var
  WName, WTag: EWString;
begin
  WName := EWStr(AName);
  WTag := EWStr(ATag);
  Result := ew_RecordGauge(PWideChar(WName), AValue, EWPChar(WTag));
end;

{$IFDEF EW_DYNAMIC_LOAD}

var
  GDLLHandle: HMODULE = 0;

procedure ClearAllPointers;
begin
  @ew_Initialize := nil;
  @ew_InitializeEx := nil;
  @ew_Shutdown := nil;
  @ew_Flush := nil;
  @ew_GetVersion := nil;
  @ew_GetLastError := nil;
  @ew_GetABIVersion := nil;
  @ew_Log := nil;
  @ew_Debug := nil;
  @ew_Info := nil;
  @ew_Warning := nil;
  @ew_Error := nil;
  @ew_Fatal := nil;
  @ew_ErrorWithStackTrace := nil;
  @ew_AddBreadcrumb := nil;
  @ew_ClearBreadcrumbs := nil;
  @ew_StartTiming := nil;
  @ew_EndTiming := nil;
  @ew_EndLastTiming := nil;
  @ew_CancelTiming := nil;
  @ew_IsTimingActive := nil;
  @ew_IncrementCounter := nil;
  @ew_RecordGauge := nil;
  @ew_SetUser := nil;
  @ew_ClearUser := nil;
  @ew_SetTag := nil;
  @ew_RemoveTag := nil;
  @ew_ClearTags := nil;
  @ew_SetCustomerId := nil;
  @ew_GetCustomerId := nil;
  @ew_SendDeviceInfo := nil;
  @ew_SetCustomDeviceInfo := nil;
  @ew_SendCustomDeviceInfo := nil;
  @ew_SetEnabled := nil;
  @ew_GetEnabled := nil;
  @ew_GetPendingCount := nil;
  @ew_SetOnError := nil;
  @ew_SetOnLogsSent := nil;
  @ew_SetOnDeviceInfoSent := nil;
end;

function EWLoadDLL(const ADLLPath: WideString): Boolean;
begin
  if GDLLHandle <> 0 then
  begin
    Result := True;
    Exit;
  end;
  GDLLHandle := LoadLibraryW(PWideChar(ADLLPath));
  if GDLLHandle = 0 then
  begin
    Result := False;
    Exit;
  end;

  // Lifecycle
  @ew_Initialize := GetProcAddress(GDLLHandle, 'ew_Initialize');
  @ew_InitializeEx := GetProcAddress(GDLLHandle, 'ew_InitializeEx');
  @ew_Shutdown := GetProcAddress(GDLLHandle, 'ew_Shutdown');
  @ew_Flush := GetProcAddress(GDLLHandle, 'ew_Flush');
  @ew_GetVersion := GetProcAddress(GDLLHandle, 'ew_GetVersion');
  @ew_GetLastError := GetProcAddress(GDLLHandle, 'ew_GetLastError');
  @ew_GetABIVersion := GetProcAddress(GDLLHandle, 'ew_GetABIVersion');
  // Logging
  @ew_Log := GetProcAddress(GDLLHandle, 'ew_Log');
  @ew_Debug := GetProcAddress(GDLLHandle, 'ew_Debug');
  @ew_Info := GetProcAddress(GDLLHandle, 'ew_Info');
  @ew_Warning := GetProcAddress(GDLLHandle, 'ew_Warning');
  @ew_Error := GetProcAddress(GDLLHandle, 'ew_Error');
  @ew_Fatal := GetProcAddress(GDLLHandle, 'ew_Fatal');
  @ew_ErrorWithStackTrace := GetProcAddress(GDLLHandle, 'ew_ErrorWithStackTrace');
  // Breadcrumbs
  @ew_AddBreadcrumb := GetProcAddress(GDLLHandle, 'ew_AddBreadcrumb');
  @ew_ClearBreadcrumbs := GetProcAddress(GDLLHandle, 'ew_ClearBreadcrumbs');
  // Timing
  @ew_StartTiming := GetProcAddress(GDLLHandle, 'ew_StartTiming');
  @ew_EndTiming := GetProcAddress(GDLLHandle, 'ew_EndTiming');
  @ew_EndLastTiming := GetProcAddress(GDLLHandle, 'ew_EndLastTiming');
  @ew_CancelTiming := GetProcAddress(GDLLHandle, 'ew_CancelTiming');
  @ew_IsTimingActive := GetProcAddress(GDLLHandle, 'ew_IsTimingActive');
  // Metrics
  @ew_IncrementCounter := GetProcAddress(GDLLHandle, 'ew_IncrementCounter');
  @ew_RecordGauge := GetProcAddress(GDLLHandle, 'ew_RecordGauge');
  // User
  @ew_SetUser := GetProcAddress(GDLLHandle, 'ew_SetUser');
  @ew_ClearUser := GetProcAddress(GDLLHandle, 'ew_ClearUser');
  // Tags
  @ew_SetTag := GetProcAddress(GDLLHandle, 'ew_SetTag');
  @ew_RemoveTag := GetProcAddress(GDLLHandle, 'ew_RemoveTag');
  @ew_ClearTags := GetProcAddress(GDLLHandle, 'ew_ClearTags');
  // Customer
  @ew_SetCustomerId := GetProcAddress(GDLLHandle, 'ew_SetCustomerId');
  @ew_GetCustomerId := GetProcAddress(GDLLHandle, 'ew_GetCustomerId');
  // Device
  @ew_SendDeviceInfo := GetProcAddress(GDLLHandle, 'ew_SendDeviceInfo');
  @ew_SetCustomDeviceInfo := GetProcAddress(GDLLHandle, 'ew_SetCustomDeviceInfo');
  @ew_SendCustomDeviceInfo := GetProcAddress(GDLLHandle, 'ew_SendCustomDeviceInfo');
  // Config
  @ew_SetEnabled := GetProcAddress(GDLLHandle, 'ew_SetEnabled');
  @ew_GetEnabled := GetProcAddress(GDLLHandle, 'ew_GetEnabled');
  @ew_GetPendingCount := GetProcAddress(GDLLHandle, 'ew_GetPendingCount');
  // Callbacks
  @ew_SetOnError := GetProcAddress(GDLLHandle, 'ew_SetOnError');
  @ew_SetOnLogsSent := GetProcAddress(GDLLHandle, 'ew_SetOnLogsSent');
  @ew_SetOnDeviceInfoSent := GetProcAddress(GDLLHandle, 'ew_SetOnDeviceInfoSent');

  // Verify at least the critical exports were found
  Result := Assigned(ew_Initialize) and Assigned(ew_Shutdown) and Assigned(ew_Log);
  if not Result then
  begin
    EWUnloadDLL;
    Exit;
  end;

  // Verify ABI compatibility
  if Assigned(ew_GetABIVersion) then
  begin
    if ew_GetABIVersion <> EW_IMPORT_ABI_VERSION then
    begin
      EWUnloadDLL;
      Result := False;
      Exit;
    end;
  end;
end;

function EWLoadDLL: Boolean;
begin
  Result := EWLoadDLL(EXEWATCH_DLL);
end;

procedure EWUnloadDLL;
begin
  if GDLLHandle <> 0 then
  begin
    FreeLibrary(GDLLHandle);
    GDLLHandle := 0;
  end;
  ClearAllPointers;
end;

function EWDLLLoaded: Boolean;
begin
  Result := GDLLHandle <> 0;
end;

{$ENDIF}

end.
