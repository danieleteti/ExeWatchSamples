unit EWMapSplash;

{
  The ExeWatch footprint in the RAD Studio splash and about box. The
  registration pattern is the one every IDE expert ships: a 48x48 transparent
  PNG compiled from ExeWatchSplash.rc into the package's RCDATA, drawn onto
  the splash at startup and listed in Help > About.

  The resource line for the PNG (the rc-with-source form) lives in the .dpk
  so the IDE's build compiles the image with the package.
}

interface

{$R ExeWatchSplash.res}

uses
  Winapi.Windows;

procedure Register;

implementation

uses
  ToolsAPI, System.SysUtils, System.Classes,
  Vcl.Dialogs, Vcl.Imaging.PngImage, Vcl.Graphics;

const
  RCDATA_NAME = 'EXEWATCHSPLASH48PNG';

  // Same version the SDK unit of the same release ships with.
  EW_TOOLS_VERSION = '0.25.0';

var
  AboutPluginIndex: Integer = 0;
  AboutBoxServices: IOTAAboutBoxServices = nil;

resourcestring
  TitleText = 'ExeWatch Map Linker v' + EW_TOOLS_VERSION;
  DescriptionText = 'Links the compiler map into Delphi binaries at build end.';
  LicenseText = 'Licensed exclusively to registered users of the ExeWatch platform (exewatch.com)';

function CreateBitmapFromPngRes: Vcl.Graphics.TBitmap;
var
  PngImage: TPngImage;
  ResStream: TResourceStream;
begin
  PngImage := nil;
  try
    Result := Vcl.Graphics.TBitmap.Create;
    PngImage := TPngImage.Create;
    ResStream := TResourceStream.Create(HInstance, RCDATA_NAME, RT_RCDATA);
    try
      PngImage.LoadFromStream(ResStream);
      Result.Assign(PngImage);
    finally
      ResStream.Free;
    end;
  finally
    PngImage.Free;
  end;
end;

procedure RegisterAboutBox;
var
  Bitmap: Vcl.Graphics.TBitmap;
begin
  if not Supports(BorlandIDEServices, IOTAAboutBoxServices, AboutBoxServices) then
    Exit;
  Bitmap := CreateBitmapFromPngRes;
  try
    AboutPluginIndex := AboutBoxServices.AddPluginInfo(
      TitleText,
      DescriptionText + sLineBreak + 'ExeWatch Map Linker Team',
      Bitmap.Handle, False, LicenseText);
  finally
    Bitmap.Free;
  end;
end;

procedure UnregisterAboutBox;
begin
  if (AboutPluginIndex <> 0) and (AboutBoxServices <> nil) then
  begin
    AboutBoxServices.RemovePluginInfo(AboutPluginIndex);
    AboutPluginIndex := 0;
    AboutBoxServices := nil;
  end;
end;

procedure Register;
var
  Bitmap: Vcl.Graphics.TBitmap;
begin
  Bitmap := CreateBitmapFromPngRes;
  try
    SplashScreenServices.AddPluginBitmap(TitleText, Bitmap.Handle, False,
      LicenseText, '');
  finally
    Bitmap.Free;
  end;
end;

initialization
  RegisterAboutBox;

finalization
  UnregisterAboutBox;

end.
