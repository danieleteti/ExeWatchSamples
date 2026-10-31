program ExeWatchMapCLI;

{$APPTYPE CONSOLE}

{
  Links a Borland .map file INTO a compiled PE (as the EXEWATCH_MAP resource)
  after every build of a project that uses the ExeWatch SDK.

  Who calls this:
  - IDE builds: the ExeWatchMapExpert package does the same injection
    in-process at the end of the build.
  - CI and command-line builds (including AI agents): this CLI.

  Usage:
    ExeWatchMapCLI <binary> [<binary>.map] [--delete-map] [/? or --help]

  With no map argument the tool looks for the .map beside the binary. With
  --delete-map it removes the .map after a successful injection.

  Machine-readable result on the FIRST line of stdout (parse this):
    RESULT=INJECTED symbols=<n> pe=<file>      (exit 0)
    RESULT=FAILED code=<n> reason=<text>       (exit <n>)

  Exit codes:
    0  injected (or replaced) successfully
    1  usage error
    2  the binary or the .map is missing
    3  the .map is empty
    4  the PE could not be written to disk
    5  injected, but the .map could not be deleted (treated as 0)
    6  the binary is not a valid Windows executable
    7  no room in the header area for a new section header
}

uses
  System.SysUtils,
  EWMapInjectU in 'EWMapInjectU.pas';

var
  DeleteMap: Boolean;
  PEFile, MapFile, Arg: string;
  Symbols, Code: Integer;
  I: Integer;

function ReasonText(const ACode: Integer): string;
begin
  case ACode of
    0: Result := 'ok';
    1: Result := 'usage-error';
    2: Result := 'pe-or-map-file-not-found';
    3: Result := 'map-file-empty';
    4: Result := 'pe-write-failed';
    5: Result := 'map-delete-failed';
    6: Result := 'not-a-pe';
    7: Result := 'no-header-room';
  else
    Result := 'unknown';
  end;
end;

procedure WriteHelp;
begin
  Writeln('ExeWatchMapCLI <binary> [<binary>.map] [--delete-map]');
  Writeln('  Links the Borland map into the binary as the EXEWATCH_MAP resource.');
  Writeln('  Without a map argument the .map beside the binary is used;');
  Writeln('  --delete-map removes it after a successful injection.');
  Writeln('Result line: RESULT=INJECTED symbols=<n> pe=<file>');
  Writeln('             RESULT=FAILED code=<n> reason=<text>');
  Writeln('Exit codes: 0 ok, 1 usage, 2 file missing, 3 map empty, 4 resource failure,');
  Writeln('            5 injected but the map could not be deleted (treated as 0).');
end;

begin
  SetLength(PEFile, 0);
  SetLength(MapFile, 0);
  DeleteMap := False;
  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if SameText(Arg, '/help') or SameText(Arg, '/?') or SameText(Arg, '--help') or SameText(Arg, '-h') then
    begin
      WriteHelp;
      Halt(0);
    end
    else if SameText(Arg, '/delete-map') or SameText(Arg, '--delete-map') then
      DeleteMap := True
    else if PEFile = '' then
      PEFile := Arg
    else if MapFile = '' then
      MapFile := Arg;
  end;
  if PEFile = '' then
  begin
    WriteHelp;
    Halt(1);
  end;
  if MapFile = '' then
    MapFile := ChangeFileExt(PEFile, '.map');
  Code := EWMapInjectMapResource(PEFile, MapFile, Symbols, DeleteMap);
  if Code = 0 then
    Writeln('RESULT=INJECTED symbols=', Symbols, ' pe=', PEFile)
  else
    Writeln('RESULT=FAILED code=', Code, ' reason=', ReasonText(Code), ' pe=', PEFile);
  if Code = 5 then
    Code := 0;  // the deliverable is in place; a leftover map is not a build break
  if Code <> 0 then
    Halt(Code);
end.