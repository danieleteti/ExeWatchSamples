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
  // Per-project toggle: default is ON for every project that links the SDK;
  // the project manager menu writes this project option (persisted inside
  // the .dproj), and/or a comment placed by hand in the .dpr turns it off:
  //   // EXEWATCH MAP LINK: OFF
  EW_MAP_LINK_OPTION = 'EWExeWatchMapLink';
  EW_MAP_LINK_COMMENT_OFF = 'EXEWATCH MAP LINK: OFF';

type
  TEWMapExpert = class;

  // Declared in full here because the expert's constructor creates it; the
  // method bodies sit at the end of the unit, beside TEWProjectMenu's.
  TEWMenuNotifier = class(TNotifierObject, IOTANotifier, IOTAProjectMenuItemCreatorNotifier)
  private
    FExpert: TEWMapExpert;
  public
    constructor Create(AExpert: TEWMapExpert);
    procedure AddMenu(const AProject: IOTAProject; const AIdentList: TStrings;
      const AProjectManagerMenuList: IInterfaceList; AIsMultiSelect: Boolean);
  end;

  TEWMapExpert = class(TInterfacedObject, IOTAWizard,
    IOTAIDENotifier, IOTAIDENotifier50, IOTAIDENotifier80)
  private
    FNotifierIndex: Integer;
    FMenuNotifierIndex: Integer;
    procedure AddMsg(const AProject: IOTAProject; const AMsg: string);
    function FileMentionsExeWatch(const AFileName: string): Boolean;
    function ProjectLinksExeWatch(const AProject: IOTAProject): Boolean;
    function ProjectSourceText(const AProject: IOTAProject): string;
    function MapLinkWanted(const AProject: IOTAProject): Boolean;
    procedure ToggleMapLink(const AProject: IOTAProject);
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

// Right-click on a project: the state of the map link and its toggle. The
// state lives in a project option (the .dproj): the editor buffer and the
// file never diverge, nothing here edits text under a live IDE.
type
  TEWProjectMenu = class(TNotifierObject, IOTALocalMenu, IOTAProjectManagerMenu)
  private
    FExpert: TEWMapExpert;
    FProject: IOTAProject;
  public
    constructor Create(AExpert: TEWMapExpert; const AProject: IOTAProject);
    { IOTALocalMenu }
    function GetCaption: string;
    function GetChecked: Boolean;
    function GetEnabled: Boolean;
    function GetHelpContext: Integer;
    function GetName: string;
    function GetParent: string;
    function GetPosition: Integer;
    function GetVerb: string;
    procedure SetCaption(const Value: string);
    procedure SetChecked(Value: Boolean);
    procedure SetEnabled(Value: Boolean);
    procedure SetHelpContext(Value: Integer);
    procedure SetName(const Value: string);
    procedure SetParent(const Value: string);
    procedure SetPosition(Value: Integer);
    procedure SetVerb(const Value: string);
    { IOTAProjectManagerMenu }
    function GetIsMultiSelectable: Boolean;
    procedure SetIsMultiSelectable(Value: Boolean);
    procedure Execute(const MenuContextList: IInterfaceList);
    function PreExecute(const MenuContextList: IInterfaceList): Boolean;
    function PostExecute(const MenuContextList: IInterfaceList): Boolean;
  end;

constructor TEWMapExpert.Create;
begin
  inherited Create;
  FNotifierIndex := -1;
  FMenuNotifierIndex := -1;
  try
    FNotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(Self);
  except
    // Without the notifier the expert simply does nothing; installing it is
    // not worth a broken IDE startup.
  end;
  try
    FMenuNotifierIndex :=
      (BorlandIDEServices as IOTAProjectManager).AddMenuItemCreatorNotifier(
        TEWMenuNotifier.Create(Self));
  except
    // No project-manager menu: the project option and the .dpr comment
    // still control the toggle.
  end;
end;

destructor TEWMapExpert.Destroy;
begin
  if (FMenuNotifierIndex >= 0) and (BorlandIDEServices <> nil) then
  try
    (BorlandIDEServices as IOTAProjectManager).RemoveMenuItemCreatorNotifier(FMenuNotifierIndex);
  except
  end;
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

// Source text of the project, whichever container file (.dpr or .dproj)
// carries the unit references: one read per call, both for the ExeWatch
// check and for the hand-written OFF comment.
function TEWMapExpert.ProjectSourceText(const AProject: IOTAProject): string;
var
  Names: array[0..1] of string;
  I: Integer;
begin
  Result := '';
  if AProject = nil then
    Exit;
  Names[0] := AProject.FileName;
  Names[1] := ChangeFileExt(AProject.FileName, '.dpr');
  for I := 0 to 1 do
    if FileExists(Names[I]) then
    try
      Result := Result + TFile.ReadAllText(Names[I]);
    except
      // An unreadable container says nothing about map linking.
    end;
end;

function TEWMapExpert.MapLinkWanted(const AProject: IOTAProject): Boolean;
begin
  // Default ON. Off when the project option says so (the manager menu) or
  // when the .dpr carries the hand-written comment.
  Result := True;
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
    Exit;
  try
    if SameText(string(AProject.ProjectOptions.Values[EW_MAP_LINK_OPTION]), 'Off') then
      Exit(False);
  except
    // Options that refuse custom keys keep the default.
  end;
  if Pos(EW_MAP_LINK_COMMENT_OFF, UpperCase(ProjectSourceText(AProject))) > 0 then
    Result := False;
end;

procedure TEWMapExpert.ToggleMapLink(const AProject: IOTAProject);
var
  NewOn: Boolean;
begin
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
    Exit;
  NewOn := not MapLinkWanted(AProject);
  try
    if NewOn then
      AProject.ProjectOptions.Values[EW_MAP_LINK_OPTION] := 'On'
    else
      AProject.ProjectOptions.Values[EW_MAP_LINK_OPTION] := 'Off';
    AProject.ProjectOptions.ModifiedState := True;
    if NewOn then
      AddMsg(AProject, 'Map link ENABLED: next build links the .map into the binary ' +
        '(the option is saved with the project)')
    else
      AddMsg(AProject, 'Map link DISABLED: builds will no longer inject the map ' +
        '(the option is saved with the project)');
  except
    on E: Exception do
      AddMsg(AProject, 'Map link toggle failed: ' + E.ClassName + ': ' + E.Message);
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

  if not MapLinkWanted(AProject) then
    Exit;
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
      AddMsg(AProject, Format('Map injection failed on %s (exit %d; if a ' +
        'debugger or antivirus keeps the file open, retry the build)',
        [ExtractFileName(Target), Code]));
    6:
      AddMsg(AProject, Format('Map not linked into %s: the linker output is ' +
        'not a valid Windows executable; rebuild the project first',
        [ExtractFileName(Target)]));
    7:
      AddMsg(AProject, Format('Map not linked into %s: the PE header area has ' +
        'no room for a section header; the runtime will fall back to the ' +
        '.map file beside the executable',
        [ExtractFileName(Target)]));
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
  // Only projects that link the SDK: outside them the expert must be a
  // silent no-op, not an option force that leaves .map files behind every
  // unrelated build of the user's IDE.
  if not ProjectLinksExeWatch(AProject) then
    Exit;
  try
    if MapLinkWanted(AProject) then
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

constructor TEWProjectMenu.Create(AExpert: TEWMapExpert; const AProject: IOTAProject);
begin
  inherited Create;
  FExpert := AExpert;
  FProject := AProject;
end;

function TEWProjectMenu.GetCaption: string;
begin
  if (FExpert = nil) or (not FExpert.MapLinkWanted(FProject)) then
    Result := 'ExeWatch: map link disabled'
  else
    Result := 'ExeWatch: map link enabled';
end;

function TEWProjectMenu.GetChecked: Boolean;
begin
  if FExpert = nil then
    Result := False
  else
    Result := FExpert.MapLinkWanted(FProject);
end;

function TEWProjectMenu.GetEnabled: Boolean;
begin
  Result := True;
end;

function TEWProjectMenu.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TEWProjectMenu.GetName: string;
begin
  Result := 'EWMapLinkToggle';
end;

function TEWProjectMenu.GetParent: string;
begin
  Result := '';
end;

function TEWProjectMenu.GetPosition: Integer;
begin
  Result := pmmpUserOptions;
end;

function TEWProjectMenu.GetVerb: string;
begin
  Result := 'ExeWatchMapLinkToggle';
end;

procedure TEWProjectMenu.SetCaption(const Value: string);
begin
end;

procedure TEWProjectMenu.SetChecked(Value: Boolean);
begin
end;

procedure TEWProjectMenu.SetEnabled(Value: Boolean);
begin
end;

procedure TEWProjectMenu.SetHelpContext(Value: Integer);
begin
end;

procedure TEWProjectMenu.SetName(const Value: string);
begin
end;

procedure TEWProjectMenu.SetParent(const Value: string);
begin
end;

procedure TEWProjectMenu.SetPosition(Value: Integer);
begin
end;

procedure TEWProjectMenu.SetVerb(const Value: string);
begin
end;

function TEWProjectMenu.GetIsMultiSelectable: Boolean;
begin
  Result := False;
end;

procedure TEWProjectMenu.SetIsMultiSelectable(Value: Boolean);
begin
end;

procedure TEWProjectMenu.Execute(const MenuContextList: IInterfaceList);
begin
  if FExpert <> nil then
    FExpert.ToggleMapLink(FProject);
end;

function TEWProjectMenu.PreExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

function TEWProjectMenu.PostExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

// Feeds the project manager: one toggle item per project container.
constructor TEWMenuNotifier.Create(AExpert: TEWMapExpert);
begin
  inherited Create;
  FExpert := AExpert;
end;

procedure TEWMenuNotifier.AddMenu(const AProject: IOTAProject;
  const AIdentList: TStrings; const AProjectManagerMenuList: IInterfaceList;
  AIsMultiSelect: Boolean);
begin
  if (FExpert <> nil) and (not AIsMultiSelect) and Assigned(AProject) and
     (AIdentList.IndexOf(sProjectContainer) >= 0) then
    AProjectManagerMenuList.Add(TEWProjectMenu.Create(FExpert, AProject));
end;

end.