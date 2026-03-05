# .NET Windows Service Sample — Quick Start

1. Open `DotNetWindowsService.csproj` in Visual Studio 2022 or later
2. Replace `ew_win_YOUR_API_KEY_HERE` in `Worker.cs` with your API key
3. Press F5 to run as a console app (for development)
4. To install as a Windows Service: `sc create ExeWatchDemo binPath="C:\path\to\DotNetWindowsService.exe"`
5. Check the ExeWatch dashboard to see logs, timings, and metrics
