@echo off
rem Builds ExeWatchMapExpert.bpl for both RAD Studio versions and places the
rem result in the IDE's public Bpl/Dcp directories, ready for
rem "Component -> Install Packages -> Add".
rem
rem Rad Studio design packages are NOT rebuilt inside the IDE (the loaded
rem .bpl keeps the output file locked): build here, install from the result.

cd /d "%~dp0"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild ExeWatchMapExpert.dproj /t:Build /p:Config=Release /p:Platform=Win32 /nologo /v:m ^
  /p:DCC_BplOutput="C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl" ^
  /p:DCC_DcpOutput="C:\Users\Public\Documents\Embarcadero\Studio\23.0\Dcp" || goto :fail

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild ExeWatchMapExpert.dproj /t:Build /p:Config=Release /p:Platform=Win32 /nologo /v:m ^
  /p:DCC_BplOutput="C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl" ^
  /p:DCC_DcpOutput="C:\Users\Public\Documents\Embarcadero\Studio\37.0\Dcp" || goto :fail

echo.
echo DONE: install Component - Install Packages - Add on
echo   23.0\Bpl\ExeWatchMapExpert.bpl  (Delphi 12)
echo   37.0\Bpl\ExeWatchMapExpert.bpl  (Delphi 13)
exit /b 0

:fail
echo BUILD FAILED ^(close every RAD Studio first^)
exit /b 1