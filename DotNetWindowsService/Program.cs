using DotNetWindowsService;

// ============================================================
// ExeWatch .NET SDK — Windows Service Sample
// ============================================================
//
// This sample demonstrates how to integrate ExeWatch into a
// .NET Worker Service that can run as a Windows Service.
//
// To install as a Windows Service:
//   sc create ExeWatchDemo binPath="C:\path\to\DotNetWindowsService.exe"
//   sc start ExeWatchDemo
//
// To run as a console app (for development):
//   dotnet run
//
// ============================================================

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "ExeWatch Demo Service";
});

builder.Services.AddHostedService<Worker>();
var host = builder.Build();
host.Run();
