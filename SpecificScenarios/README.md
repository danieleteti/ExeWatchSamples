# Specific Scenarios — HowTo

This folder contains focused examples that solve **specific integration questions** customers encounter when using the ExeWatch SDK. Each subfolder is a self-contained Delphi VCL project you can open, build, and run.

## Prerequisites

- Delphi 12.3+ (Embarcadero RAD Studio)
- An ExeWatch API key ([get one here](https://exewatch.com))
- Replace the `EXEWATCH_API_KEY` constant in each sample's `MainFormU.pas`

## Scenarios

| Folder                                              | Question                                                     |
| --------------------------------------------------- | ------------------------------------------------------------ |
| [InitialCustomDeviceInfo](InitialCustomDeviceInfo/) | How do I attach tags and environment info (RDP, Terminal Server, desktop mode) to the **first log event** and device info at startup? |
| [madExceptIntegration](madExceptIntegration/)       | I already use **madExcept**. How do I forward intercepted exceptions to ExeWatch with madExcept's resolved stack (unit names + line numbers) instead of the SDK's raw capture? |

---

## How to use a sample

1. Open the `.dproj` file in Delphi
2. Set your API key in `MainFormU.pas`
3. Build and run (F9)
4. Check the ExeWatch dashboard — the data appears immediately

## SDK files

All samples reference the SDK from `../DelphiCommons/`. Make sure those files are present (they ship with this repository).
