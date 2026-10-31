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
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows, Vcl.Dialogs,
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
  TEWAddMonitorMenu = class;

  // Declared in full before the expert class. NO back-reference to the
  // wizard: the IDE's shutdown ordering can free the wizard object while a
  // project-manager menu item still lives, so every menu decision is taken
  // from standalone functions on the IOTAProject alone. The notifier is
  // registered from the unit's initialization, unregistered in finalization.
  TEWMenuNotifier = class(TNotifierObject, IOTANotifier, IOTAProjectMenuItemCreatorNotifier)
  public
    constructor Create;
    procedure AddMenu(const AProject: IOTAProject; const AIdentList: TStrings;
      const AProjectManagerMenuList: IInterfaceList; AIsMultiSelect: Boolean);
  end;

  // 'Add ExeWatch Monitoring' on a project's right-click: wires the SDK unit
  // into the .dpr through the IDE buffer (single undoable edit) and leaves a
  // step-by-step integration comment.
  TEWAddMonitorMenu = class(TNotifierObject, IOTALocalMenu, IOTAProjectManagerMenu)
  private
    FProject: IOTAProject;
  public
    constructor Create(const AProject: IOTAProject);
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

  // The build notifier as its OWN object: one registration, one release.
  // The wizard object used to double as the build notifier (registered as
  // both a wizard and an IOTAIDENotifier): two registrations on one instance
  // meant two IDE releases at uninstall, and the RTL's machinery read the
  // freed memory. Its lifetime = the registration window: the expert's
  // destructor unregisters it before dropping the last reference.
  TEWBuildNotifier = class(TNotifierObject, IOTAIDENotifier,
    IOTAIDENotifier50, IOTAIDENotifier80)
  private
    FExpert: TEWMapExpert;
  public
    constructor Create(AExpert: TEWMapExpert);
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

  TEWMapExpert = class(TInterfacedObject, IOTAWizard)
  private
    FNotifierIndex: Integer;
    procedure AddMsg(const AProject: IOTAProject; const AMsg: string);
    function FileMentionsExeWatch(const AFileName: string): Boolean;
    function ProjectLinksExeWatch(const AProject: IOTAProject): Boolean;
    function MapLinkWanted(const AProject: IOTAProject): Boolean;
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
    FProject: IOTAProject;
  public
    constructor Create(const AProject: IOTAProject);
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

var
  GMenuNotifierIndex: Integer = -1;

constructor TEWBuildNotifier.Create(AExpert: TEWMapExpert);
begin
  inherited Create;
  FExpert := AExpert;
end;

constructor TEWMapExpert.Create;
begin
  inherited Create;
  FNotifierIndex := -1;
  try
    FNotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(
      TEWBuildNotifier.Create(Self));
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

// Standalone: the project-manager menu raises no messages through the
// wizard object either.
procedure EWAddMsg(const AProject: IOTAProject; const AMsg: string);
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
// The editor buffer is the source of truth while the file is open: an edit
// made on the disk file would go lost (or worse, merged) against it.
function EWSourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  I: Integer;
begin
  for I := 0 to AModule.GetModuleFileCount - 1 do
    if Supports(AModule.GetModuleFileEditor(I), IOTASourceEditor, Result) then
      Exit;
  Result := nil;
end;

function EWBufferText(const AEditor: IOTASourceEditor): string;
const
  CHUNK = 16384;
var
  Reader: IOTAEditReader;
  Bytes: TBytes;
  BufPos, BufRead: Integer;
begin
  Reader := AEditor.CreateReader;
  BufPos := 0;
  repeat
    SetLength(Bytes, BufPos + CHUNK);
    BufRead := Reader.GetText(BufPos, PAnsiChar(@Bytes[BufPos]), CHUNK);
    if BufRead > 0 then
      Inc(BufPos, BufRead);
  until BufRead < CHUNK;
  SetLength(Bytes, BufPos);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

// The step-by-step comment the menu item leaves in the .dpr.
function EWIntegrationComment: string;
begin
  Result :=
    '// ==========================================================' + sLineBreak +
    '//  ExeWatch (exewatch.com) - how to integrate monitoring, step by step' + sLineBreak +
    '// ==========================================================' + sLineBreak +
    '//  1) The ExeWatchSDKv1 unit has just been added to this .dpr''s uses.' + sLineBreak +
    '//  2) Initialize once, at startup (e.g. the main form''s OnCreate):' + sLineBreak +
    '//       InitializeExeWatch(''api-key-from-the-ExeWatch-console'', ''customer-id'');' + sLineBreak +
    '//     Log, metrics and breadcrumbs with: EW.Info / EW.Warning /' + sLineBreak +
    '//     EW.Error / EW.Count / EW.Gauge / EW.StartBreadcrumb.' + sLineBreak +
    '//  3) VCL: add ExeWatchSDKv1.VCL to the main form''s uses to capture' + sLineBreak +
    '//     GUI exceptions; for FMX use ExeWatchSDKv1.FMX.' + sLineBreak +
    '//  4) Stack trace with names and lines: Project Options > Compiling >' + sLineBreak +
    '//     Linking > Map file = Detailed. The ExeWatch expert (default ON)' + sLineBreak +
    '//     links the map into the binary at every build; without it, the' + sLineBreak +
    '//     .map beside the executable is enough for the SDK.' + sLineBreak +
    '// ==========================================================' + sLineBreak;
end;


// 'Add ExeWatch Monitoring': the SDK unit (+ the VCL/FMX wrapper for GUI
// projects) into the .dpr's uses and the integration comment at the top,
// all through the IDE buffer in undoable steps. Idempotent: a project
// already carrying the unit reports and edits nothing.
procedure EWAddMonitoring(const AProject: IOTAProject;
  const AExplain: TProc<string>);
var
  DprFile, BufferText, Upper, UnitsText, AfterUses: string;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  Writer: IOTAEditWriter;
  UsesPos, BreakWalk: Integer;
begin
  if AProject = nil then
  begin
    AExplain('No project on this menu: IOTAProject was nil.');
    Exit;
  end;
  // the work-in-progress line goes to the Messages view; the DIALOG is
  // reserved for the outcome
  EWAddMsg(AProject, 'Add ExeWatch Monitoring: working on ' +
    ChangeFileExt(ExtractFileName(AProject.FileName), '.dpr') + '...');
  DprFile := ChangeFileExt(AProject.FileName, '.dpr');
  if SameText(ExtractFileExt(AProject.FileName), '.dpr') then
    DprFile := AProject.FileName;
  if not FileExists(DprFile) then
  begin
    EWAddMsg(AProject, 'No .dpr beside ' + ExtractFileName(AProject.FileName) +
      ': the monitoring setup works on Delphi projects with a .dpr');
    Exit;
  end;
  Module := (BorlandIDEServices as IOTAModuleServices).OpenModule(DprFile);
  Editor := EWSourceEditorOf(Module);
  if not Assigned(Editor) then
  begin
    EWAddMsg(AProject, 'Cannot open the source of ' + ExtractFileName(DprFile));
    Exit;
  end;
  BufferText := EWBufferText(Editor);
  Upper := UpperCase(BufferText);
  try
    if Pos('EXEWATCHSDKV1', Upper) > 0 then
    begin
      EWAddMsg(AProject, 'ExeWatchSDKv1 is already in this project''s uses: nothing to add');
      Exit;
    end;
    if Pos('USES', Upper) = 0 then
    begin
      EWAddMsg(AProject, 'No uses clause in ' + ExtractFileName(DprFile));
      Exit;
    end;
    // The VCL/FMX wrapper follows the .dpr's own uses; the wrapper unit must
    // be reachable like the SDK unit (beside the .dpr or on the search path).
    if Pos('.FMX', Upper) > 0 then
      UnitsText := '  ExeWatchSDKv1,' + sLineBreak + '  ExeWatchSDKv1.FMX,' + sLineBreak
    else if Pos('VCL.', Upper) > 0 then
      UnitsText := '  ExeWatchSDKv1,' + sLineBreak + '  ExeWatchSDKv1.VCL,' + sLineBreak
    else
      UnitsText := '  ExeWatchSDKv1,' + sLineBreak;
    UsesPos := Pos('USES', Upper);
    // A single forward-only writer, edits in ascending offset order against
    // the ORIGINAL buffer text: the comment lands before the keyword, the
    // units on the first item's line.
    AfterUses := BufferText.Substring(UsesPos - 1 + 4);  // from the keyword's end
    BreakWalk := 0;
    while (BreakWalk < Length(AfterUses)) and
          CharInSet(AfterUses[BreakWalk + 1], [#13, #10]) do
      Inc(BreakWalk);
    Writer := Editor.CreateUndoableWriter;
    try
      // 1st edit: the comment, right before 'uses'
      Writer.CopyTo(TEncoding.UTF8.GetByteCount(BufferText.Substring(0, UsesPos - 1)));
      Writer.Insert(PAnsiChar(UTF8String(EWIntegrationComment + sLineBreak)));
      // 2nd edit: the units, at the first item's line start
      Writer.CopyTo(TEncoding.UTF8.GetByteCount(BufferText.Substring(
        UsesPos - 1, 4 + BreakWalk)));
      Writer.Insert(PAnsiChar(UTF8String(UnitsText)));
    finally
      Writer := nil;
      Editor.Show;
    end;
    EWAddMsg(AProject, ExtractFileName(DprFile) +
      ': ExeWatch unit added to the uses (one undo; Ctrl+Z takes it back)');
  except
    on E: Exception do
      AExplain('Add ExeWatch Monitoring failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;


procedure TEWMapExpert.AddMsg(const AProject: IOTAProject; const AMsg: string);
begin
  EWAddMsg(AProject, AMsg);
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
var
  I: Integer;
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
  // The SDK unit can also travel in the uses of ANY project unit (the new
  // wizard puts it in the form's unit, not the .dpr): scan the project's own
  // modules before declaring this project outside ExeWatch.
  if not Result then
    for I := 0 to AProject.GetModuleCount - 1 do
      if FileMentionsExeWatch(AProject.GetModule(I).FileName) then
        Exit(True);
end;

// Source text of the project, whichever container file (.dpr or .dproj)
// carries the unit references: one read per call, both for the ExeWatch
// check and for the hand-written OFF comment.
function EWProjectSourceText(const AProject: IOTAProject): string;
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

function EWMapLinkWanted(const AProject: IOTAProject): Boolean;
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
  if Pos(EW_MAP_LINK_COMMENT_OFF, UpperCase(EWProjectSourceText(AProject))) > 0 then
    Result := False;
end;

procedure EWMapToggleLink(const AProject: IOTAProject);
var
  NewOn: Boolean;
begin
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
    Exit;
  NewOn := not EWMapLinkWanted(AProject);
  try
    if NewOn then
      AProject.ProjectOptions.Values[EW_MAP_LINK_OPTION] := 'On'
    else
      AProject.ProjectOptions.Values[EW_MAP_LINK_OPTION] := 'Off';
    AProject.ProjectOptions.ModifiedState := True;
    if NewOn then
      EWAddMsg(AProject, 'Map link ENABLED: next build links the .map into the binary ' +
        '(the option is saved with the project)')
    else
      EWAddMsg(AProject, 'Map link DISABLED: builds will no longer inject the map ' +
        '(the option is saved with the project)');
  except
    on E: Exception do
      EWAddMsg(AProject, 'Map link toggle failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

// Thin wrappers on the expert object: the menu never calls through the
// wizard, the build notifier keeps its method names.
function TEWMapExpert.MapLinkWanted(const AProject: IOTAProject): Boolean;
begin
  Result := EWMapLinkWanted(AProject);
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

procedure TEWBuildNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
end;

procedure TEWBuildNotifier.BeforeCompile(const AProject: IOTAProject;
  var Cancel: Boolean);
begin
end;

procedure TEWBuildNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TEWBuildNotifier.BeforeCompile(const AProject: IOTAProject;
  IsCodeInsight: Boolean; var Cancel: Boolean);
begin
  if IsCodeInsight then
    Exit;
  // Only projects that link the SDK: outside them the expert must be a
  // silent no-op, not an option force that leaves .map files behind every
  // unrelated build of the user's IDE.
  if not FExpert.ProjectLinksExeWatch(AProject) then
    Exit;
  try
    if FExpert.MapLinkWanted(AProject) then
      FExpert.ForceMapOption(AProject);
  except
    // A failed option read keeps the project's own settings; the build goes on.
  end;
end;

procedure TEWBuildNotifier.AfterCompile(Succeeded: Boolean;
  IsCodeInsight: Boolean);
begin
end;

procedure TEWBuildNotifier.AfterCompile(const AProject: IOTAProject;
  Succeeded: Boolean; IsCodeInsight: Boolean);
begin
  if IsCodeInsight or (not Succeeded) then
    Exit;
  try
    FExpert.ProcessProject(AProject);
  except
    on E: Exception do
      EWAddMsg(AProject, 'Internal error: ' + E.ClassName + ': ' + E.Message);
  end;
end;

constructor TEWProjectMenu.Create(const AProject: IOTAProject);
begin
  inherited Create;
  FProject := AProject;
end;

function TEWProjectMenu.GetCaption: string;
begin
  if not EWMapLinkWanted(FProject) then
    Result := 'ExeWatch: map link disabled'
  else
    Result := 'ExeWatch: map link enabled';
end;

function TEWProjectMenu.GetChecked: Boolean;
begin
  Result := EWMapLinkWanted(FProject);
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
  EWMapToggleLink(FProject);
end;

function TEWProjectMenu.PreExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

function TEWProjectMenu.PostExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

// 'Add ExeWatch Monitoring' item.
constructor TEWAddMonitorMenu.Create(const AProject: IOTAProject);
begin
  inherited Create;
  FProject := AProject;
end;

function TEWAddMonitorMenu.GetCaption: string;
begin
  Result := 'Add ExeWatch Monitoring';
end;

function TEWAddMonitorMenu.GetChecked: Boolean;
begin
  Result := False;
end;

function TEWAddMonitorMenu.GetEnabled: Boolean;
begin
  Result := True;
end;

function TEWAddMonitorMenu.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TEWAddMonitorMenu.GetName: string;
begin
  Result := 'EWAddMonitoring';
end;

function TEWAddMonitorMenu.GetParent: string;
begin
  Result := '';
end;

function TEWAddMonitorMenu.GetPosition: Integer;
begin
  Result := pmmpUserOptions;
end;

function TEWAddMonitorMenu.GetVerb: string;
begin
  Result := 'EWAddExeWatchMonitoring';
end;

procedure TEWAddMonitorMenu.SetCaption(const Value: string);
begin
end;

procedure TEWAddMonitorMenu.SetChecked(Value: Boolean);
begin
end;

procedure TEWAddMonitorMenu.SetEnabled(Value: Boolean);
begin
end;

procedure TEWAddMonitorMenu.SetHelpContext(Value: Integer);
begin
end;

procedure TEWAddMonitorMenu.SetName(const Value: string);
begin
end;

procedure TEWAddMonitorMenu.SetParent(const Value: string);
begin
end;

procedure TEWAddMonitorMenu.SetPosition(Value: Integer);
begin
end;

procedure TEWAddMonitorMenu.SetVerb(const Value: string);
begin
end;

function TEWAddMonitorMenu.GetIsMultiSelectable: Boolean;
begin
  Result := False;
end;

procedure TEWAddMonitorMenu.SetIsMultiSelectable(Value: Boolean);
begin
end;

procedure TEWAddMonitorMenu.Execute(const MenuContextList: IInterfaceList);
begin
  MessageDlg('Add ExeWatch Monitoring: Execute reached', mtInformation, [mbOK], 0);
  EWAddMonitoring(FProject,
    procedure(AWhat: string)
    begin
      MessageDlg('Add ExeWatch Monitoring' + sLineBreak + sLineBreak + AWhat,
        mtInformation, [mbOK], 0);
    end);
end;

function TEWAddMonitorMenu.PreExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

function TEWAddMonitorMenu.PostExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

// Feeds the project manager: one toggle item per project container.
constructor TEWMenuNotifier.Create;
begin
  inherited Create;
end;

procedure TEWMenuNotifier.AddMenu(const AProject: IOTAProject;
  const AIdentList: TStrings; const AProjectManagerMenuList: IInterfaceList;
  AIsMultiSelect: Boolean);
begin
  if (not AIsMultiSelect) and Assigned(AProject) and
     (AIdentList.IndexOf(sProjectContainer) >= 0) then
  begin
    AProjectManagerMenuList.Add(TEWProjectMenu.Create(AProject));
    AProjectManagerMenuList.Add(TEWAddMonitorMenu.Create(AProject));
  end;
end;

procedure RegisterMenuNotifier;
var
  Manager: IOTAProjectManager;
begin
  if (GMenuNotifierIndex >= 0) or
     (not Supports(BorlandIDEServices, IOTAProjectManager, Manager)) then
    Exit;
  GMenuNotifierIndex := Manager.AddMenuItemCreatorNotifier(TEWMenuNotifier.Create);
end;

procedure UnregisterMenuNotifier;
var
  Manager: IOTAProjectManager;
begin
  if (GMenuNotifierIndex >= 0) and
     Supports(BorlandIDEServices, IOTAProjectManager, Manager) then
    Manager.RemoveMenuItemCreatorNotifier(GMenuNotifierIndex);
  GMenuNotifierIndex := -1;
end;

initialization
  RegisterMenuNotifier;

finalization
  UnregisterMenuNotifier;

end.