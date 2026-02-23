{ *******************************************************************************
  ExeWatch SDK - VCL Exception Hook

  Include this unit in VCL applications to capture GUI exceptions.
  GUI exceptions are handled by VCL's message loop and don't reach System.ExceptProc.

  Usage:
    Add ExeWatchSDKv1.VCL to your uses clause (anywhere after ExeWatchSDKv1).

  LICENSE: This SDK is licensed exclusively to registered users of the
  ExeWatch platform (https://exewatch.com). Any other use is strictly
  prohibited.

  Copyright (c) 2026 - bit Time Professionals

******************************************************************************* }

unit ExeWatchSDKv1.VCL;

interface

implementation

uses
  System.SysUtils,
  System.JSON,
  Vcl.Forms,
  ExeWatchSDKv1;

type
  TExeWatchVCLHook = class
  private
    FOldHandler: TExceptionEvent;
  public
    procedure ExceptionHandler(Sender: TObject; E: Exception);
    procedure Install;
    procedure Uninstall;
  end;

var
  GVCLHook: TExeWatchVCLHook = nil;

{ TExeWatchVCLHook }

procedure TExeWatchVCLHook.ExceptionHandler(Sender: TObject; E: Exception);
var
  ExtraData: TJSONObject;
begin
  // Log the exception if SDK is initialized
  if ExeWatchIsInitialized then
  begin
    ExtraData := TJSONObject.Create;
    try
      ExtraData.AddPair('exception_class', E.ClassName);
      ExtraData.AddPair('exception_source', 'vcl');

      ExeWatch.Log(llError, 'GUI exception: ' + E.Message, 'exception', ExtraData);
    except
      // Silently ignore errors during exception logging
      ExtraData.Free;
    end;
  end;

  // Call old handler if present (default shows message box)
  if Assigned(FOldHandler) then
    FOldHandler(Sender, E)
  else
    Application.ShowException(E);
end;

procedure TExeWatchVCLHook.Install;
begin
  FOldHandler := Application.OnException;
  Application.OnException := ExceptionHandler;
end;

procedure TExeWatchVCLHook.Uninstall;
begin
  Application.OnException := FOldHandler;
end;

initialization
  // Register with main SDK
  ExeWatchRegisterFrameworkHook;

  // Create and install hook
  GVCLHook := TExeWatchVCLHook.Create;
  GVCLHook.Install;

finalization
  // Restore old handler and free
  if Assigned(GVCLHook) then
  begin
    GVCLHook.Uninstall;
    GVCLHook.Free;
    GVCLHook := nil;
  end;

end.
