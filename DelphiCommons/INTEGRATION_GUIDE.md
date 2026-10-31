# ExeWatch Delphi SDK - Integration Guide

Complete guide to integrating the ExeWatch Delphi SDK into your application.

## Table of Contents

1. [Requirements](#requirements)
2. [Basic Installation](#basic-installation)
3. [Initialization Flows](#initialization-flows)
4. [Device Info and Customer ID](#device-info-and-customer-id)
5. [Custom Device Info](#custom-device-info)
6. [Practical Scenarios](#practical-scenarios)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Requirements

### Compiler

- **Delphi XE8 or later** (32-bit and 64-bit, VCL and FMX targets).

### Operating System

- **Windows**: Windows Vista / Windows Server 2008 or later (x86 / x64).
  The SDK uses Win32 APIs introduced in Vista — notably `GetTickCount64` (linked
  statically) and `GetLogicalProcessorInformation`. Earlier versions
  (Windows XP, Server 2003, 2000) are **not supported**: the binary will fail
  to load with an "entry point not found in kernel32.dll" error.
- **Linux**: glibc-based distributions (the SDK targets `libc.so` directly for
  thread/process info).

### Network

- HTTPS to the configured `Endpoint` (default `https://api.exewatch.com`).
  The transport uses `System.Net.HttpClient` which requires the host to support
  TLS 1.2 or later. This is automatic on Vista+; legacy hosts without TLS 1.2
  cannot ship to the platform.

---

## Basic Installation

### 1. Copy the SDK file

Copy `ExeWatchSDKv1.pas` to your project folder or a shared library.

### 2. Add to uses clause

```pascal
uses
  ExeWatchSDKv1;  // Main SDK

// For VCL apps (Windows Desktop):
uses
  ExeWatchSDKv1, ExeWatchSDKv1.VCL;

// For FMX apps (Cross-platform):
uses
  ExeWatchSDKv1, ExeWatchSDKv1.FMX;
```

### 3. Initialize the SDK

```pascal
var
  Config: TExeWatchConfig;
begin
  Config := TExeWatchConfig.Create('YOUR_API_KEY', 'CUSTOMER_ID');
  Config.Endpoint := 'https://api.exewatch.com';  // Production
  // Config.Endpoint := 'http://localhost:8000';  // Local development

  InitializeExeWatch(Config);
end;
```

---

## Initialization Flows

The SDK supports **3 main initialization flows**, depending on your application's needs.

### Flow 1: Standard Initialization (with Customer ID)

**When to use:** When you know the `customer_id` at application startup.

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
begin
  // Customer ID known at startup
  Config := TExeWatchConfig.Create('ew_win_abc123...', 'ACME-Corp');
  Config.Endpoint := 'https://api.exewatch.com';
  InitializeExeWatch(Config);

  // Device info is sent AUTOMATICALLY at initialization
  EW.Info('Application started', 'startup');
end;
```

**What happens internally:**
1. ✅ SDK initializes with customer_id = `ACME-Corp`
2. ✅ Device info (hardware, OS, app version) is queued for sending
3. ✅ Device info is sent with first log batch
4. ✅ Flag `FDeviceInfoSent = True`

---

### Flow 2: Deferred Customer ID

**When to use:** When the `customer_id` is determined AFTER startup (e.g., after user login, license validation, etc.).

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
begin
  // Empty customer ID at startup
  Config := TExeWatchConfig.Create('ew_win_abc123...', '');
  Config.Endpoint := 'https://api.exewatch.com';
  InitializeExeWatch(Config);

  // You can log immediately (without customer_id)
  EW.Warning('No valid license found', 'license');
end;

procedure TMainForm.OnLicenseValidated(const CustomerName: string);
begin
  // After license validation, set customer_id
  EW.SetCustomerId(CustomerName);

  // From now on, all logs will have customer_id
  EW.Info('License validated for ' + CustomerName, 'license');
end;
```

**What happens internally:**
1. ✅ SDK initializes with customer_id = `''` (empty)
2. ✅ Device info is NOT sent (missing customer_id)
3. ✅ Logs are sent normally (even without customer_id)
4. ⏳ When you call `SetCustomerId('ACME-Corp')`:
   - Customer ID is set
   - Device info is queued and sent
   - `FDeviceInfoSent = True`

---

### Flow 3: Customer ID Change

**When to use:** When the customer changes during execution (e.g., logout/login with different user, license change).

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
begin
  Config := TExeWatchConfig.Create('ew_win_abc123...', 'CUSTOMER-A');
  InitializeExeWatch(Config);
  // Device info sent with customer_id = 'CUSTOMER-A'
end;

procedure TMainForm.OnUserSwitched(const NewCustomer: string);
begin
  // User switches from CUSTOMER-A to CUSTOMER-B
  EW.SetCustomerId(NewCustomer);

  // Device info is RE-SENT with the new customer_id
  EW.Info('User switched to ' + NewCustomer, 'auth');
end;
```

**What happens internally:**
1. ✅ SDK initializes with customer_id = `CUSTOMER-A`
2. ✅ Device info sent with `customer_id = CUSTOMER-A`
3. ⏳ When you call `SetCustomerId('CUSTOMER-B')`:
   - SDK **detects the change** (customer_id different from current)
   - Flag `FDeviceInfoSent = False` (reset)
   - Device info is **re-queued** and sent with `customer_id = CUSTOMER-B`
   - The device in the backend is **updated** with the new customer

**⚠️ Important note:** If you call `SetCustomerId` with the **same** customer_id already set, device info is NOT re-sent (no change).

---

## Device Info and Customer ID

### When is Device Info Sent?

Device info (hardware, OS, app version) is sent **automatically** in these cases:

| Scenario | Device Info Sent? | When? |
|----------|------------------|-------|
| `InitializeExeWatch` with customer_id | ✅ Yes | On first log batch |
| `InitializeExeWatch` with empty customer_id | ❌ No | Never (until you set customer_id) |
| `SetCustomerId` (first time) | ✅ Yes | On next batch |
| `SetCustomerId` (customer change) | ✅ Yes | On next batch (re-send) |
| `SetCustomerId` (same customer) | ❌ No | Already sent |

### Internal Flag: FDeviceInfoSent

The SDK uses an internal flag `FDeviceInfoSent` to track if device info has been sent:

```pascal
// SDK internal pseudo-code
procedure TExeWatch.SetCustomerId(const ACustomerId: string);
var
  CustomerIdChanged: Boolean;
begin
  // Detect if customer_id changed
  CustomerIdChanged := (FConfig.CustomerId <> ACustomerId) and
                       (FConfig.CustomerId <> '');

  FConfig.CustomerId := ACustomerId;

  if CustomerIdChanged then
  begin
    // Customer changed → re-send device info
    FDeviceInfoSent := False;
    QueueDeviceInfo;
  end
  else if not FDeviceInfoSent then
  begin
    // First time set → send
    QueueDeviceInfo;
  end;
end;
```

---

## Custom Device Info

The SDK allows you to send **custom information** along with device info (e.g., deployment environment, DB version, configuration).

### Available Methods

#### 1. InitialCustomDeviceInfo (Initial Setup)

Set custom info **before** `InitializeExeWatch` (sent together with device info):

```pascal
var
  Config: TExeWatchConfig;
  CustomInfo: TDictionary<string, string>;
begin
  Config := TExeWatchConfig.Create('ew_win_abc123...', 'CUSTOMER-ID');

  // Create dictionary with custom info
  CustomInfo := TDictionary<string, string>.Create;
  try
    CustomInfo.Add('environment', 'production');
    CustomInfo.Add('db_version', '5.2.1');
    CustomInfo.Add('license_type', 'enterprise');

    // Set BEFORE InitializeExeWatch
    Config.InitialCustomDeviceInfo :=
      reference to procedure(var Info: TDictionary<string, string>)
      begin
        for var Pair in CustomInfo do
          Info.Add(Pair.Key, Pair.Value);
      end;

    InitializeExeWatch(Config);
  finally
    CustomInfo.Free;
  end;
end;
```

#### 2. SetCustomDeviceInfo (Runtime)

Set/update custom info **after** `InitializeExeWatch`:

```pascal
// Set custom info at runtime
EW.SetCustomDeviceInfo('environment', 'staging');
EW.SetCustomDeviceInfo('feature_flags', 'new_ui,beta_mode');

// Changes are sent on next batch
```

#### 3. SendCustomDeviceInfo (Immediate Send)

**⚠️ DEPRECATED** - Use `SetCustomDeviceInfo` instead. This method sends immediately, but is discouraged as it bypasses the batching mechanism.

### Custom Info: Merge vs Replace

**Backend behavior:**
- Custom info is **REPLACED** (not merged)
- If you send `{}` (empty dictionary), custom info is **deleted**
- This allows you to "clear" custom info when no longer needed

```pascal
// Example: Clear custom info
var
  EmptyInfo: TDictionary<string, string>;
begin
  EmptyInfo := TDictionary<string, string>.Create;
  try
    // Send empty dictionary → deletes custom info on backend
    Config.InitialCustomDeviceInfo :=
      reference to procedure(var Info: TDictionary<string, string>)
      begin
        // Info remains empty
      end;
    // Device info sent with custom_device_info = {}
  finally
    EmptyInfo.Free;
  end;
end;
```

---

## Practical Scenarios

### Scenario 1: Multi-Tenant Application (Desktop SaaS)

**Suppose** you have a multi-tenant desktop application where the `customer_id` is determined after user login.

```pascal
unit MainForm;

var
  FCurrentCustomer: string = '';

procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
begin
  // Initialize SDK WITHOUT customer_id
  Config := TExeWatchConfig.Create('ew_win_abc123...', '');
  Config.Endpoint := 'https://api.exewatch.com';
  InitializeExeWatch(Config);

  // Log without customer_id (user not logged in yet)
  EW.Info('Application started - waiting for login', 'startup');
end;

procedure TMainForm.OnLoginSuccess(const Username, Company: string);
begin
  // After login, set customer_id
  FCurrentCustomer := Company;
  EW.SetCustomerId(FCurrentCustomer);

  // From now on, all logs have customer_id
  EW.Info('User logged in: ' + Username, 'auth');
end;

procedure TMainForm.OnLogout;
begin
  EW.Info('User logged out: ' + FCurrentCustomer, 'auth');

  // You can reset customer_id (optional)
  // EW.SetCustomerId('');
end;
```

---

### Scenario 2: Application with Custom Deployment Environment Info

**Suppose** you want to track information about the deployment environment (production, staging, dev) and database version.

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TExeWatchConfig;
  DBVersion: string;
  Environment: string;
begin
  // Read configuration from file/registry
  Environment := ReadEnvironmentFromConfig;  // 'production', 'staging', etc.
  DBVersion := GetDatabaseVersion;           // '5.2.1'

  Config := TExeWatchConfig.Create('ew_win_abc123...', 'CUSTOMER-ID');

  // Add custom info
  Config.InitialCustomDeviceInfo :=
    reference to procedure(var Info: TDictionary<string, string>)
    begin
      Info.Add('environment', Environment);
      Info.Add('db_version', DBVersion);
      Info.Add('deployment_region', 'EU-West');
    end;

  InitializeExeWatch(Config);

  EW.Info('Application started in ' + Environment, 'startup');
end;
```

**Backend display:**
In the device modal you'll see:

```
Custom Device Info
  environment: production
  db_version: 5.2.1
  deployment_region: EU-West
  Updated: 2026-02-11 10:30:00 UTC
```

---

### Scenario 3: Runtime License Change

**Suppose** you have an application that allows the user to change license/customer during execution.

```pascal
procedure TMainForm.OnLicenseChanged(const OldLicense, NewLicense: string);
begin
  EW.Info('License changing from ' + OldLicense + ' to ' + NewLicense, 'license');

  // Change customer_id → device info is re-sent
  EW.SetCustomerId(NewLicense);

  // Also update custom info if needed
  EW.SetCustomDeviceInfo('license_type', GetLicenseType(NewLicense));

  EW.Info('License changed successfully', 'license');
end;
```

**What happens:**
1. Device info is re-sent with new `customer_id = NewLicense`
2. In the backend, the device is **moved** from old customer to new one
3. Custom info is updated

---

## Best Practices

### ✅ DO

1. **Use meaningful customer IDs**
   ```pascal
   // ✅ GOOD
   EW.SetCustomerId('ACME-Corp');
   EW.SetCustomerId('Customer-12345');

   // ❌ BAD
   EW.SetCustomerId('user123');  // Too generic
   ```

2. **Set customer_id as early as possible**
   ```pascal
   // ✅ GOOD - Set right after login
   procedure OnLoginSuccess(const Company: string);
   begin
     EW.SetCustomerId(Company);
   end;
   ```

3. **Use custom info for useful metadata**
   ```pascal
   // ✅ GOOD
   EW.SetCustomDeviceInfo('environment', 'production');
   EW.SetCustomDeviceInfo('feature_flags', 'beta_ui,new_reports');
   ```

4. **Log important customer-related events**
   ```pascal
   // ✅ GOOD
   EW.Info('License validated for ' + CustomerName, 'license');
   EW.SetCustomerId(CustomerName);
   ```

### ❌ DON'T

1. **Don't change customer_id too often**
   ```pascal
   // ❌ BAD - Device info re-sent every call!
   for I := 1 to 100 do
     EW.SetCustomerId('Customer-' + IntToStr(I));
   ```

2. **Don't use sensitive data in custom info**
   ```pascal
   // ❌ BAD - Sensitive data exposed
   EW.SetCustomDeviceInfo('password', UserPassword);
   EW.SetCustomDeviceInfo('credit_card', CardNumber);
   ```

3. **Don't use SendCustomDeviceInfo in loops**
   ```pascal
   // ❌ BAD - Too many HTTP requests
   for var Key in ConfigKeys do
     EW.SendCustomDeviceInfo(Key, GetValue(Key));  // AVOID!

   // ✅ GOOD - Use SetCustomDeviceInfo (batching)
   for var Key in ConfigKeys do
     EW.SetCustomDeviceInfo(Key, GetValue(Key));
   ```

---

## Troubleshooting

### Device info not sent

**Problem:** Device info doesn't appear in backend.

**Possible causes:**
1. Empty customer ID at initialization
   ```pascal
   // ❌ Device info NOT sent
   Config := TExeWatchConfig.Create('API_KEY', '');
   InitializeExeWatch(Config);
   ```

   **Solution:** Set customer_id afterwards:
   ```pascal
   EW.SetCustomerId('CUSTOMER-ID');
   ```

2. Invalid API key
   ```pascal
   // ❌ Backend rejects request
   Config := TExeWatchConfig.Create('wrong_key', 'CUSTOMER');
   ```

   **Solution:** Verify API key in backend (API Keys page).

### Device info missing hardware info

**Problem:** Device info sent but missing RAM, CPU, etc.

**Possible cause:** Custom device info overwrites hardware info (old SDK bug, now fixed).

**Solution:** Update SDK to latest version (v0.15.0+).

### Customer ID not updating

**Problem:** Changed `SetCustomerId` but device remains on old customer.

**Possible cause:** Backend didn't receive updated device info.

**Debug:**
```pascal
// Enable SDK internal logs
EW.SetCustomerId('NEW-CUSTOMER');
// Check log file at %LOCALAPPDATA%\ExeWatch\exewatch_internal.log
```

---


## Stack trace symbols: the .map beside the executable (default)

The SDK translates trace addresses into unit/function/line from the Borland
map. It reads, in order: the map linked INTO the binary (the `.ewmap` section
the injectors write; a legacy `EXEWATCH_MAP` resource is read too), then a
plain `.map` file beside it, then export names, then `module+0x...`.

**Default setup (zero extra steps): enable the detailed map.**

1. Project Options > Compiling > Linking > Map file = *Full/Detailed* (dcc
   flag `-GD` from the command line).
2. Ship the produced `.exe.map` beside the executable. That is the whole
   setup: the SDK reads it from disk the first time it needs to resolve.

Optional (release polish, never required): link the map INSIDE the binary
instead of shipping it as a file:
- in the IDE: open `Tools/ExeWatchMapExpert/ExeWatchMapExpert.dproj`.
  The IDE compiles it directly. One rule, the same for any design package:
  while the package is loaded in the IDE (it is, as long as it sits in
  Component > Install Packages), the linker cannot rewrite its own .bpl and
  refuses with a clear message - so the update cycle is REMOVE, BUILD, ADD:
  1. Component > Install Packages: untick/remove 'ExeWatch map linker';
  2. Project > Build the package;
  3. Component > Install Packages > Add: the freshly built .bpl.
  The expert (XE8+... 32-bit IDE) injects in-process; it forces the map
  option to Detailed and links the map at the end of every build, ONLY for
  projects that use the ExeWatch SDK, silent elsewhere. Per-project toggle:
  right-click the project in the Project Manager -> 'ExeWatch: map link
  enabled'/'disabled'; the state is saved in the .dproj, default is
  ENABLED; a comment in the .dpr (`// EXEWATCH MAP LINK: OFF`) disables it
  too;
- on a pipeline or from the command line (also what an AI agent uses):
  compile `Tools/ExeWatchMapCLI.dpr` once and run
  `ExeWatchMapCLI.exe <binary> <binary>.map [/delete-map]`
  (exit 0 ok, 2 file missing, 3 map empty, 4 write failure, 5 map delete
  failed, 6 not a valid PE, 7 no room for the map section). The first stdout
  line is machine-readable: `RESULT=INJECTED symbols=N pe=...` or
  `RESULT=FAILED code=N reason=...`.

Notes: inject **before** Authenticode signing (the appended section
invalidates an existing signature); the binary grows by the size of the map;
the embedded map wins over the side file.

## References

- **SDK Version:** v0.15.0+
- **API Version:** v1
- **Backend:** ExeWatch >= 1.5.0

For further questions: support@exewatch.com
