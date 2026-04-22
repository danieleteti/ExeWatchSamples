@echo off
REM -----------------------------------------------------------------------------
REM Helper: activate MSVC x64 environment, build test_msvc.cpp, run it.
REM
REM Works if you installed Visual Studio 2022 Build Tools or the full IDE in a
REM default location. If you installed VS in a non-default path, change
REM VCVARS below.
REM -----------------------------------------------------------------------------

setlocal

set VCVARS="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% (
    echo Cannot find vcvars64.bat. Install Visual Studio 2022 Build Tools or
    echo edit run_msvc.cmd to point to your VS installation.
    exit /b 1
)

call %VCVARS% >nul || goto :fail
cd /d "%~dp0"

echo Compiling test_msvc.cpp ...
cl /EHsc /W4 /nologo test_msvc.cpp || goto :fail

echo.
echo Running test_msvc.exe ...
echo.
test_msvc.exe
exit /b %errorlevel%

:fail
echo Build or run failed.
exit /b 1
