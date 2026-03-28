# ExeWatch + Runtime Packages (LoadPackage) Demo

This sample demonstrates that **ExeWatch works seamlessly with Delphi runtime packages** loaded dynamically via `LoadPackage`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  HostApp.exe (main application)                         │
│  - Initializes ExeWatch (API key, user, tags)           │
│  - Loads modules on demand via LoadPackage               │
│  - All modules share the same EW session                │
├─────────────────────────────────────────────────────────┤
│  ExeWatchSDKPkg.bpl (shared runtime package)            │
│  - Contains ExeWatchSDKv1.pas + VCL hook                │
│  - Contains ModuleRegistryU.pas (form registration)     │
│  - Global EW instance is shared across all BPLs         │
├──────────────────────┬──────────────────────────────────┤
│  ModuleCustomers.bpl │  ModuleOrders.bpl                │
│  - Customer form     │  - Orders form                   │
│  - Logging, metrics  │  - Timing, gauges, breadcrumbs   │
│  - Error capture     │  - Slow query simulation         │
└──────────────────────┴──────────────────────────────────┘
```

**Key principle:** The ExeWatch SDK is compiled into its own package (`ExeWatchSDKPkg.bpl`). This ensures that the global `EW` instance is shared across the host application and all dynamically loaded module packages. Without this, each BPL would have its own copy of the SDK globals.

## Build Instructions

### Open the Project Group

1. Open `VCLWithPackages.groupproj` in Delphi IDE
2. All 4 projects are listed with correct build order

### Configure Output Directories

Set the **same output directory** for all projects (BPLs + EXE must be in the same folder):

1. Right-click each project > **Options** > **Delphi Compiler** > **Output directory**
2. Set to: `.\bin` (or any shared folder)
3. For packages, also set **DCP output directory** to: `.\bin`

### Configure HostApp for Runtime Packages

1. Right-click **HostApp** > **Options** > **Packages**
2. Check **"Build with runtime packages"**
3. In the **Runtime packages** field, add: `ExeWatchSDKPkg`

   > This tells the linker to use ExeWatchSDKPkg.bpl at runtime instead of statically linking the SDK.

### Build Order

Build in this exact order (or use **Build All** from the project group):

1. **ExeWatchSDKPkg.dpk** — the SDK wrapper package (build first!)
2. **ModuleCustomers.dpk** — customer management module
3. **ModuleOrders.dpk** — order management module
4. **HostApp.dpr** — the main application (build last)

### Set Your API Key

Open `MainFormU.pas` and set the constants at the top of the file:

```pascal
const
  APP_API_KEY     = 'ew_win_YOUR_API_KEY_HERE';   // ← your ExeWatch API Key
  APP_CUSTOMER_ID = 'DEMO-CUSTOMER-001';           // ← your Customer ID
```

Get your API Key from [exewatch.com](https://exewatch.com) after creating an application.

### Run

1. Make sure all `.bpl` files are in the same folder as `HostApp.exe`
2. Run `HostApp.exe`
3. Click **Connect** (API Key is configured as a constant in the code)
4. Click **Load Customers Module** / **Load Orders Module**
5. Select a module and click **Show Module Form**
6. Use the module forms — all logging goes through ExeWatch!

## How It Works

### Shared SDK via Package

```
ExeWatchSDKPkg.dpk contains:
  - ExeWatchSDKv1.pas       → global EW instance
  - ExeWatchSDKv1.VCL.pas   → VCL exception hook
  - ModuleRegistryU.pas     → module form registry
```

Because all modules `require ExeWatchSDKPkg`, they all link to the **same** BPL at runtime. This means:

- `EW` is the same object everywhere
- `ExeWatchIsInitialized` returns the same value
- Breadcrumbs, tags, user identity are shared
- All logs go to the same ExeWatch session

### Module Registration Pattern

Each module package registers its form in its `initialization` section:

```pascal
// In CustomersFormU.pas (inside ModuleCustomers.bpl)
initialization
  RegisterModule('Customers', 'Customer management module', TCustomersForm);
```

The host application queries the registry after `LoadPackage`:

```pascal
// In MainFormU.pas (HostApp.exe)
LoadPackage('ModuleCustomers.bpl');
// → runs initialization → form is registered
Modules := GetRegisteredModules;
// → now contains TCustomersForm
```

### Using ExeWatch from a Package

Code inside a package uses ExeWatch exactly the same way as in a regular application:

```pascal
// This code runs inside a BPL - same API, no changes needed!
EW.Info('Customer added: ' + CustomerName, 'customers');
EW.AddBreadcrumb(btClick, 'customers', 'Added customer');
EW.IncrementCounter('customers.added', 1.0, 'customers');
EW.StartTiming('customer.search', 'customers');
// ... do work ...
EW.EndTiming('customer.search');
```

## ExeWatch Features Demonstrated

| Feature | Where |
|---------|-------|
| Logging (all levels) | Customers module: add/remove/search |
| Exception capture | Customers module: "Simulate Error" button |
| Timing/Profiling | Orders module: create order, process order |
| Breadcrumbs | Both modules: form open/close, button clicks |
| Counters | Both modules: operation counts |
| Gauges | Orders module: query time measurement |
| Device Info | Host app: sent at connect |
| User Identity | Host app: set at connect, shared with all modules |
| Global Tags | Host app: `environment=demo`, `app_type=runtime_packages` |

## File Structure

```
VCLWithPackages/
├── VCLWithPackages.groupproj    ← Open this in Delphi IDE
├── ExeWatchSDKPkg.dpk           ← SDK runtime package
├── ModuleCustomers.dpk          ← Customer module package
├── ModuleOrders.dpk             ← Orders module package
├── HostApp.dpr                  ← Main application
├── MainFormU.pas / .dfm         ← Host main form
├── CustomersFormU.pas / .dfm    ← Customer form (in package)
├── OrdersFormU.pas / .dfm       ← Orders form (in package)
├── ModuleRegistryU.pas          ← Module registry (in SDK package)
└── README.md                    ← This file
```

## Troubleshooting

**"Cannot load ModuleCustomers.bpl"**
- Make sure all BPLs are in the same folder as the EXE
- Build ExeWatchSDKPkg **first** (module packages depend on it)

**"Unit X was compiled with a different version"**
- Rebuild all packages and the host app from scratch (Build All)
- Make sure all projects target the same platform (Win32 or Win64)

**"Duplicate unit" errors**
- Make sure HostApp has "Build with runtime packages" enabled
- The SDK units must come from ExeWatchSDKPkg.bpl, not be compiled directly into the EXE

**ExeWatch logs not appearing from modules**
- Verify `ExeWatchIsInitialized` returns True (connect before loading modules)
- Confirm ExeWatchSDKPkg.bpl is loaded (it should be, since HostApp requires it)
