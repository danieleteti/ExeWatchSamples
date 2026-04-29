{ *******************************************************************************
  ExeWatchMadExceptBridgeU

  Single-unit bridge between madExcept and the ExeWatch SDK.

  Add this unit to your project (it's enough to list it in the .dpr uses
  clause — the initialization section does the rest) and every exception
  madExcept intercepts will also be shipped to ExeWatch, with madExcept's
  fully-resolved stack trace attached.

  The callback leaves madExcept's Handled flag alone: the regular madExcept
  dialog, bug report, and email flow continue to work unchanged.

  How it works:

    Build an extra_data JSON with stack_trace set to madExcept's BugReport,
    then call EW.Log(llError, Msg, Tag, ExtraData). The supplied stack is
    sent to the dashboard as-is.

  Requires:
    - madExcept installed and linked (Project > madExcept settings >
      "madExcept enabled") so the debug info used to resolve frames is
      embedded in the executable.
    - ExeWatch SDK v0.22.0 or newer.
    - InitializeExeWatch must be called before exceptions start firing
      (typically right after Application.Initialize). The ExeWatchIsInitialized
      guard below handles the early-startup race.

  Failure modes handled:
    - ExeWatch not yet initialized (crash before InitializeExeWatch):
      skip silently; madExcept still saves the bug report locally.
    - ExceptObject is not an Exception (hardware fault before the Delphi
      wrapper): fall back to madExcept's ExceptClass/ExceptMessage strings.
    - Callback may run on any thread — the EW.* API is thread-safe, so we
      pass stDontSync to avoid unnecessary main-thread marshalling.
******************************************************************************* }

unit ExeWatchMadExceptBridgeU;

interface

implementation

uses
  System.SysUtils,
  System.JSON,
  madExcept,
  ExeWatchSDKv1;

const
  EW_TAG = 'exception';

{ Build the stack-trace string to send to ExeWatch.

  IMEException.BugReport returns the full formatted bug report (exception
  header, call stack of the crashed thread, module list, etc.). madExcept's
  help warns the property can be slow because it may trigger full
  symbolication — but we are already inside an error path, and symbolicated
  frames are precisely why this bridge exists.

  If you prefer a slimmer payload (call stack only, no module/thread list
  or registers), use GetBugReport(false) or drill into BugReportSections
  to extract the 'call stack' field. Every extra KB goes into the log
  event as a single string, subject to the server's max_message_length. }

function BuildMadExceptStackTrace(const ExceptIntf: IMEException): string;
begin
  if ExceptIntf = nil then
    Exit('');
  Result := ExceptIntf.BugReport;
end;

procedure ExeWatchMadExceptHandler(const ExceptIntf: IMEException;
  var Handled: Boolean);
var
  ExtraData: TJSONObject;
  ExClass, ExMsg: string;
  E: TObject;
begin
  if ExceptIntf = nil then
    Exit;
  if not ExeWatchIsInitialized then
    Exit;  // SDK not ready yet — let madExcept handle this one alone

  // Prefer class/message from the original Exception object when available
  // (matches what a try/except would see); fall back to madExcept's fields
  // for hardware faults that arrived before the Delphi wrapper.
  E := ExceptIntf.ExceptObject;
  if Assigned(E) and (E is Exception) then
  begin
    ExClass := E.ClassName;
    ExMsg   := Exception(E).Message;
  end
  else
  begin
    ExClass := ExceptIntf.ExceptClass;
    ExMsg   := ExceptIntf.ExceptMessage;
  end;

  // Pre-populate extra_data so the SDK's Log() skips its own stack capture.
  ExtraData := TJSONObject.Create;
  ExtraData.AddPair('exception_class',   ExClass);
  ExtraData.AddPair('exception_message', ExMsg);
  ExtraData.AddPair('stack_trace',       BuildMadExceptStackTrace(ExceptIntf));

  EW.Log(llError, ExMsg, EW_TAG, ExtraData);

  // Handled deliberately left untouched: madExcept's own dialog,
  // bug report, and email flow must still run.
end;

initialization
  // stDontSync: callback may fire on any thread; EW.* is thread-safe.
  RegisterExceptionHandler(ExeWatchMadExceptHandler, stDontSync);

finalization
  UnregisterExceptionHandler(ExeWatchMadExceptHandler);

end.
