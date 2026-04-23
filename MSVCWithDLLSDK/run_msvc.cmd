@echo off
REM -----------------------------------------------------------------------------
REM ExeWatch DLL SDK -- MSVC sample build + run script.
REM
REM Auto-activates vcvars64 (64-bit MSVC), compiles main.cpp together with the
REM shared dynamic-loader (..\DLLSDKCommons\ExeWatchSDKv1.dynload.c), and
REM runs the resulting main.exe.
REM -----------------------------------------------------------------------------

setlocal

REM Force English (1033) output from cl.exe regardless of the user's locale.
set VSLANG=1033

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

echo Compiling main.cpp + ExeWatchSDKv1.dynload.c ...
cl /EHsc /W4 /nologo /I..\DLLSDKCommons main.cpp ..\DLLSDKCommons\ExeWatchSDKv1.dynload.c || goto :fail

echo.
echo Running main.exe ...
echo.
".\main.exe"
exit /b %errorlevel%

:fail
echo Build or run failed.
exit /b 1
