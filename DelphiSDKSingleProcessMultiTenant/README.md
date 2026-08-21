# Single Process, Multiple Tenants (DelphiMVCFramework)

> **Question:** *My server serves several customers from one process, and every request belongs to a different one. How do I make sure each request is logged against the right customer? And how do I keep ten copies of the server on one machine from fighting over the same queue?*

A DMVCFramework API: one process, one API key, three tenants, and a pool of request threads where no thread owns a tenant.

## The three rules

**One `TExeWatch` per tenant.** The ingest payload carries `customer_id` and `device` once per batch, not once per event, so a single instance cannot attribute different events to different tenants. Calling `SetCustomerId` per request would also re-tag whatever is still sitting in the buffer, which under concurrent requests is a race.

**One `StoragePath` per instance.** By default the SDK derives the queue directory from the API key alone. Every tenant here shares one key, so the default would drop all of them into the same folder, where their shipper threads compete for the same queue files and each newly created instance runs its startup crash-recovery pass over files its siblings are still sending.

**The tenant list is fixed at startup.** Each instance costs a shipper thread, a queue directory and a device record. A registry that created one on demand would let whoever can set a header decide how many threads the process runs. The tenants a server serves are known from its configuration; anything else is a 400.

## How the tenant reaches the code

The tenant is a property of the request, so it travels in the request context and nothing is stored per thread. `TWebContext.Data` is a `TMVCStringDictionary` that dies with the request, which is exactly the lifetime wanted.

```pascal
procedure TExeWatchTenantMiddleware.OnBeforeRouting(AContext: TWebContext;
  var AHandled: Boolean);
begin
  TenantId := AContext.Request.Headers[TENANT_HEADER];

  if not FLoggers.IsKnownTenant(TenantId) then    // refuse before anything allocates
  begin
    AContext.Response.StatusCode := HTTP_STATUS.BadRequest;
    AHandled := True;
    Exit;
  end;

  AContext.Data[CTX_TENANT_ID] := TenantId;
  FLoggers.ForTenant(TenantId).ClearBreadcrumbs;   // the thread came from the pool
end;
```

The controller base class reads it back and holds nothing:

```pascal
function TTenantController.EW: TExeWatch;
begin
  Result := GLoggers.ForTenant(TenantOf(Context));
end;
```

From there the action code is identical to a single-tenant app. It never asks which customer it is serving:

```pascal
function TOrdersController.GetAll: TObjectList<TOrder>;
begin
  EW.AddBreadcrumb('Listing orders', 'orders');
  EW.StartTiming('orders.list', 'orders');
  try
    ...
  finally
    EW.EndTiming('orders.list');   // a timing left open is inherited by the
  end;                             // next request this thread serves
  EW.Info(Format('Listed %d orders', [Result.Count]), 'orders');
end;
```

## Pooled threads need per-request hygiene

Breadcrumbs and timings are kept per thread, and a server thread serves one request after another. Two consequences, both handled above:

- Breadcrumbs are only cleared when an error consumes them, so a request that ended without an error leaves its trail on the thread. Clear them when the request starts.
- A timing that is never ended stays on the thread. End it in a `finally`.

Neither is a cross-tenant leak, because each tenant has its own instance and therefore its own per-thread dictionaries. It is a cross-request leak inside one tenant, which is quiet enough to survive a long time unnoticed.

## Where this design stops

It fits a process serving a handful to a few dozen tenants. It does not fit thousands, because the cost per tenant is a thread, a queue directory and a device record.

Above that range there is no good answer with the ingest API as it stands, only a trade: run one instance for the whole server, with `customer_id` set to the deployment and the tenant carried per event in `extra_data`. One thread, one queue, and no customer dimension, which means no per-customer dashboards and no per-customer devices. Attributing individual events to customers would need `customer_id` to move from the batch onto the event, a change to the platform rather than something to work around in integration code.

## Prerequisites

- Embarcadero Delphi 12 (the `.dproj` targets Delphi 12).
- [DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework), with the `DMVC` IDE environment variable pointing at its `sources` folder, the same setup the `DelphiDMVCFramework` sample uses.
- An ExeWatch API key ([get one here](https://exewatch.com)).

## How to run

1. Open `EWMultiTenantAPI.dproj` in Delphi.
2. Replace the `EXEWATCH_API_KEY` constant in `EWMultiTenantAPI.dpr` with your real key,
   or set an `EXEWATCH_API_KEY` environment variable, which wins over the constant. The
   environment is the safer habit: a key typed into the source is a key that gets committed.
3. Build and run, or from a console: `EWMultiTenantAPI.exe inst01 8080`.

```bash
curl -H "X-Tenant-Id: ACME-Corp"     http://localhost:8080/orders
curl -H "X-Tenant-Id: Northwind-Ltd" http://localhost:8080/orders/7
curl -H "X-Tenant-Id: Globex-SA"     http://localhost:8080/orders/broken
curl -H "X-Tenant-Id: nope"          http://localhost:8080/orders     # 400
curl                                 http://localhost:8080/orders     # 400
```

On the dashboard, switch between customers. Each one shows only its own requests and its own timings, and the failure appears under Globex-SA alone, carrying the breadcrumb of the request that failed and not the one before it.

Run a second copy to see two installed instances stay apart:

```
EWMultiTenantAPI.exe inst02 8081
```

```
C:\ProgramData\ExeWatchSamples\MultiTenantAPI\
├── inst01\
│   ├── ACME-Corp\        20260821_110048789_...ewlog
│   ├── Globex-SA\
│   └── Northwind-Ltd\
└── inst02\
    └── ...
```

With the placeholder key still in place the server runs and the events stay queued on disk, which is worth watching once on its own: nothing is lost, and the queue is retried on the next start.

## Details worth copying

**DeviceId.** The default is `username@hostname`, so every copy of a server under the same account would report as one device. The sample sets `Cfg.DeviceInfo.DeviceId` from the instance name. Note the unit: the useful one is the process, not the tenant. All tenants inside a process share a DeviceId and are told apart by their customer id.

**Where the queues live.** Servers often run as LocalSystem or under a shared service account, where the SDK default (`%LOCALAPPDATA%`) resolves to the same directory for every copy. The sample puts them under `%ProgramData%`.

**Resolving the tenant.** A header keeps the sample runnable with curl. Real deployments read a JWT claim or the subdomain, and everything downstream is the same.

**Public routes.** This middleware demands the header on every request. A real service exempts health checks and static files before the check.

**Draining on shutdown.** Freeing a `TExeWatch` shuts it down and makes one send attempt. `FlushAll` waits instead, and its timeout is the budget for the whole shutdown rather than per tenant. That distinction is not academic: with the queue unable to ship, a per-tenant timeout of 20 seconds took 60 seconds to stop a three-tenant server, and a service manager kills a process that stops that slowly. Tenants past the budget still get their buffer written to disk, so nothing is lost, it is retried on the next start.

## File layout

```
DelphiSDKSingleProcessMultiTenant/
├── EWMultiTenantAPI.dpr       Indy Direct bootstrap, engine config, exception handler
├── EWMultiTenantAPI.dproj     Project file (Win32 + Win64)
├── TenantLoggersU.pas         TTenantLoggers, one TExeWatch per tenant
├── ExeWatchTenantU.pas        Middleware + TTenantController base class
├── Controllers.OrdersU.pas    The demo API
└── README.md                  This file
```
