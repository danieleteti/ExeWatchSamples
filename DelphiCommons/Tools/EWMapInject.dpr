program EWMapInject;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  EWMapInjectU in 'EWMapInjectU.pas';

var
  PEFile, MapFile: string;
  DeleteMap: Boolean;
  I: Integer;
  Symbols: Integer;
  Code: Integer;
begin
  PEFile := '';
  MapFile := '';
  DeleteMap := False;
  for I := 1 to ParamCount do
  begin
    if SameText(ParamStr(I), '/delete-map') or SameText(ParamStr(I), '--delete-map') then
      DeleteMap := True
    else if PEFile = '' then
      PEFile := ParamStr(I)
    else if MapFile = '' then
      MapFile := ParamStr(I);
  end;
  if (PEFile = '') or (MapFile = '') then
  begin
    Writeln('Usage: EWMapInject <pe> <map> [/delete-map]');
    Writeln('  Links the Borland map into the PE as the EXEWATCH_MAP resource.');
    Halt(1);
  end;
  Code := EWMapInjectMapResource(PEFile, MapFile, Symbols, DeleteMap);
  case Code of
    0:
      Writeln(ExtractFileName(PEFile), ': map linked (', Symbols, ' symbols)');
    2:
      Writeln('File not found: ', PEFile, ' / ', MapFile);
    3:
      Writeln('Map is empty: ', MapFile);
    4:
      Writeln('Resource update failed on ', PEFile, ' (GetLastError=', GetLastError, ')');
    5:
      Writeln(ExtractFileName(PEFile), ': map linked but the map file could not be deleted');
  end;
  if Code = 5 then
    Code := 0;  // the deliverable is in place; a leftover map is not a build break
  if Code <> 0 then
    Halt(Code);
end.