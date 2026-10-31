unit EWMapInjectU;

{
  Links a Borland .map file INTO a compiled PE as an RCDATA resource
  (EXEWATCH_MAP). The ExeWatch SDK reads the symbols straight from the
  mapped image at runtime; a plain .map file beside the module only backs it
  up. Build-time callers: the console tool (EWMapInject.dpr) and the RAD
  Studio expert, which call this same routine.

  Exit/result codes:
    0  injected (or replaced) successfully
    2  a file path is missing or empty
    3  the map is empty
    4  a resource API failed (Begin/Update/EndUpdateResource)
    5  injected, but the requested map deletion failed
}

interface

uses
  System.SysUtils, Winapi.Windows;

const
  EW_MAP_RESOURCE_NAME = 'EXEWATCH_MAP';

function EWMapInjectMapResource(const APEFile, AMapFile: string;
  out ASymbolCount: Integer; ADeleteMap: Boolean = False): Integer;

implementation

uses
  System.Classes;

// One entry per 'Publics by Value' map row: segment:offset then the symbol
// name. Enough for the user-facing count, exact enough to match what the
// runtime parser stores.
function CountMapSymbols(const AText: string): Integer;
var
  SL: TStringList;
  I: Integer;
  BlankCount: Integer;
  InSection: Boolean;
begin
  Result := 0;
  if AText = '' then
    Exit;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    InSection := False;
    BlankCount := 0;
    for I := 0 to SL.Count - 1 do
    begin
      if not InSection then
      begin
        if Pos('Publics by Value', SL[I]) > 0 then
          InSection := True;
        Continue;
      end;
      if Trim(SL[I]) = '' then
      begin
        Inc(BlankCount);
        if BlankCount >= 2 then
          Break;
        Continue;
      end;
      BlankCount := 0;
      if SL[I].StartsWith(' ') and (Pos(':', SL[I]) > 0) and
         (not SL[I].StartsWith('Address')) then
        Inc(Result);
    end;
  finally
    SL.Free;
  end;
end;

function MapFileSize(const AFile: string): Int64;
var
  Search: TSearchRec;
begin
  Result := -1;
  if System.SysUtils.FindFirst(AFile, faAnyFile, Search) = 0 then
  begin
    Result := Search.Size;
    System.SysUtils.FindClose(Search);
  end;
end;

function EWMapInjectMapResource(const APEFile, AMapFile: string;
  out ASymbolCount: Integer; ADeleteMap: Boolean = False): Integer;
var
  MapBytes: TBytes;
  MapStream: TFileStream;
  Update: THandle;
begin
  ASymbolCount := 0;
  if (APEFile = '') or (AMapFile = '') or
     (not FileExists(APEFile)) or (not FileExists(AMapFile)) then
    Exit(2);
  // Empty-on-disk counts as missing: injecting a useless resource would hide
  // the problem instead of failing the build.
  if MapFileSize(AMapFile) <= 0 then
    Exit(3);
  MapStream := TFileStream.Create(AMapFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(MapBytes, MapStream.Size);
    MapStream.ReadBuffer(MapBytes[0], Length(MapBytes));
  finally
    MapStream.Free;
  end;
  ASymbolCount := CountMapSymbols(TEncoding.Default.GetString(MapBytes));
  Update := BeginUpdateResourceW(PChar(APEFile), False);
  if Update = 0 then
    Exit(4);
  if not UpdateResourceW(Update, RT_RCDATA, PWideChar(EW_MAP_RESOURCE_NAME), 0,
    Pointer(MapBytes), Length(MapBytes)) then
  begin
    EndUpdateResourceW(Update, True);
    Exit(4);
  end;
  if not EndUpdateResourceW(Update, False) then
    Exit(4);
  if ADeleteMap and (not DeleteFile(PChar(AMapFile))) then
    Exit(5);
  Result := 0;
end;

end.