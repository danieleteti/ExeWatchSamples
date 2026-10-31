# Stack trace behaviour per compiler / linker configuration

Verified 2026-10-31 on Delphi 12 (Studio 23.0) and Delphi 13 (Studio 37.0),
Win32 + Win64, on a real host linked with the SDK: **32 builds** (8 flag
combinations × both compilers × both platforms), each compiled, injected by
`ExeWatchMapCLI` (where a map exists) and executed, with the trace checked
at run time. The same runtime suite (`ExeWatchSDKTests.dpr`, 59 tests with
the backend up) passes on both compilers.

**Every combination builds, runs and produces a trace. Nothing breaks when
the user changes linker or compiler settings.** The differences below are
only about what the trace can RESOLVE.

**Installing the linkers is optional.** Without them the SDK still ships a
trace: it reads a plain `.map` left beside the executable by the linker
(detail map = names + lines; publics map = names; none at all = module+offset
and PE export names). An executable produced without a map keeps working and
keeps tracing; adding a map later (or linking it in) only makes the trace
more precise. This no-tool path is what the runtime suite exercises
throughout (the suite binary itself is not injected: every trace it resolves
comes from the `.map` beside it), and the mapless path is exercised by the
`no-map` matrix builds.

## What the trace resolves to, per linker map setting

| Map file setting (`Project Options > Compiling > Linking > Map file`) | dcc flag | Trace content |
|---|---|---|
| Full/Detailed | `-GD` | `unit!function (line N)` for every symbol; the embedded map wins over the `.map` beside the exe |
| Publics only | `-GP` | symbol names (`unit!function`), **no line numbers** (the map does not carry the line table) |
| Segments only | `-GS` | no publics exist: the tool injects but the table stays empty; trace = module+offset + PE export names |
| None | – | no injection (the tool refuses with exit 2, no map produced); trace = module+offset + PE export names, e.g. `ntdll.dll+0x600` or `ntdll.dll!RtlGetVersion` |

The map is read from the `.ewmap` PE section the injectors write; the legacy
`EXEWATCH_MAP` RCDATA resource still wins if some other tooling produced it,
and the plain `.map` beside the executable backs both up.

## Compiler settings: what changes for the Win32 stack walk

| Setting | Effect on the trace |
|---|---|
| Stack frames `{$W+}` (Debug config enables it) | complete EBP chains on Win32 |
| Stack frames `{$W-}` (dcc command line default) | frameless procs break the EBP chain: the walk **truncates** at the first frameless caller; the trace stays correct and never lies (frames below are simply not recorded). Win64 uses `RtlCaptureStackBackTrace` and is unaffected |
| Optimization / range / overflow / I/O checks | no effect observed on capture or resolution |
| Runtime packages (`-LUrtl`) | smaller map, everything resolves as above |
| Debug info off (`-$D- -$L- -$Y-`) | trace unchanged; only `.pdb`-style data changes |

## Injection behaviour per executable shape (verified)

| Shape | Result |
|---|---|
| Simple executable (resource section last) | map appended as the `.ewmap` section, `SizeOfImage` patched; loads and runs |
| VCL/FMX shape: `.reloc`/`.pdata`/`.debug` AFTER `.rsrc` in raw order (every x64 Debug linker output), or header slack shorter than 40 bytes | the header block is relocated into the linker slack (e_lfanew updated, security directory adjusted), then injected; verified loading with `LoadLibrary` |
| Header block cannot relocate either (~18+ sections in a 0x400-header image) | refused with **exit 7** ("no header room"); nothing written; the runtime falls back to the `.map` beside the exe |
| Not a PE | refused with **exit 6**, untouched |
| Already injected (re-run) | replaced in place; file truncated to the new payload; byte-identical map → idempotent |
| Signed binaries | inject BEFORE Authenticode signing (the appended section invalidates the signature), as documented |

The NT loader requires every page inside `SizeOfImage` to belong to a
section: the injector always appends contiguously so it never creates page
holes. Growing the resource section through the OS resource API instead
*has been observed destroying the DOS header* of executables whose resource
section is not last — that is why the map travels as its own section.

## What each trace line is, in order

1. top = the raising function (or the first caller with a frame on Win32);
2. the SDK/RTL raise machinery is filtered by unit name, so no internal
   frames surface and source edits cannot change the filter's coverage;
3. frames from other modules resolve against THEIR module: exports first,
   then `module+0xN`, never against the host map;
4. `GetNoStackTraceReason` explains a missing trace: 1 = capture
   unavailable (x64), 2 = the host module has no usable symbols, 3 = empty
   capture.