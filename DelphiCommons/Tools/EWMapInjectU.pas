unit EWMapInjectU;

{
  Links a Borland .map file INTO a compiled PE so the ExeWatch SDK can read
  the symbols straight from the mapped image at runtime. The map is stored as
  its own PE section (.ewmap): a section header written into the slack of the
  linker's header area and the map bytes appended after the last section.
  A plain .map file beside the module still backs it up during development.
  Build-time callers: the console tool (ExeWatchMapCLI.dpr) and the RAD Studio
  expert, which call this same routine.

  Why the map is a section and not a resource: growing the resource section
  when other sections sit after it in raw file order (any executable whose
  link order puts .reloc, .pdata or .debug past .rsrc) makes the OS resource
  API rebuild the whole section layout, and that rebuild has been observed
  destroying the DOS header and duplicating section entries, leaving a
  binary the loader refuses before it starts. Writing the section directly
  never moves or rewrites anything but the SizeOfImage field and the section
  count, so the outcome is deterministic for every PE whose header slack
  fits one more 40-byte header.

  Exit/result codes:
    0  injected (or replaced) successfully
    2  a file path is missing or empty
    3  the map is empty
    4  the PE image could not be written to disk
    5  injected, but the requested map deletion failed
    6  the file is not a valid Windows executable
    7  no room in the header area for a new section header
}

interface

uses
  System.SysUtils, Winapi.Windows;

const
  EW_MAP_SECTION_NAME = '.ewmap';
  // First bytes of the section payload: the SDK scans for exactly this.
  EW_MAP_SECTION_SIG = 'EXEWATCHMAPSIG1';
  // Legacy storage form: an earlier injector stored the map as an RCDATA
  // resource and the SDK still reads that, too. This unit writes sections.
  EW_MAP_RESOURCE_NAME = 'EXEWATCH_MAP';

  INJECT_OK = 0;
  INJECT_FILE_MISSING = 2;
  INJECT_MAP_EMPTY = 3;
  INJECT_WRITE_FAILED = 4;
  INJECT_MAP_DELETE_FAILED = 5;
  INJECT_NOT_A_PE = 6;
  INJECT_NO_HEADER_ROOM = 7;

function EWMapInjectMapResource(const APEFile, AMapFile: string;
  out ASymbolCount: Integer; ADeleteMap: Boolean = False): Integer;

implementation

uses
  System.Classes;

const
  // 'EXEWATCHMAPSIG1' is 15 characters; the stored signature is 16 bytes.
  SIGNATURE: array[0..15] of AnsiChar = 'EXEWATCHMAPSIG1' + #0;
  EW_SEC_NAME: array[0..7] of AnsiChar = '.ewmap';
  // Initialized data, readable, discardable: the linker gives .rsrc the same.
  EW_IMAGE_SECTION_CHARS = $42000040;
  SECTION_HEADER_SIZE = $28;

type
  // The PE fields the injector reads and patches, valid for PE32 and PE32+.
  TPELayout = record
    LFanew: Longword;                 // file offset of the PE header block
    COFFOffset: Integer;              // file offset of the COFF header
    SectionTable: Integer;            // file offset of the section header array
    NumSections: Integer;
    NumSectionsFileOffset: Integer;   // file offset of the section count
    SizeOfImageFileOffset: Integer;   // file offset of SizeOfImage
    SizeOfImage: Longword;
    FileAlignment: Longword;
    SectionAlignment: Longword;
    SizeOfHeaders: Longword;
    // Security-directory entry (IMAGE_DIRECTORY_ENTRY_SECURITY, a FILE offset)
    // and COFF symbol table, when present: both hold positions inside the
    // header area and must move with a header relocation.
    HasSecurityDir: Boolean;
    SecurityDirOffset: Integer;       // file offset of the entry's Address field
    HasSymbolTable: Boolean;
    SymbolTableOffset: Integer;       // file offset of the table pointer itself
  end;

function AlignUp(AValue, AAlign: Longword): Longword;
begin
  if AAlign = 0 then
    Exit(AValue);
  Result := AValue + AAlign - 1 - ((AValue + AAlign - 1) mod AAlign);
end;

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

// Reads the PE structure fields, refusing anything the section writer could
// not safely patch: short file, bad signatures, insane tables.
function ReadPELayout(const AImage: TBytes; out ALayout: TPELayout): Boolean;
var
  LFanew, Opt, Magic, Sig: Longword;
begin
  Result := False;
  if Length(AImage) < $80 then
    Exit;
  if PWord(@AImage[0])^ <> $5A4D then
    Exit;
  LFanew := PLongword(@AImage[$3C])^;
  if (LFanew < $40) or (LFanew + $28 > Longword(Length(AImage))) then
    Exit;
  Sig := PLongword(@AImage[LFanew])^;
  if Sig <> $00004550 then
    Exit;
  ALayout.NumSections := PWord(@AImage[LFanew + $06])^;
  if (ALayout.NumSections < 1) or (ALayout.NumSections > 96) then
    Exit;
  Opt := LFanew + $18;
  Magic := PWord(@AImage[Opt])^;
  if (Magic <> $010B) and (Magic <> $020B) then
    Exit; // PE32 and PE32+ only: the field offsets used here are theirs
  ALayout.LFanew := LFanew;
  ALayout.COFFOffset := LFanew + $04;
  ALayout.SizeOfImage := PLongword(@AImage[Opt + 56])^;
  ALayout.FileAlignment := PLongword(@AImage[Opt + 36])^;
  ALayout.SectionAlignment := PLongword(@AImage[Opt + 32])^;
  ALayout.SizeOfHeaders := PLongword(@AImage[Opt + 60])^;
  ALayout.NumSectionsFileOffset := LFanew + $06;
  ALayout.SizeOfImageFileOffset := Opt + 56;
  ALayout.SectionTable := Opt + PWord(@AImage[LFanew + $14])^;
  ALayout.HasSecurityDir := False;
  ALayout.SecurityDirOffset := 0;
  ALayout.HasSymbolTable := False;
  ALayout.SymbolTableOffset := 0;
  if PLongword(@AImage[ALayout.COFFOffset + 8])^ > 0 then
  begin
    ALayout.HasSymbolTable := True;
    ALayout.SymbolTableOffset := ALayout.COFFOffset + 8;
  end;
  // The data directory array starts right past the optional header's fixed
  // part: 96 bytes in PE32, 112 in PE32+. Entry 4 = security.
  if PLongword(@AImage[Opt + $60 + (4 * 8)])^ > 0 then
  begin
    ALayout.HasSecurityDir := True;
    ALayout.SecurityDirOffset := Opt + $60 + (4 * 8);
  end
  else if PLongword(@AImage[Opt + $70 + (4 * 8)])^ > 0 then
  begin
    ALayout.HasSecurityDir := True;
    ALayout.SecurityDirOffset := Opt + $70 + (4 * 8);
  end;
  if ALayout.SizeOfImage = 0 then
    Exit;
  if ALayout.SectionTable + ALayout.NumSections * SECTION_HEADER_SIZE >
     Length(AImage) then
    Exit;
  Result := True;
end;

// The header block (PE signature, COFF, optional header, section table) does
// not have to start at its linked position: everything between the DOS
// header and the first section's raw data is linker slack, and e_lfanew only
// points there. When the canonical position cannot hold one more 40-byte
// section header (Delphi x64 Debug builds leave 24 bytes: one section header
// short), the whole block is moved down into the slack it came after and the
// new header is appended at the end of the moved table. File offsets stored
// inside the block (security-directory entry, symbol-table pointer) follow.
function RelocateHeadersDown(const AImage: TBytes; const ALayout: TPELayout;
  out ANewLayout: TPELayout): Boolean;
var
  I, SectionOff: Integer;
  RawPtr, FirstRaw: Longword;
  NeedSize, BlockLen, NewLFanew, Delta, Stored: Longword;
begin
  Result := False;
  FirstRaw := High(Longword);
  for I := 0 to ALayout.NumSections - 1 do
  begin
    SectionOff := ALayout.SectionTable + I * SECTION_HEADER_SIZE;
    RawPtr := PLongword(@AImage[SectionOff + 20])^;
    if (RawPtr > 0) and (RawPtr < FirstRaw) then
      FirstRaw := RawPtr;
  end;
  if FirstRaw = High(Longword) then
    Exit; // no raw sections at all: nothing sane to relocate against
  NeedSize := Longword(ALayout.SectionTable) - ALayout.LFanew +
    Longword((ALayout.NumSections + 1) * SECTION_HEADER_SIZE);
  if NeedSize > FirstRaw - $40 then
    Exit; // the DOS header must survive untouched below the block
  NewLFanew := FirstRaw - NeedSize;
  Delta := ALayout.LFanew - NewLFanew;
  if Delta = 0 then
    Exit;
  BlockLen := Longword(ALayout.SectionTable) +
    Longword(ALayout.NumSections * SECTION_HEADER_SIZE) - ALayout.LFanew;
  Move(AImage[ALayout.LFanew], AImage[NewLFanew], BlockLen);
  FillChar(AImage[NewLFanew + BlockLen], Delta, 0);
  PLongword(@AImage[$3C])^ := NewLFanew;
  // File offsets pointing INSIDE the moved block shift with it; offsets
  // beyond it (a certificate appended at the end of the file) stay put.
  if ALayout.HasSymbolTable then
  begin
    Stored := PLongword(@AImage[ALayout.SymbolTableOffset])^;
    if (Stored >= ALayout.LFanew) and
       (Stored < ALayout.LFanew + BlockLen) then
      PLongword(@AImage[ALayout.SymbolTableOffset])^ := Stored - Delta;
  end;
  if ALayout.HasSecurityDir then
  begin
    Stored := PLongword(@AImage[ALayout.SecurityDirOffset])^;
    if (Stored >= ALayout.LFanew) and
       (Stored < ALayout.LFanew + BlockLen) then
      PLongword(@AImage[ALayout.SecurityDirOffset])^ := Stored - Delta;
  end;
  if not ReadPELayout(AImage, ANewLayout) then
    Exit;
  Result := True;
end;

// TRUE only when the 8-byte name field is exactly Name followed by zeros.
function SectionHeaderNameIs(const AHeader: PAnsiChar; const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to 7 do
  begin
    if I < Length(AName) then
    begin
      if AHeader[I] <> AnsiChar(AName[I + 1]) then
        Exit;
    end
    else if AHeader[I] <> #0 then
      Exit;
  end;
  Result := True;
end;

function EWMapInjectMapResource(const APEFile, AMapFile: string;
  out ASymbolCount: Integer; ADeleteMap: Boolean = False): Integer;
var
  MapBytes: TBytes;
  MapStream: TFileStream;
  Image: TBytes;
  ImageStream: TFileStream;
  Layout: TPELayout;
  I, SectionOff, MapLen: Integer;
  ExistingRawPtr, ExistingRawSz, ExistingVA: Longword;
  OwnsTail: Boolean;
  NewVSz, NewVA, NewRawSz, NewRawPtr, NewSizeOfImage: Longword;
  HeaderOff: Integer;
  Relayout: TPELayout;
begin
  ASymbolCount := 0;
  if (APEFile = '') or (AMapFile = '') or
     (not FileExists(APEFile)) or (not FileExists(AMapFile)) then
    Exit(INJECT_FILE_MISSING);
  // Empty-on-disk counts as missing: injecting a useless section would hide
  // the problem instead of failing the build.
  if MapFileSize(AMapFile) <= 0 then
    Exit(INJECT_MAP_EMPTY);
  MapStream := TFileStream.Create(AMapFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(MapBytes, MapStream.Size);
    MapStream.ReadBuffer(MapBytes[0], Length(MapBytes));
  finally
    MapStream.Free;
  end;
  ASymbolCount := CountMapSymbols(TEncoding.Default.GetString(MapBytes));
  MapLen := Length(MapBytes);

  ImageStream := TFileStream.Create(APEFile, fmOpenReadWrite or fmShareDenyWrite);
  try
    SetLength(Image, ImageStream.Size);
    if Length(Image) > 0 then
      ImageStream.ReadBuffer(Image[0], Length(Image));
  finally
    ImageStream.Free;
  end;
  if not ReadPELayout(Image, Layout) then
    Exit(INJECT_NOT_A_PE);

  // A section a previous injection left: it must own the file tail to be
  // extended safely in place. Anything else means unknown PE surgery happened
  // meanwhile and is refused instead of overwritten.
  ExistingVA := 0;
  ExistingRawPtr := 0;
  ExistingRawSz := 0;
  OwnsTail := False;
  for I := 0 to Layout.NumSections - 1 do
  begin
    SectionOff := Layout.SectionTable + I * SECTION_HEADER_SIZE;
    if SectionHeaderNameIs(@Image[SectionOff], EW_MAP_SECTION_NAME) then
    begin
      ExistingVA := PLongword(@Image[SectionOff + 12])^;
      ExistingRawSz := PLongword(@Image[SectionOff + 16])^;
      ExistingRawPtr := PLongword(@Image[SectionOff + 20])^;
      OwnsTail := (ExistingRawSz > 0) and
        (Int64(ExistingRawPtr) + Int64(ExistingRawSz) >= Length(Image));
      Break;
    end;
  end;

  if OwnsTail then
  begin
    // Replace/refresh: same VirtualAddress, the payload is rewritten and the
    // file truncated to it when it shrinks - everything past the new payload
    // would be bytes of a previous map.
    NewVSz := $10 + MapLen;
    NewVA := ExistingVA;
    NewRawPtr := ExistingRawPtr;
    NewRawSz := AlignUp(NewVSz, Layout.FileAlignment);
    NewSizeOfImage := AlignUp(NewVA + NewVSz, Layout.SectionAlignment);
    if NewSizeOfImage > AlignUp(Layout.SizeOfImage, Layout.SectionAlignment) then
      Exit(INJECT_NOT_A_PE); // a replace must never relocate the image
    for I := 0 to Layout.NumSections - 1 do
    begin
      SectionOff := Layout.SectionTable + I * SECTION_HEADER_SIZE;
      if SectionHeaderNameIs(@Image[SectionOff], EW_MAP_SECTION_NAME) then
      begin
        PLongword(@Image[SectionOff + 8])^ := NewVSz;
        PLongword(@Image[SectionOff + 16])^ := NewRawSz;
      end;
    end;
  end
  else
  begin
    // One more 40-byte header must fit inside the linker's header area (the
    // Delphi linker sizes it by FileAlignment and leaves slack). Without
    // slack, the whole header block is moved down into the linker slack it
    // followed; if even that cannot make room, the file stays untouched and
    // the caller reports code 7.
    HeaderOff := Layout.SectionTable + Layout.NumSections * SECTION_HEADER_SIZE;
    if Int64(HeaderOff) + Int64(SECTION_HEADER_SIZE) >
       Int64(Layout.SizeOfHeaders) then
    begin
      if not RelocateHeadersDown(Image, Layout, Relayout) then
        Exit(INJECT_NO_HEADER_ROOM);
      Layout := Relayout;
      HeaderOff := Layout.SectionTable + Layout.NumSections * SECTION_HEADER_SIZE;
    end;
    NewVSz := $10 + MapLen;
    NewVA := AlignUp(Layout.SizeOfImage, Layout.SectionAlignment);
    NewRawPtr := AlignUp(Length(Image), Layout.FileAlignment);
    NewRawSz := AlignUp(NewVSz, Layout.FileAlignment);
    NewSizeOfImage := AlignUp(NewVA + NewVSz, Layout.SectionAlignment);
    Move(EW_SEC_NAME, Image[HeaderOff], 8);
    PLongword(@Image[HeaderOff + 8])^ := NewVSz;   // VirtualSize
    PLongword(@Image[HeaderOff + 12])^ := NewVA;   // VirtualAddress
    PLongword(@Image[HeaderOff + 16])^ := NewRawSz; // SizeOfRawData
    PLongword(@Image[HeaderOff + 20])^ := NewRawPtr; // PointerToRawData
    PLongword(@Image[HeaderOff + 36])^ := EW_IMAGE_SECTION_CHARS;
    PWord(@Image[Layout.NumSectionsFileOffset])^ := Layout.NumSections + 1;
  end;
  if NewSizeOfImage <> Layout.SizeOfImage then
    PLongword(@Image[Layout.SizeOfImageFileOffset])^ := NewSizeOfImage;

  // Payload: 16-byte signature, the map bytes, FileAlignment padding. The
  // file ends at the payload: on replace the previous longer one is truncated.
  if Int64(Length(Image)) <> Int64(NewRawPtr) + Int64(NewRawSz) then
    SetLength(Image, NewRawPtr + NewRawSz);
  Move(SIGNATURE, Image[NewRawPtr], 16);
  Move(MapBytes[0], Image[NewRawPtr + 16], MapLen);
  try
    ImageStream := TFileStream.Create(APEFile, fmCreate);
    try
      ImageStream.WriteBuffer(Image[0], Length(Image));
    finally
      ImageStream.Free;
    end;
  except
    on E: Exception do
      Exit(INJECT_WRITE_FAILED);
  end;

  if ADeleteMap and (not DeleteFile(PChar(AMapFile))) then
    Exit(INJECT_MAP_DELETE_FAILED);
  Result := INJECT_OK;
end;

end.