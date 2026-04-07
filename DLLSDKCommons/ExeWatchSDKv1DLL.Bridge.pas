{ *******************************************************************************
  ExeWatch SDK DLL Exports

  Flat stdcall function wrappers around the ExeWatch Delphi SDK.
  This unit is compiled INTO the DLL — not used by consumers.
  Consumers use ExeWatchSDKv1DLL.Import.pas instead.

  All exported functions:
  - Use stdcall calling convention
  - Accept PWideChar for strings
  - Return Integer error codes (0 = OK, negative = error)
  - Catch all exceptions internally

  Copyright (c) 2026 - bit Time Professionals
******************************************************************************* }

unit ExeWatchSDKv1DLL.Bridge;

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  ExeWatchSDKv1;

const
  // Error codes
  EW_OK                      =  0;
  EW_ERR_NOT_INITIALIZED     = -1;
  EW_ERR_ALREADY_INITIALIZED = -2;
  EW_ERR_INVALID_PARAM       = -3;
  EW_ERR_EXCEPTION           = -4;
  EW_ERR_BUFFER_TOO_SMALL    = -5;
  EW_ERR_VERSION_MISMATCH    = -6;

  // ABI version — MUST match EW_IMPORT_ABI_VERSION in ExeWatchSDKv1Imports.pas
  // Increment BOTH whenever the DLL interface changes (new exports,
  // changed signatures, changed record layouts, etc.)
  EW_DLL_ABI_VERSION = 2;

type
  // Config record shared with import unit (must be kept in sync)
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

  // Callback types (stdcall, plain procedure pointers)
  TEWErrorCallback = procedure(ErrorMsg: PWideChar); stdcall;
  TEWLogsSentCallback = procedure(AcceptedCount, RejectedCount: Integer); stdcall;
  TEWDeviceInfoSentCallback = procedure(Success: LongBool; ErrorMsg: PWideChar); stdcall;

// --- Lifecycle ---
function ew_Initialize(ApiKey, CustomerId, AppVersion: PWideChar): Integer; stdcall;
function ew_InitializeEx(Config: PEWDLLConfig): Integer; stdcall;
function ew_Shutdown: Integer; stdcall;
function ew_Flush: Integer; stdcall;
function ew_GetVersion(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
function ew_GetLastError(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
function ew_GetABIVersion: Integer; stdcall;

// --- Logging ---
function ew_Log(Level: Integer; Msg, Tag, ExtraDataJson: PWideChar): Integer; stdcall;
function ew_Debug(Msg, Tag: PWideChar): Integer; stdcall;
function ew_Info(Msg, Tag: PWideChar): Integer; stdcall;
function ew_Warning(Msg, Tag: PWideChar): Integer; stdcall;
function ew_Error(Msg, Tag: PWideChar): Integer; stdcall;
function ew_Fatal(Msg, Tag: PWideChar): Integer; stdcall;
function ew_ErrorWithStackTrace(Msg, Tag, StackTrace, ExceptionClass: PWideChar): Integer; stdcall;

// --- Breadcrumbs ---
function ew_AddBreadcrumb(BreadcrumbType: Integer; Category, Msg, DataJson: PWideChar): Integer; stdcall;
function ew_ClearBreadcrumbs: Integer; stdcall;

// --- Timing ---
function ew_StartTiming(Id, Tag: PWideChar): Integer; stdcall;
function ew_EndTiming(Id: PWideChar; out ElapsedMs: Double): Integer; stdcall;
function ew_EndLastTiming(out ElapsedMs: Double): Integer; stdcall;
function ew_CancelTiming(Id: PWideChar): Integer; stdcall;
function ew_IsTimingActive(Id: PWideChar): LongBool; stdcall;

// --- Metrics ---
function ew_IncrementCounter(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;
function ew_RecordGauge(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;

// --- User Identity ---
function ew_SetUser(Id, Email, Name: PWideChar): Integer; stdcall;
function ew_ClearUser: Integer; stdcall;

// --- Tags ---
function ew_SetTag(Key, Value: PWideChar): Integer; stdcall;
function ew_RemoveTag(Key: PWideChar): Integer; stdcall;
function ew_ClearTags: Integer; stdcall;

// --- Customer ID ---
function ew_SetCustomerId(Id: PWideChar): Integer; stdcall;
function ew_GetCustomerId(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;

// --- Device Info ---
function ew_SendDeviceInfo: Integer; stdcall;
function ew_SetCustomDeviceInfo(Key, Value: PWideChar): Integer; stdcall;
function ew_SendCustomDeviceInfo: Integer; stdcall;

// --- Config ---
function ew_SetEnabled(Value: LongBool): Integer; stdcall;
function ew_GetEnabled: LongBool; stdcall;
function ew_GetPendingCount: Integer; stdcall;

// --- Callbacks ---
function ew_SetOnError(Callback: TEWErrorCallback): Integer; stdcall;
function ew_SetOnLogsSent(Callback: TEWLogsSentCallback): Integer; stdcall;
function ew_SetOnDeviceInfoSent(Callback: TEWDeviceInfoSentCallback): Integer; stdcall;

// --- DLL lifecycle (called from DllProc) ---
procedure DLLCleanup;

implementation

threadvar
  GLastErrorMsg: string;

var
  GInitialized: Boolean = False;
  GInitLock: TCriticalSection = nil;
  // Stored callback pointers
  GOnErrorCallback: TEWErrorCallback = nil;
  GOnLogsSentCallback: TEWLogsSentCallback = nil;
  GOnDeviceInfoSentCallback: TEWDeviceInfoSentCallback = nil;

// --- Helpers ---

procedure SetLastEWError(const AMsg: string);
begin
  GLastErrorMsg := AMsg;
end;

function SafeStr(P: PWideChar): string; inline;
begin
  if P <> nil then
    Result := string(P)
  else
    Result := '';
end;

function SafeStrDefault(P: PWideChar; const ADefault: string): string; inline;
begin
  if (P <> nil) and (P^ <> #0) then
    Result := string(P)
  else
    Result := ADefault;
end;

function CopyToBuffer(const AStr: string; Buffer: PWideChar; BufLen: Integer): Integer;
var
  Len: Integer;
begin
  Len := Length(AStr) + 1; // including null terminator
  if (Buffer = nil) or (BufLen <= 0) then
    Exit(Len); // return required size
  if BufLen < Len then
  begin
    SetLastEWError('Buffer too small. Required: ' + IntToStr(Len) + ' chars');
    Exit(EW_ERR_BUFFER_TOO_SMALL);
  end;
  Move(PWideChar(AStr)^, Buffer^, Len * SizeOf(WideChar));
  Result := EW_OK;
end;

function CheckInitialized: Boolean; inline;
begin
  Result := GInitialized and ExeWatchIsInitialized;
  if not Result then
    SetLastEWError('ExeWatch not initialized. Call ew_Initialize first.');
end;

function ParseExtraDataJson(AJson: PWideChar): TJSONObject;
var
  JsonStr: string;
  Parsed: TJSONValue;
begin
  Result := nil;
  if (AJson = nil) or (AJson^ = #0) then
    Exit;
  JsonStr := string(AJson);
  Parsed := TJSONObject.ParseJSONValue(JsonStr);
  if Parsed is TJSONObject then
    Result := TJSONObject(Parsed)
  else
  begin
    Parsed.Free;
    raise Exception.Create('ExtraData must be a JSON object, got: ' + JsonStr);
  end;
end;

// --- Callback forwarders (called by TExeWatch on shipper thread) ---

type
  TCallbackForwarder = class
    procedure OnError(const AErrorMessage: string);
    procedure OnLogsSent(AAcceptedCount, ARejectedCount: Integer);
    procedure OnDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
  end;

var
  GCallbackForwarder: TCallbackForwarder = nil;

procedure TCallbackForwarder.OnError(const AErrorMessage: string);
var
  Cb: TEWErrorCallback;
begin
  Cb := GOnErrorCallback;
  if Assigned(Cb) then
    Cb(PWideChar(AErrorMessage));
end;

procedure TCallbackForwarder.OnLogsSent(AAcceptedCount, ARejectedCount: Integer);
var
  Cb: TEWLogsSentCallback;
begin
  Cb := GOnLogsSentCallback;
  if Assigned(Cb) then
    Cb(AAcceptedCount, ARejectedCount);
end;

procedure TCallbackForwarder.OnDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
var
  Cb: TEWDeviceInfoSentCallback;
begin
  Cb := GOnDeviceInfoSentCallback;
  if Assigned(Cb) then
    Cb(LongBool(ASuccess), PWideChar(AErrorMessage));
end;

// ============================================================
// Lifecycle
// ============================================================

function ew_Initialize(ApiKey, CustomerId, AppVersion: PWideChar): Integer; stdcall;
var
  Config: TExeWatchConfig;
begin
  try
    if ApiKey = nil then
    begin
      SetLastEWError('ApiKey cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    GInitLock.Enter;
    try
      Config := TExeWatchConfig.Create(SafeStr(ApiKey), SafeStr(CustomerId));
      Config.AppVersion := SafeStr(AppVersion);
      InitializeExeWatch(Config);
      ExeWatch.SendDeviceInfo;
      // Wire up callback forwarder
      ExeWatch.OnError := GCallbackForwarder.OnError;
      ExeWatch.OnLogsSent := GCallbackForwarder.OnLogsSent;
      ExeWatch.OnDeviceInfoSent := GCallbackForwarder.OnDeviceInfoSent;
      GInitialized := True;
    finally
      GInitLock.Leave;
    end;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_InitializeEx(Config: PEWDLLConfig): Integer; stdcall;
var
  SDKConfig: TExeWatchConfig;
begin
  try
    if Config = nil then
    begin
      SetLastEWError('Config cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    if Config^.StructSize < SizeOf(TEWDLLConfig) then
    begin
      SetLastEWError('Config.StructSize mismatch. Expected >= ' +
        IntToStr(SizeOf(TEWDLLConfig)) + ', got ' + IntToStr(Config^.StructSize));
      Exit(EW_ERR_VERSION_MISMATCH);
    end;
    if Config^.ApiKey = nil then
    begin
      SetLastEWError('Config.ApiKey cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    GInitLock.Enter;
    try
      SDKConfig := TExeWatchConfig.Create(SafeStr(Config^.ApiKey), SafeStr(Config^.CustomerId));
      SDKConfig.AppVersion := SafeStr(Config^.AppVersion);
      if (Config^.StoragePath <> nil) and (Config^.StoragePath^ <> #0) then
        SDKConfig.StoragePath := SafeStr(Config^.StoragePath);
      if Config^.BufferSize > 0 then
        SDKConfig.BufferSize := Config^.BufferSize;
      if Config^.FlushIntervalMs > 0 then
        SDKConfig.FlushIntervalMs := Config^.FlushIntervalMs;
      if Config^.RetryIntervalMs > 0 then
        SDKConfig.RetryIntervalMs := Config^.RetryIntervalMs;
      if Config^.SampleRate > 0.0 then
        SDKConfig.SampleRate := Config^.SampleRate;
      if Config^.GaugeSamplingIntervalSec > 0 then
        SDKConfig.GaugeSamplingIntervalSec := Config^.GaugeSamplingIntervalSec;
      if Config^.MaxPendingAgeDays >= 0 then
        SDKConfig.MaxPendingAgeDays := Config^.MaxPendingAgeDays;
      SDKConfig.AnonymizeDeviceId := Config^.AnonymizeDeviceId;

      InitializeExeWatch(SDKConfig);
      ExeWatch.SendDeviceInfo;
      // Wire up callback forwarder
      ExeWatch.OnError := GCallbackForwarder.OnError;
      ExeWatch.OnLogsSent := GCallbackForwarder.OnLogsSent;
      ExeWatch.OnDeviceInfoSent := GCallbackForwarder.OnDeviceInfoSent;
      GInitialized := True;
    finally
      GInitLock.Leave;
    end;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_Shutdown: Integer; stdcall;
begin
  try
    GInitLock.Enter;
    try
      if GInitialized then
      begin
        FinalizeExeWatch;
        GInitialized := False;
        GOnErrorCallback := nil;
        GOnLogsSentCallback := nil;
        GOnDeviceInfoSentCallback := nil;
      end;
    finally
      GInitLock.Leave;
    end;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_Flush: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.Flush;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_GetVersion(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
begin
  try
    Result := CopyToBuffer(EXEWATCH_SDK_VERSION, Buffer, BufLen);
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_GetLastError(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
begin
  try
    Result := CopyToBuffer(GLastErrorMsg, Buffer, BufLen);
  except
    Result := EW_ERR_EXCEPTION;
  end;
end;

function ew_GetABIVersion: Integer; stdcall;
begin
  Result := EW_DLL_ABI_VERSION;
end;

// ============================================================
// Logging
// ============================================================

function ew_Log(Level: Integer; Msg, Tag, ExtraDataJson: PWideChar): Integer; stdcall;
var
  ExtraData: TJSONObject;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Msg = nil then
    begin
      SetLastEWError('Msg cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    if (Level < Ord(Low(TEWLogLevel))) or (Level > Ord(High(TEWLogLevel))) then
    begin
      SetLastEWError('Invalid log level: ' + IntToStr(Level));
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExtraData := ParseExtraDataJson(ExtraDataJson);
    // ExeWatch.Log takes ownership of ExtraData
    ExeWatch.Log(TEWLogLevel(Level), SafeStr(Msg), SafeStrDefault(Tag, 'main'), ExtraData);
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_Debug(Msg, Tag: PWideChar): Integer; stdcall;
begin
  Result := ew_Log(Ord(llDebug), Msg, Tag, nil);
end;

function ew_Info(Msg, Tag: PWideChar): Integer; stdcall;
begin
  Result := ew_Log(Ord(llInfo), Msg, Tag, nil);
end;

function ew_Warning(Msg, Tag: PWideChar): Integer; stdcall;
begin
  Result := ew_Log(Ord(llWarning), Msg, Tag, nil);
end;

function ew_Error(Msg, Tag: PWideChar): Integer; stdcall;
begin
  Result := ew_Log(Ord(llError), Msg, Tag, nil);
end;

function ew_Fatal(Msg, Tag: PWideChar): Integer; stdcall;
begin
  Result := ew_Log(Ord(llFatal), Msg, Tag, nil);
end;

function ew_ErrorWithStackTrace(Msg, Tag, StackTrace, ExceptionClass: PWideChar): Integer; stdcall;
var
  ExtraData: TJSONObject;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Msg = nil then
    begin
      SetLastEWError('Msg cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExtraData := TJSONObject.Create;
    // Pre-set stack_trace so the SDK won't try to capture its own
    // (the SDK skips auto-capture when stack_trace already exists in extra_data)
    if (StackTrace <> nil) and (StackTrace^ <> #0) then
      ExtraData.AddPair('stack_trace', SafeStr(StackTrace));
    if (ExceptionClass <> nil) and (ExceptionClass^ <> #0) then
      ExtraData.AddPair('exception_class', SafeStr(ExceptionClass));
    // Log takes ownership of ExtraData
    ExeWatch.Log(llError, SafeStr(Msg), SafeStrDefault(Tag, 'exception'), ExtraData);
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Breadcrumbs
// ============================================================

function ew_AddBreadcrumb(BreadcrumbType: Integer; Category, Msg, DataJson: PWideChar): Integer; stdcall;
var
  Data: TJSONObject;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if (BreadcrumbType < Ord(Low(TBreadcrumbType))) or (BreadcrumbType > Ord(High(TBreadcrumbType))) then
    begin
      SetLastEWError('Invalid breadcrumb type: ' + IntToStr(BreadcrumbType));
      Exit(EW_ERR_INVALID_PARAM);
    end;
    Data := ParseExtraDataJson(DataJson);
    // AddBreadcrumb takes ownership of Data
    ExeWatch.AddBreadcrumb(TBreadcrumbType(BreadcrumbType),
      SafeStrDefault(Category, 'custom'), SafeStr(Msg), Data);
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_ClearBreadcrumbs: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.ClearBreadcrumbs;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Timing
// ============================================================

function ew_StartTiming(Id, Tag: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Id = nil then
    begin
      SetLastEWError('Timing Id cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.StartTiming(SafeStr(Id), SafeStr(Tag));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_EndTiming(Id: PWideChar; out ElapsedMs: Double): Integer; stdcall;
begin
  ElapsedMs := -1;
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Id = nil then
    begin
      SetLastEWError('Timing Id cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ElapsedMs := ExeWatch.EndTiming(SafeStr(Id));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_EndLastTiming(out ElapsedMs: Double): Integer; stdcall;
begin
  ElapsedMs := -1;
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ElapsedMs := ExeWatch.EndTiming;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_CancelTiming(Id: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if (Id <> nil) and (Id^ <> #0) then
      ExeWatch.CancelTiming(SafeStr(Id))
    else
      ExeWatch.CancelTiming;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_IsTimingActive(Id: PWideChar): LongBool; stdcall;
begin
  try
    if not CheckInitialized then Exit(LongBool(False));
    if Id = nil then Exit(LongBool(False));
    Result := LongBool(ExeWatch.IsTimingActive(SafeStr(Id)));
  except
    Result := LongBool(False);
  end;
end;

// ============================================================
// Metrics
// ============================================================

function ew_IncrementCounter(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Name = nil then
    begin
      SetLastEWError('Counter name cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.IncrementCounter(SafeStr(Name), Value, SafeStr(Tag));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_RecordGauge(Name: PWideChar; Value: Double; Tag: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Name = nil then
    begin
      SetLastEWError('Gauge name cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.RecordGauge(SafeStr(Name), Value, SafeStr(Tag));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// User Identity
// ============================================================

function ew_SetUser(Id, Email, Name: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Id = nil then
    begin
      SetLastEWError('User Id cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.SetUser(SafeStr(Id), SafeStr(Email), SafeStr(Name));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_ClearUser: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.ClearUser;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Tags
// ============================================================

function ew_SetTag(Key, Value: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Key = nil then
    begin
      SetLastEWError('Tag key cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.SetTag(SafeStr(Key), SafeStr(Value));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_RemoveTag(Key: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Key = nil then
    begin
      SetLastEWError('Tag key cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.RemoveTag(SafeStr(Key));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_ClearTags: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.ClearTags;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Customer ID
// ============================================================

function ew_SetCustomerId(Id: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Id = nil then
    begin
      SetLastEWError('Customer Id cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.SetCustomerId(SafeStr(Id));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_GetCustomerId(Buffer: PWideChar; BufLen: Integer): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    Result := CopyToBuffer(ExeWatch.GetCustomerId, Buffer, BufLen);
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Device Info
// ============================================================

function ew_SendDeviceInfo: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.SendDeviceInfo;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_SetCustomDeviceInfo(Key, Value: PWideChar): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    if Key = nil then
    begin
      SetLastEWError('Device info key cannot be nil');
      Exit(EW_ERR_INVALID_PARAM);
    end;
    ExeWatch.SetCustomDeviceInfo(SafeStr(Key), SafeStr(Value));
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_SendCustomDeviceInfo: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.SendCustomDeviceInfo;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// Config
// ============================================================

function ew_SetEnabled(Value: LongBool): Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(EW_ERR_NOT_INITIALIZED);
    ExeWatch.Enabled := Boolean(Value);
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_GetEnabled: LongBool; stdcall;
begin
  try
    if not CheckInitialized then Exit(LongBool(False));
    Result := LongBool(ExeWatch.Enabled);
  except
    Result := LongBool(False);
  end;
end;

function ew_GetPendingCount: Integer; stdcall;
begin
  try
    if not CheckInitialized then Exit(0);
    Result := ExeWatch.GetPendingCount;
  except
    Result := 0;
  end;
end;

// ============================================================
// Callbacks
// ============================================================

function ew_SetOnError(Callback: TEWErrorCallback): Integer; stdcall;
begin
  try
    GOnErrorCallback := Callback;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_SetOnLogsSent(Callback: TEWLogsSentCallback): Integer; stdcall;
begin
  try
    GOnLogsSentCallback := Callback;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

function ew_SetOnDeviceInfoSent(Callback: TEWDeviceInfoSentCallback): Integer; stdcall;
begin
  try
    GOnDeviceInfoSentCallback := Callback;
    Result := EW_OK;
  except
    on E: Exception do
    begin
      SetLastEWError(E.Message);
      Result := EW_ERR_EXCEPTION;
    end;
  end;
end;

// ============================================================
// DLL Cleanup
// ============================================================

procedure DLLCleanup;
begin
  if GInitialized then
  begin
    try
      FinalizeExeWatch;
    except
      // Swallow — we're in DLL_PROCESS_DETACH
    end;
    GInitialized := False;
  end;
  FreeAndNil(GCallbackForwarder);
  FreeAndNil(GInitLock);
end;

initialization
  GInitLock := TCriticalSection.Create;
  GCallbackForwarder := TCallbackForwarder.Create;

end.
