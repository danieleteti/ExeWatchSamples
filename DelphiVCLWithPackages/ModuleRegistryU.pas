{ ============================================================================
  ModuleRegistryU - Module Registration System for Runtime Packages

  This unit provides a simple registry where dynamically loaded packages
  can register their forms. The host application queries the registry
  to discover and instantiate module forms.

  This unit MUST be in a shared package (ExeWatchSDKPkg) so that both
  the host app and all module packages share the same global registry.
  ============================================================================ }

unit ModuleRegistryU;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, Vcl.Forms;

type
  TModuleInfo = record
    ModuleName: string;
    FormClass: TFormClass;
    Description: string;
  end;

procedure RegisterModule(const AModuleName, ADescription: string; AFormClass: TFormClass);
function GetRegisteredModules: TArray<TModuleInfo>;
procedure ClearModuleRegistry;

implementation

var
  GModuleList: TList<TModuleInfo>;

procedure RegisterModule(const AModuleName, ADescription: string; AFormClass: TFormClass);
var
  Info: TModuleInfo;
begin
  Info.ModuleName := AModuleName;
  Info.Description := ADescription;
  Info.FormClass := AFormClass;
  GModuleList.Add(Info);
end;

function GetRegisteredModules: TArray<TModuleInfo>;
begin
  Result := GModuleList.ToArray;
end;

procedure ClearModuleRegistry;
begin
  GModuleList.Clear;
end;

initialization
  GModuleList := TList<TModuleInfo>.Create;

finalization
  GModuleList.Free;

end.
