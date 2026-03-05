# Quick Start

## Open

```
DelphiVCL/EWDelphiVCL.dproj
```

## API Key

In `MainFormU.pas`, find `FormCreate` and replace the API key:

```pascal
InitializeExeWatch('YOUR_API_KEY_HERE', '');
```

## Run

Press F9 in Delphi IDE.

## Test

Click buttons to:
- Send logs (Debug, Info, Warning, Error, Fatal)
- Measure timing of simulated operation
- Add breadcrumbs then trigger an error
- Set user identity
- Add tags
- Record metrics

View results in ExeWatch dashboard.
