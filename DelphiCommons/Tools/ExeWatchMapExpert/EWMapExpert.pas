unit EWMapExpert;

{
  Design-time RAD Studio expert that links the .map file INTO the compiled
  binary at the end of every build, for projects that link the ExeWatch SDK.
  Inside the IDE it plays the role the console tool plays for command-line
  builds; both share EWMapInjectU.

  - BeforeCompile: forces the map-file option to 'Detailed' on every leaf of
    the active build configuration, so a map is always produced.
  - AfterCompile (not CodeInsight, build ok): reads the produced .map and, if
    the project links ExeWatchSDKv1, links it as the EXEWATCH_MAP resource.
  Every outcome is reported as a tool message in the Messages view. Nothing
  here may ever break the customer's build: all exceptions become messages,
  never dialog boxes.
}

interface

procedure Register;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  ToolsAPI,
  EWMapInjectU;

const
  EW_MSG_PREFIX = 'ExeWatch map linker';
  EW_EXEWATCH_UNIT = 'ExeWatchSDKv1';
  EW_MAP_OPTION_NAME = 'DCC_MapFile';
  EW_MAP_OPTION_DETAILED = '3';

type
  TEWMapExpert = class(TInterfacedObject, IOTAWizard,
    IOTAIDENotifier, IOTAIDENotifier50, IOTAIDENotifier80)
  private
    FNotifierIndex: Integer;
    procedure AddMsg(const AProject: IOTAProject; const AMsg: string);
    function FileMentionsExeWatch(const AFileName: string): Boolean;
    function ProjectLinksExeWatch(const AProject: IOTAProject): Boolean;
    procedure ForceMapOptionOn(const AConfig: IOTABuildConfiguration);
    procedure ForceMapOption(const AProject: IOTAProject);
    procedure ProcessProject(const AProject: IOTAProject);
  public
    constructor Create;
    destructor Destroy; override;
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAWizard }
    procedure Execute;
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    { IOTAIDENotifier }
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const AProject: IOTAProject;
      var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
    { IOTAIDENotifier50 }
    procedure BeforeCompile(const AProject: IOTAProject;
      IsCodeInsight: Boolean; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean; IsCodeInsight: Boolean); overload;
    { IOTAIDENotifier80 }
    procedure AfterCompile(const AProject: IOTAProject; Succeeded: Boolean;
      IsCodeInsight: Boolean); overload;
  end;

procedure Register;
begin
  RegisterPackageWizard(TEWMapExpert.Create);
end;

function EWMapMakePath(const ABase, APath: string): string;
begin
  if ExtractFilePath(APath) = '' then
    Result := TPath.Combine(ABase, APath)
  else
    Result := APath;
end;

constructor TEWMapExpert.Create;
begin
  inherited Create;
  FNotifierIndex := -1;
  try
    FNotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(Self);
  except
    // Without the notifier the expert simply does nothing; installing it is
    // not worth a broken IDE startup.
  end;
end;

destructor TEWMapExpert.Destroy;
begin
  if (FNotifierIndex >= 0) and (BorlandIDEServices <> nil) then
  try
    (BorlandIDEServices as IOTAServices).RemoveNotifier(FNotifierIndex);
  except
  end;
  inherited Destroy;
end;

procedure TEWMapExpert.AddMsg(const AProject: IOTAProject; const AMsg: string);
var
  MsgServices: IOTAMessageServices;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, MsgServices) then
    Exit;
  if AProject <> nil then
    MsgServices.AddToolMessage(AProject.FileName, AMsg, EW_MSG_PREFIX, 0, 1)
  else
    MsgServices.AddToolMessage('', AMsg, EW_MSG_PREFIX, 0, 1);
end;

procedure TEWMapExpert.AfterSave;
begin
end;

procedure TEWMapExpert.BeforeSave;
begin
end;

procedure TEWMapExpert.Destroyed;
begin
end;

procedure TEWMapExpert.Modified;
begin
end;

procedure TEWMapExpert.Execute;
begin
end;

function TEWMapExpert.FileMentionsExeWatch(const AFileName: string): Boolean;
var
  Content: string;
begin
  Result := False;
  if AFileName = '' then
    Exit;
  if not FileExists(AFileName) then
    Exit;
  try
    Content := TFile.ReadAllText(AFileName);
  except
    Exit;
  end;
  Result := Pos(EW_EXEWATCH_UNIT, Content) > 0;
end;

function TEWMapExpert.ProjectLinksExeWatch(const AProject: IOTAProject): Boolean;
begin
  if AProject = nil then
    Exit(False);
  // Either source form can carry the unit reference: .dproj for IDE projects
  // (.dproj is written beside the .dpr).
  Result := FileMentionsExeWatch(AProject.FileName);
  if not Result then
  begin
    if SameText(ExtractFileExt(AProject.FileName), '.dproj') then
      Result := FileMentionsExeWatch(ChangeFileExt(AProject.FileName, '.dpr'))
    else
      Result := FileMentionsExeWatch(ChangeFileExt(AProject.FileName, '.dproj'));
  end;
end;

procedure TEWMapExpert.ForceMapOptionOn(const AConfig: IOTABuildConfiguration);
var
  I: Integer;
begin
  if AConfig = nil then
    Exit;
  try
    AConfig.Value[EW_MAP_OPTION_NAME] := EW_MAP_OPTION_DETAILED;
  except
    // A configuration that refuses the option keeps whatever it has.
  end;
  for I := 0 to AConfig.GetChildCount - 1 do
    ForceMapOptionOn(AConfig.GetChild(I));
end;

procedure TEWMapExpert.ForceMapOption(const AProject: IOTAProject);
var
  Cfgs: IOTAProjectOptionsConfigurations;
begin
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
    Exit;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Cfgs) then
    Exit;
  ForceMapOptionOn(Cfgs.ActiveConfiguration);
end;

procedure TEWMapExpert.ProcessProject(const AProject: IOTAProject);
var
  Target, MapFile, ProjectBase: string;
  SymbolCount: Integer;
  Code: Integer;

  procedure Explain(const AMsg: string);
  begin
    // The expert is a convenience, never a gate: projects outside ExeWatch
    // stay silent, projects inside it get told WHERE it went wrong.
    if ProjectLinksExeWatch(AProject) then
      AddMsg(AProject, AMsg);
  end;

begin
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
    Exit;
  ProjectBase := ChangeFileExt(AProject.FileName, '');
  Target := AProject.ProjectOptions.TargetName;
  if (Target = '') or (Pos('$(', Target) > 0) then
  begin
    // No usable target name from the options: try the project's own base
    // name with both binary extensions, in the project directory.
    Target := ProjectBase;
  end
  else
    Target := EWMapMakePath(ExtractFilePath(AProject.FileName), Target);

  if (not FileExists(Target)) and FileExists(Target + '.exe') then
    Target := Target + '.exe'
  else if (not FileExists(Target)) and FileExists(Target + '.dll') then
    Target := Target + '.dll';
  if not FileExists(Target) then
  begin
    Explain('Output not found (looked for "' + Target + '" and both binary ' +
      'extensions): the output directory of this configuration differs from ' +
      'what the project options expect - open it once from the IDE');
    Exit;
  end;

  MapFile := ChangeFileExt(Target, '.map');
  if not FileExists(MapFile) then
  begin
    Explain('No .map beside ' + ExtractFileName(Target) + ': the map-file ' +
      'option (Project Options > Compiling > Linking > Map file = ' +
      'Full/Detailed) was not applied to the configuration just built; ' +
      'without it no symbols can be linked');
    Exit;
  end;

  if not ProjectLinksExeWatch(AProject) then
    Exit;

  Code := EWMapInjectMapResource(Target, MapFile, SymbolCount);
  case Code of
    0:
      AddMsg(AProject, Format('%s: map linked (%d symbols)',
        [ExtractFileName(Target), SymbolCount]));
    3:
      AddMsg(AProject, 'Map is empty: ' + MapFile);
    4,
    5:
      AddMsg(AProject, Format('Resource injection failed on %s (exit %d; ' +
        'if a debugger or antivirus keeps the file open, retry the build)',
        [ExtractFileName(Target), Code]));
  end;
end;

function TEWMapExpert.GetIDString: string;
begin
  Result := 'ExeWatch.EWMapExpert';
end;

function TEWMapExpert.GetName: string;
begin
  Result := EW_MSG_PREFIX;
end;

function TEWMapExpert.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TEWMapExpert.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
end;

procedure TEWMapExpert.BeforeCompile(const AProject: IOTAProject;
  var Cancel: Boolean);
begin
end;

procedure TEWMapExpert.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TEWMapExpert.BeforeCompile(const AProject: IOTAProject;
  IsCodeInsight: Boolean; var Cancel: Boolean);
begin
  if IsCodeInsight then
    Exit;
  try
    if ProjectLinksExeWatch(AProject) then
      ForceMapOption(AProject);
  except
    // A failed option read keeps the project's own settings; the build goes on.
  end;
end;

procedure TEWMapExpert.AfterCompile(Succeeded: Boolean;
  IsCodeInsight: Boolean);
begin
end;

procedure TEWMapExpert.AfterCompile(const AProject: IOTAProject;
  Succeeded: Boolean; IsCodeInsight: Boolean);
begin
  if IsCodeInsight or (not Succeeded) then
    Exit;
  try
    ProcessProject(AProject);
  except
    on E: Exception do
      AddMsg(AProject, 'Internal error: ' + E.ClassName + ': ' + E.Message);
  end;
end;

end.