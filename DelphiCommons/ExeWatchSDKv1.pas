{ *******************************************************************************
  ExeWatch SDK for Delphi

  A lightweight SDK to send logs from Delphi applications to ExeWatch.

  Requirements:
  - Compiler: Delphi XE8 or later (32-bit and 64-bit)
  - Windows: Vista / Server 2008 or later (uses GetTickCount64 etc.)
  - Linux: glibc-based distributions

  Features:
  - Persistent log storage (logs are saved to disk before sending)
  - Automatic retry on failure
  - Log shipping: old logs are sent before new ones
  - Crash-safe: logs survive application crashes
  - Automatic unhandled exception capture (via System.ExceptProc)

  For VCL/FMX applications:
  To capture GUI exceptions (which bypass System.ExceptProc), add ONE of these units:
  - VCL apps: add ExeWatchSDKv1.VCL to your uses clause
  - FMX apps: add ExeWatchSDKv1.FMX to your uses clause

  LICENSE: This SDK is licensed exclusively to registered users of the
  ExeWatch platform (https://exewatch.com). Any other use is strictly
  prohibited.

  Copyright (c) 2026  - bit Time Professionals

******************************************************************************* }

unit ExeWatchSDKv1;

// Overflow and range checks belong to the CALLING project, and every Debug
// configuration turns them on. This unit's address arithmetic wraps on purpose
// and was validated without the checks: left on, an EIntOverflow inside the
// symbol builder stopped it half way and no trace of the application ever
// resolved again. They are off for this file whatever the host project says.
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SyncObjs,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.DateUtils,
  System.IOUtils,
  System.Diagnostics;  // For TStopwatch (high-precision timing)

const
  EXEWATCH_SDK_VERSION = '0.26.0';
  EXEWATCH_API_VERSION = 'v1';  // API version this SDK targets
  {$IF NOT DEFINED(LOCAL_EXEWATCH)}
  EXEWATCH_ENDPOINT = 'https://exewatch.com';
  {$ELSE}
  EXEWATCH_ENDPOINT = 'http://192.168.1.110:8000';
  {$ENDIF}
  EXEWATCH_DEFAULT_BUFFER_SIZE = 100;
  EXEWATCH_DEFAULT_FLUSH_INTERVAL_MS = 5000;
  EXEWATCH_DEFAULT_RETRY_INTERVAL_MS = 30000;
  EXEWATCH_ERROR_PERSIST_MIN_GAP_MS = 1000;  // at most one error-triggered write to disk per second
  EXEWATCH_DEFAULT_SAMPLE_RATE = 1.0;  // 1.0 = 100%, 0.5 = 50%
  EXEWATCH_MAX_BREADCRUMBS = 20;
  EXEWATCH_MAX_PENDING_TIMINGS = 100;
  EXEWATCH_LOG_FILE_EXTENSION = '.ewlog';
  EXEWATCH_DEVICE_FILE_EXTENSION = '.ewdevice';
  EXEWATCH_METRIC_FILE_EXTENSION = '.ewmetric';
  EXEWATCH_SENDING_EXTENSION = '.sending';
  EXEWATCH_TEMP_EXTENSION = '.tmp';
  EXEWATCH_DEFAULT_GAUGE_SAMPLING_INTERVAL_SEC = 30;
  EXEWATCH_MIN_GAUGE_SAMPLING_INTERVAL_SEC = 10;
  EXEWATCH_MAX_REGISTERED_GAUGES = 20;
  EXEWATCH_DEFAULT_MAX_PENDING_AGE_DAYS = 7;  // Delete unsent files older than 7 days (0 = unlimited)
  EXEWATCH_METRIC_FLUSH_INTERVAL_MS = 30000;  // 30 seconds
  EXEWATCH_INTERNAL_LOG_FILE = 'exewatch_sdk.log';
  EXEWATCH_INTERNAL_LOG_MAX_LINES = 1000;
  EXEWATCH_INTERNAL_LOG_MAX_AGE_DAYS = 7;
  // API Trace constants
  EXEWATCH_API_TRACE_FILE = 'exewatch_api_trace.log';
  EXEWATCH_API_TRACE_MAX_SIZE = 10 * 1024 * 1024;  // 10 MB
  EXEWATCH_API_TRACE_MAX_AGE_HOURS = 12;
  EXEWATCH_API_TRACE_CHECK_INTERVAL = 100;  // Check every 100 writes

type
  TEWLogLevel = (llDebug, llInfo, llWarning, llError, llFatal);

const
  LogLevelNames: array[TEWLogLevel] of string = (
    'debug', 'info', 'warning', 'error', 'fatal'
  );

type
  /// <summary>
  /// Breadcrumb types for tracking user actions before errors
  /// </summary>
  TBreadcrumbType = (
    btClick,        // UI click events
    btNavigation,   // Screen/form navigation
    btHttp,         // HTTP/API requests
    btConsole,      // Console/log output
    btCustom,       // Custom/generic breadcrumb
    btError,        // Caught exceptions or errors
    btQuery,        // Database queries
    btTransaction,  // Business/database transactions
    btUser,         // User actions (login, logout, signup, etc.)
    btSystem,       // System events (startup, shutdown, update, etc.)
    btFile,         // File operations (open, save, delete, etc.)
    btState,        // Application state changes
    btForm,         // Form/dialog open/close (VCL/FMX specific)
    btConfig,       // Configuration changes
    btMessage,      // Messages/notifications sent or received
    btDebug         // Debug information
  );

  /// <summary>
  /// A breadcrumb represents a single event in the trail leading to an error
  /// </summary>
  TBreadcrumb = record
    Timestamp: TDateTime;
    BreadcrumbType: TBreadcrumbType;
    Category: string;
    Message: string;
    Data: TJSONObject;
    class function Create(ABreadcrumbType: TBreadcrumbType; const ACategory, AMessage: string;
      AData: TJSONObject = nil): TBreadcrumb; static;
    function ToJSON: TJSONObject;
  end;

  /// <summary>
  /// Entry for a pending timing measurement
  /// </summary>
  TTimingEntry = record
    StartTicks: Int64;  // TStopwatch.GetTimestamp for high-precision timing
    Tag: string;
    Metadata: TJSONObject;
    // Nested timing traces: empty when the timing is flat (no enclosing trace).
    // SpanId/TraceId/ParentSpanId are filled only for spans inside a StartTrace.
    SpanId: string;
    TraceId: string;
    ParentSpanId: string;  // '' = trace root
    class function Create(const ATag: string; AMetadata: TJSONObject = nil): TTimingEntry; static;
  end;

  /// <summary>
  /// Info about an active timing (for debugging/inspection)
  /// </summary>
  TActiveTimingInfo = record
    Id: string;
    Tag: string;
    ElapsedMs: Double;
  end;

  /// <summary>
  /// Callback function for periodic gauge sampling
  /// </summary>
  TGaugeCallback = reference to function: Double;

  /// <summary>
  /// Registration for a periodic gauge
  /// </summary>
  TGaugeRegistration = record
    Name: string;
    Tag: string;
    Callback: TGaugeCallback;
  end;

  /// <summary>
  /// Accumulator for pre-aggregating metrics before flush
  /// </summary>
  TMetricAccumulator = record
    MetricType: string;   // 'counter' | 'gauge'
    Name: string;
    Tag: string;
    Value: Double;         // Counter: sum of deltas. Gauge: last value
    MinValue: Double;      // Gauge: min of samples
    MaxValue: Double;      // Gauge: max of samples
    SumValue: Double;      // Gauge: sum for avg calculation
    SampleCount: Integer;
    PeriodStart: TDateTime;
    class function CreateCounter(const AName, ATag: string): TMetricAccumulator; static;
    class function CreateGauge(const AName, ATag: string; AValue: Double): TMetricAccumulator; static;
  end;

  /// <summary>
  /// User identity for tracking who triggered errors
  /// </summary>
  TUserIdentity = record
    Id: string;
    Email: string;
    Name: string;
    class function Create(const AId: string; const AEmail: string = '';
      const AName: string = ''): TUserIdentity; static;
    function IsEmpty: Boolean;
    function ToJSON: TJSONObject;
  end;

  TLogEvent = record
    Level: TEWLogLevel;
    Message: string;
    Tag: string;
    Timestamp: TDateTime;
    ThreadId: UInt64;
    ProcessId: Cardinal;
    SessionId: string;
    ExtraData: TJSONObject;
    class function Create(ALevel: TEWLogLevel; const AMessage, ATag, ASessionId: string;
      AExtraData: TJSONObject = nil): TLogEvent; overload; static;
    class function Create(ALevel: TEWLogLevel; const AMessage, ATag, ASessionId: string;
      ATimestamp: TDateTime; AThreadId: UInt64; AProcessId: Cardinal;
      AExtraData: TJSONObject = nil): TLogEvent; overload; static;
    function ToJSON: TJSONObject;
    class function FromJSON(AJSON: TJSONObject): TLogEvent; static;
  end;

  TDeviceInfo = record
    DeviceId: string;
    Hostname: string;
    Username: string;
    OSType: string;
    OSVersion: string;
    AppBinaryVersion: string;  // Auto-detected from executable
    AppVersion: string;        // User-defined version tag
    TimezoneOffset: string;    // e.g., "+01:00", "-05:00"
    class function CreateFromSystem(const AAppBinaryVersion: string = ''): TDeviceInfo; static;
    function ToJSON: TJSONObject;
    class function FromJSON(AJSON: TJSONObject): TDeviceInfo; static;
  end;

  TDiskInfo = record
    Drive: string;          // e.g. "C:"
    VolumeName: string;
    FileSystem: string;     // e.g. "NTFS"
    TotalBytes: Int64;
    FreeBytes: Int64;
    DriveType: string;      // "Fixed", "Removable", "Network", "CDRom", "RamDisk"
    /// <summary>
    ///   1 = solid state, 0 = it spins, -1 = the device did not say.
    ///   DriveType cannot tell the two apart: an NVMe and a 2011 platter drive
    ///   both report "Fixed", and a drive that spins is the single most common
    ///   answer to "why is this machine slow".
    /// </summary>
    IsSSD: Integer;
    function ToJSON: TJSONObject;
  end;

  TMonitorInfo = record
    Index: Integer;
    Name: string;
    Width: Integer;
    Height: Integer;
    BitsPerPixel: Integer;
    Primary: Boolean;
    function ToJSON: TJSONObject;
  end;

  TAppVersionInfo = record
    FileVersion: string;        // e.g., "1.2.3.4"
    ProductVersion: string;     // e.g., "1.2.3"
    ProductName: string;
    FileDescription: string;
    CompanyName: string;
    InternalName: string;
    OriginalFilename: string;
    LegalCopyright: string;
    class function GetFromFile(const AFileName: string = ''): TAppVersionInfo; static;
    function ToJSON: TJSONObject;
  end;

  /// <summary>
  ///   A folder that identifies the user (the profile, the application data) and the token that
  ///   stands in for it when AnonymizeDeviceId is on, e.g. ('[USERPROFILE]', 'C:\Users\bob').
  /// </summary>
  TEWPathRoot = record
    Token: string;
    Value: string;
  end;

  THardwareInfo = record
    // Memory
    TotalPhysicalMemory: Int64;
    AvailablePhysicalMemory: Int64;
    // CPU
    CPUName: string;
    CPUCores: Integer;
    CPULogicalProcessors: Integer;
    CPUArchitecture: string;
    /// <summary>
    ///   Nominal clock, the figure a spec sheet prints. Not the boost clock,
    ///   and not what the CPU happens to be doing right now: neither is a
    ///   stable property of the machine. 0 when unknown.
    /// </summary>
    CPUMaxMhz: Integer;
    /// <summary>
    ///   Nominal clock of the slowest core class. On a hybrid CPU the efficiency
    ///   cores sit well below the package figure, and single-threaded work that
    ///   lands on one is slower for a reason no other field shows. 0 when
    ///   unknown. This is a specification, not a throttle: see CPUThrottleMaxPct.
    /// </summary>
    CPUMinCoreMhz: Integer;
    /// <summary>
    ///   Ceiling the active power plan puts on the processor, as a percentage.
    ///   A machine held at 30% is slow for a reason no hardware figure shows.
    ///   -1 when unknown.
    /// </summary>
    CPUThrottleMaxPct: Integer;
    /// <summary>"ac", "battery", or empty when unknown.</summary>
    PowerSource: string;
    /// <summary>
    ///   1 = running inside a remote desktop / terminal server session,
    ///   0 = local console, -1 = unknown. A GUI application over RDP is slow
    ///   for reasons that have nothing to do with the machine's specification,
    ///   so this changes where you look before it changes what you conclude.
    /// </summary>
    RemoteSession: Integer;
    // Disks
    Disks: TArray<TDiskInfo>;
    // Monitors
    Monitors: TArray<TMonitorInfo>;
    // Paths
    ExecutablePath: string;
    WorkingDirectory: string;
    CommandLine: string;
    // System
    SystemBootTime: TDateTime;
    LocalIPAddresses: TArray<string>;
    Timezone: string;
    SystemLanguage: string;
    SystemLocale: string;
    // Application version info (from executable)
    AppVersionInfo: TAppVersionInfo;
    // Helpers
    class function Collect: THardwareInfo; static;
    /// <summary>
    ///   Removes what names a person: user folders in the paths and the command line become
    ///   their tokens, local IP addresses and volume names are dropped.
    /// </summary>
    procedure Anonymize(const ARoots: TArray<TEWPathRoot>; ACaseSensitive: Boolean);
    function ToJSON: TJSONObject;
  end;

  TExeWatchConfig = record
    ApiKey: string;
    CustomerId: string;
    BufferSize: Integer;
    FlushIntervalMs: Integer;
    RetryIntervalMs: Integer;
    StoragePath: string;  // Directory for persistent log files
    DeviceInfo: TDeviceInfo;
    /// <summary>
    /// Custom device info to be sent along with hardware info at startup.
    /// Set before creating TExeWatch to include in the initial device info call.
    /// </summary>
    InitialCustomDeviceInfo: TArray<TPair<string, string>>;
    /// <summary>
    /// Global tags to apply before the first log event ("Application started").
    /// Use this to include environment context (e.g. session type, deployment mode)
    /// in the very first log. Tags set here behave exactly like SetTag — they are
    /// included in all subsequent events until removed.
    /// </summary>
    GlobalTags: TArray<TPair<string, string>>;
    /// <summary>
    /// Sample rate for events (1.0 = 100%, 0.5 = 50%, 0.1 = 10%).
    /// Errors and Fatal always bypass sampling.
    /// </summary>
    SampleRate: Double;
    /// <summary>
    /// Application binary version. If empty, SDK will try to auto-detect from executable.
    /// If auto-detection fails and this is empty, "not available" will be used.
    /// </summary>
    AppBinaryVersion: string;
    /// <summary>
    /// User-defined application version/release tag (e.g., "2024-Q1", "v2.0-beta").
    /// </summary>
    AppVersion: string;
    /// <summary>
    /// Gauge sampling interval in seconds. Default 30, minimum 10.
    /// Applies to all periodic gauges registered via RegisterPeriodicGauge.
    /// </summary>
    GaugeSamplingIntervalSec: Integer;
    /// <summary>
    /// Maximum age in days for unsent pending files. Files older than this are deleted.
    /// Default: 7 days. Set to 0 to disable purging (unlimited accumulation).
    /// </summary>
    MaxPendingAgeDays: Integer;
    /// <summary>
    /// On by default. Nothing that names a person leaves the machine:
    /// - Username and Hostname are sent as a code of 8 hex characters each, the same two codes
    ///   DeviceId is made of: "mario.rossi@PC01" becomes "a1b2c3d4@0f1e2d3c";
    /// - in the executable path, the working directory and the command line, a folder that
    ///   belongs to the user (USERPROFILE, APPDATA, LOCALAPPDATA, TEMP; HOME elsewhere) is
    ///   replaced by its name between square brackets: "[USERPROFILE]\app\app.exe";
    /// - local IP addresses and volume names are not sent;
    /// - the same folders are replaced in the text of the exceptions the SDK reports.
    /// A code is HMAC-SHA256 of the name with a key the SDK never sends (the machine id of the
    /// operating system or, where there is none, a random value kept in a file on the machine),
    /// so the same user on the same machine gives the same code as long as that key is there,
    /// and whoever has only the code cannot go back to the name, not even by trying names.
    /// Names of other people inside command line arguments and the text of your own log
    /// messages are not touched. Set to False to send everything as it is.
    /// </summary>
    AnonymizeDeviceId: Boolean;
    /// <summary>
    /// Override the ingest endpoint (base URL, no trailing slash).
    /// Leave empty to use the compiled-in default (https://exewatch.com, or the
    /// LOCAL_EXEWATCH override if defined). Intended for self-hosted deployments
    /// and integration tests pointing at a local backend.
    /// </summary>
    Endpoint: string;
    class function Create(const AApiKey, ACustomerId: string): TExeWatchConfig; static;
  end;

  TOnLogError = procedure(const AErrorMessage: string) of object;
  TOnLogsSent = procedure(AAcceptedCount, ARejectedCount: Integer) of object;
  TOnDeviceInfoSent = procedure(ASuccess: Boolean; const AErrorMessage: string) of object;
  TOnCustomDeviceInfoSent = procedure(ASuccess: Boolean; const AErrorMessage: string) of object;

  IExeWatchClientListener = interface
    ['{F7E8A3B2-5C1D-4E9F-8A6B-7D2C3E4F5A6B}']
    /// <summary>Called when a log is written. Use to forward to other logging systems (e.g., LoggerPro).</summary>
    procedure OnExeWatchLog(ALevel: TEWLogLevel; const AMessage, ATag: string);
    /// <summary>Called when logs are successfully sent to the server.</summary>
    procedure OnExeWatchLogsSent(AAcceptedCount, ARejectedCount: Integer);
    /// <summary>Called when an error occurs (network, etc.).</summary>
    procedure OnExeWatchError(const AErrorMessage: string);
  end;

  TExeWatch = class
  private
    FConfig: TExeWatchConfig;
    FBuffer: TList<TLogEvent>;
    FBufferLock: TCriticalSection;
    FShipperThread: TThread;
    FPersistThread: TThread;
    FPersistEvent: TEvent;
    FShutdown: Boolean;
    FShutdownEvent: TEvent;
    FOnError: TOnLogError;
    FOnLogsSent: TOnLogsSent;
    FOnDeviceInfoSent: TOnDeviceInfoSent;
    FOnCustomDeviceInfoSent: TOnCustomDeviceInfoSent;
    FClientListener: IExeWatchClientListener;
    FEnabled: Boolean;
    FFileCounter: Int64;
    FDeviceInfoSent: Boolean;
    FCustomDeviceInfo: TDictionary<string, string>;
    FCustomDeviceInfoLock: TCriticalSection;
    // The folders of the user, read once: empty when AnonymizeDeviceId is off.
    FUserPathRoots: TArray<TEWPathRoot>;
    // Breadcrumbs (thread-local: each thread has its own breadcrumb trail)
    FBreadcrumbs: TDictionary<TThreadID, TList<TBreadcrumb>>;
    FBreadcrumbOwners: TDictionary<TThreadID, Int64>; // generation ID — detects ThreadID reuse on Linux
    FBreadcrumbsLock: TCriticalSection;
    // Timing/Profiling — stored per-thread so two threads using the same
    // timing id don't collide (StartTiming auto-closes duplicates).
    // Outer key = TThread.Current.ThreadID; inner key = user-provided timing id.
    // ThreadID reuse (common on Linux) is detected via FPendingTimingsOwners
    // generation counters, mirroring the breadcrumbs pattern.
    FPendingTimings: TDictionary<TThreadID, TDictionary<string, TTimingEntry>>;
    FTimingStacks: TDictionary<TThreadID, TList<string>>;
    FPendingTimingsOwners: TDictionary<TThreadID, Int64>;
    FPendingTimingsLock: TCriticalSection;
    // User identity
    FCurrentUser: TUserIdentity;
    FCurrentUserLock: TCriticalSection;
    // Global tags
    FGlobalTags: TDictionary<string, string>;
    FGlobalTagsLock: TCriticalSection;
    // Session ID - unique per app run
    FSessionId: string;
    // Process ID - cached at startup (never changes during execution)
    FProcessId: Cardinal;
    // Server-driven dynamic configuration
    FServerConfigVersion: Integer;
    FServerFlushIntervalMs: Integer;
    FServerBatchSize: Integer;
    FServerSamplingRate: Double;
    FServerMaxMessageLength: Integer;
    FServerMinLevel: TEWLogLevel;
    FServerEnabled: Boolean;
    FServerConfigLock: TCriticalSection;
    // Internal diagnostic logging
    FInternalLogLock: TCriticalSection;
    FLastSendFailed: Boolean;
    // API Trace
    FAPITraceFile: string;
    FAPITraceWriteCount: Integer;
    FAPITraceLock: TCriticalSection;
    // Metrics (Counters & Gauges)
    FMetricAccumulators: TDictionary<string, TMetricAccumulator>;
    FMetricAccumulatorsLock: TCriticalSection;
    FRegisteredGauges: TList<TGaugeRegistration>;
    FRegisteredGaugesLock: TCriticalSection;
    FSamplerThread: TThread;
    FLastMetricFlushTime: TDateTime;
    FLastErrorPersistTick: UInt64;
    procedure SamplerThreadExecute;
    procedure PersistMetricBuffer;
    procedure UnregisterPeriodicGaugeInternal(const AName: string);
    function GetNextMetricFileName: string;
    procedure WriteInternalLog(const AMessage: string);
    procedure CleanupOldInternalLogs;
    procedure InitializeAPITrace;
    procedure WriteAPITrace(const AEntry: string);
    procedure CheckAPITraceRotation;
    procedure RotateAPITraceFile;
    procedure ApplyServerConfig(AConfigJson: TJSONObject);
    function GetEffectiveFlushInterval: Integer;
    function GetEffectiveSamplingRate: Double;
    function GetEffectiveMaxMessageLength: Integer;
    function GetEffectiveMinLevel: TEWLogLevel;
    function GetEffectiveEnabled: Boolean;
    function EffectiveEndpoint: string;
    function TruncateMessage(const AMessage: string): string;
    function SendToServer(const AFilePath: string): Boolean;
    function RemoveInvalidEventsFromFile(const AFilePath, AResponseJson: string): Boolean;
    procedure ShipperThreadExecute;
    procedure PersistThreadExecute;
    procedure DoError(const AMessage: string);
    procedure DoLogsSent(AAccepted, ARejected: Integer);
    procedure DoDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
    procedure DoCustomDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
    function GetNextFileName: string;
    procedure PersistBuffer;
    function GetPendingLogFiles: TArray<string>;
    procedure EnsureStoragePath;
    procedure PurgeExpiredFiles;
    procedure QueueDeviceInfo;
    function ShouldSample: Boolean;
    function BuildExtraData(AExtraData: TJSONObject; AIncludeBreadcrumbs: Boolean): TJSONObject;
  public
    constructor Create(const AConfig: TExeWatchConfig);
    destructor Destroy; override;

    /// <summary>
    /// The content of the device file (device, hardware, custom info) exactly as it is queued.
    /// The caller owns the result. Public so that tests can read it without going through the disk.
    /// </summary>
    function BuildDeviceInfoFile: TJSONObject;

    procedure Log(ALevel: TEWLogLevel; const AMessage: string;
      const ATag: string = 'main'; AExtraData: TJSONObject = nil); overload;
    /// <summary>
    /// Log with custom timestamp and thread ID (for integration with other logging frameworks).
    /// Process ID is automatically captured at SDK startup.
    /// </summary>
    procedure Log(ALevel: TEWLogLevel; const AMessage: string; const ATag: string;
      ATimestamp: TDateTime; AThreadId: UInt64; AExtraData: TJSONObject = nil); overload;

    procedure Debug(const AMessage: string; const ATag: string = 'main'); overload;
    procedure Info(const AMessage: string; const ATag: string = 'main'); overload;
    procedure Warning(const AMessage: string; const ATag: string = 'main'); overload;
    procedure Error(const AMessage: string; const ATag: string = 'main'); overload;
    procedure Fatal(const AMessage: string; const ATag: string = 'main'); overload;

    // Format-style overloads (like SysUtils.Format)
    procedure Debug(const AFormat: string; const AArgs: array of const; const ATag: string = 'main'); overload;
    procedure Info(const AFormat: string; const AArgs: array of const; const ATag: string = 'main'); overload;
    procedure Warning(const AFormat: string; const AArgs: array of const; const ATag: string = 'main'); overload;
    procedure Error(const AFormat: string; const AArgs: array of const; const ATag: string = 'main'); overload;
    procedure Fatal(const AFormat: string; const AArgs: array of const; const ATag: string = 'main'); overload;

    procedure ErrorWithException(E: Exception; const ATag: string = 'main';
      const AAdditionalMessage: string = '');

    /// <summary>
    ///   AText with the folders of the user replaced by their placeholder ("[USERPROFILE]\..."),
    ///   when AnonymizeDeviceId is on; AText as it is otherwise. The SDK passes the text of the
    ///   exceptions it reports through it. Use it on a message of yours that may hold a path.
    /// </summary>
    function ScrubUserPaths(const AText: string): string;

    /// <summary>
    /// Queues device hardware info and custom info to be sent to the server.
    /// Called automatically at startup. Uses persistent storage with automatic retry.
    /// To include custom device info, set Config.InitialCustomDeviceInfo before creating the logger.
    /// </summary>
    procedure SendDeviceInfo;

    /// <summary>
    /// Sets a custom device info key-value pair.
    /// These are accumulated until SendCustomDeviceInfo is called.
    /// </summary>
    procedure SetCustomDeviceInfo(const AKey, AValue: string);

    /// <summary>
    /// Clears a specific custom device info key.
    /// </summary>
    procedure ClearCustomDeviceInfo(const AKey: string);

    /// <summary>
    /// Clears all accumulated custom device info.
    /// </summary>
    procedure ClearAllCustomDeviceInfo;

    /// <summary>
    /// Sends all accumulated custom device info to the server.
    /// The data is merged with any existing custom info on the server.
    /// </summary>
    procedure SendCustomDeviceInfo; overload;

    /// <summary>
    /// Sets and immediately sends a single custom device info key-value pair.
    /// </summary>
    procedure SendCustomDeviceInfo(const AKey, AValue: string); overload;

    procedure Flush;
    procedure Shutdown;

    function GetPendingCount: Integer;
    /// <summary>
    /// Flushes the in-memory buffer to disk and waits (up to TimeoutSec
    /// seconds) until every pending event has been shipped to the server.
    /// Useful for short-lived apps / console samples where you must ensure
    /// events are uploaded before the process exits.
    /// Returns the number of events still pending when the call returns
    /// (0 = fully drained, >0 = timeout with events still queued).
    /// </summary>
    function WaitForSending(ATimeoutSec: Integer): Integer;

    // ============================================================
    // Breadcrumbs - Trail of events before errors
    // ============================================================

    /// <summary>
    /// Adds a breadcrumb to the trail. Breadcrumbs are attached to error events.
    /// </summary>
    procedure AddBreadcrumb(ABreadcrumbType: TBreadcrumbType; const ACategory, AMessage: string;
      AData: TJSONObject = nil); overload;

    /// <summary>
    /// Adds a custom breadcrumb with message and optional category.
    /// </summary>
    procedure AddBreadcrumb(const AMessage: string; const ACategory: string = 'custom'); overload;

    /// <summary>
    /// Gets a copy of current breadcrumbs.
    /// </summary>
    function GetBreadcrumbs: TArray<TBreadcrumb>;

    /// <summary>
    /// Clears all breadcrumbs.
    /// </summary>
    procedure ClearBreadcrumbs;

    // ============================================================
    // Timing / Profiling
    // ============================================================

    /// <summary>
    /// Starts a timing measurement.
    /// </summary>
    procedure StartTiming(const AId: string; const ATag: string = ''); overload;

    /// <summary>
    /// Starts a timing measurement with metadata.
    /// </summary>
    procedure StartTiming(const AId: string; const ATag: string; AMetadata: TJSONObject); overload;

    /// <summary>
    /// Starts a timing with format-style ID.
    /// </summary>
    procedure StartTiming(const AIdFormat: string; const AArgs: array of const; const ATag: string = ''); overload;

    /// <summary>
    /// Opens a named root trace (a tree of nested timings). Timings started while
    /// the trace is open auto-nest under it via the per-thread LIFO stack. Returns
    /// the generated trace_id. Single-thread/synchronous: a timing started on
    /// another thread is not part of this trace. If a trace is already open on the
    /// thread, this degrades to a normal child timing (no nested traces).
    /// </summary>
    function StartTrace(const AName: string): string;

    /// <summary>
    /// Closes the current thread's active root trace, emitting its span. Any child
    /// timings still open are force-closed as failed (incomplete). Returns the
    /// trace's total duration in ms, or -1 if no trace is active.
    /// </summary>
    function EndTrace: Double;

    /// <summary>
    /// Ends a timing measurement and sends a log. Returns duration in ms, or -1 if not found.
    /// </summary>
    function EndTiming(const AId: string; AEndMetadata: TJSONObject = nil; ASuccess: Boolean = True): Double; overload;

    /// <summary>
    /// Ends a timing with format-style ID.
    /// </summary>
    function EndTiming(const AIdFormat: string; const AArgs: array of const; AEndMetadata: TJSONObject = nil; ASuccess: Boolean = True): Double; overload;

    /// <summary>
    /// Ends the last started timing (LIFO stack). Returns duration in ms, or -1 if no active timing.
    /// </summary>
    function EndTiming: Double; overload;

    /// <summary>
    /// Checks if a timing is currently active.
    /// </summary>
    function IsTimingActive(const AId: string): Boolean;

    /// <summary>
    /// Cancels a timing without sending a log.
    /// </summary>
    procedure CancelTiming(const AId: string); overload;

    /// <summary>
    /// Cancels the last started timing without sending a log.
    /// </summary>
    procedure CancelTiming; overload;

    /// <summary>
    /// Gets all active timings (for debugging).
    /// </summary>
    function GetActiveTimings: TArray<TActiveTimingInfo>;

    // ============================================================
    // User Identity - Track who triggered errors
    // ============================================================

    /// <summary>
    /// Sets the current user identity. User info is included in all events.
    /// Note: this is a global setting shared across all threads, best suited
    /// for desktop apps with a single user. For multi-threaded server apps,
    /// consider passing user info via extra_data on each log call.
    /// </summary>
    procedure SetUser(const AUser: TUserIdentity); overload;

    /// <summary>
    /// Sets the current user identity with individual parameters.
    /// </summary>
    procedure SetUser(const AId: string; const AEmail: string = ''; const AName: string = ''); overload;

    /// <summary>
    /// Clears the current user identity.
    /// </summary>
    procedure ClearUser;

    /// <summary>
    /// Gets the current user identity.
    /// </summary>
    function GetUser: TUserIdentity;

    // ============================================================
    // Customer ID - Can be set after initialization
    // ============================================================

    /// <summary>
    /// Sets the customer ID. Use this when the customer ID is not known at startup
    /// (e.g., after license validation). All subsequent logs will use this customer ID.
    /// </summary>
    procedure SetCustomerId(const ACustomerId: string);

    /// <summary>
    /// Gets the current customer ID.
    /// </summary>
    function GetCustomerId: string;

    // ============================================================
    // Global Tags - Context added to all events
    // ============================================================

    /// <summary>
    /// Sets multiple global tags at once.
    /// </summary>
    procedure SetTags(const ATags: TArray<TPair<string, string>>);

    /// <summary>
    /// Sets a single global tag.
    /// </summary>
    procedure SetTag(const AKey, AValue: string);

    /// <summary>
    /// Removes a global tag.
    /// </summary>
    procedure RemoveTag(const AKey: string);

    /// <summary>
    /// Clears all global tags.
    /// </summary>
    procedure ClearTags;

    /// <summary>
    /// Gets all current global tags.
    /// </summary>
    function GetTags: TArray<TPair<string, string>>;

    // ============================================================
    // Metrics (Counters & Gauges)
    // ============================================================

    /// <summary>
    /// Increments a counter metric by AValue (default 1.0).
    /// Counters track cumulative values: API calls, cache hits, errors processed, etc.
    /// Values are pre-aggregated in memory and flushed to the server every 60 seconds.
    /// </summary>
    procedure IncrementCounter(const AName: string; AValue: Double = 1.0; const ATag: string = '');

    /// <summary>
    /// Records a gauge metric with the current value.
    /// Gauges track point-in-time values: memory usage, CPU, active connections, queue depth, etc.
    /// Values are pre-aggregated (min/max/avg/last) and flushed every 60 seconds.
    /// </summary>
    procedure RecordGauge(const AName: string; AValue: Double; const ATag: string = '');

    /// <summary>
    /// Registers a periodic gauge that is automatically sampled every GaugeSamplingIntervalSec.
    /// The callback function is called on a background thread to read the current value.
    /// Maximum 20 gauges can be registered.
    /// </summary>
    procedure RegisterPeriodicGauge(const AName: string; ACallback: TGaugeCallback; const ATag: string = '');

    /// <summary>
    /// Unregisters a periodic gauge by name.
    /// </summary>
    procedure UnregisterPeriodicGauge(const AName: string);

    // ============================================================
    // Version
    // ============================================================

    /// <summary>
    /// Gets the user-defined app version string (set via Config.AppVersion before init).
    /// </summary>
    function GetAppVersion: string;

    property Enabled: Boolean read FEnabled write FEnabled;
    property OnError: TOnLogError read FOnError write FOnError;
    property OnLogsSent: TOnLogsSent read FOnLogsSent write FOnLogsSent;
    property OnDeviceInfoSent: TOnDeviceInfoSent read FOnDeviceInfoSent write FOnDeviceInfoSent;
    property OnCustomDeviceInfoSent: TOnCustomDeviceInfoSent read FOnCustomDeviceInfoSent write FOnCustomDeviceInfoSent;
    property ClientListener: IExeWatchClientListener read FClientListener write FClientListener;
    property Config: TExeWatchConfig read FConfig;
    property DeviceInfoSent: Boolean read FDeviceInfoSent;
    /// <summary>
    /// Unique identifier for this application session (8 hex chars).
    /// Use to correlate all logs from a single app run.
    /// </summary>
    property SessionId: string read FSessionId;
  end;

  TExeWatchHelper = class
  public
    class function GetHostname: string;
    class function GetUsername: string;
    class function GetOSVersion: string;
    class function GetDeviceId: string;
    /// <summary>
    ///   The code that stands for a user name: KeyedCode with the key of this machine.
    /// </summary>
    class function AnonymizeUsername(const AUsername: string): string;
    /// <summary>
    ///   The code that stands for a host name. What follows the first dot is left out:
    ///   "srv01" and "srv01.example.com" are one machine, and runtimes report either.
    /// </summary>
    class function AnonymizeHostname(const AHostname: string): string;
    /// <summary>
    ///   The first 8 hex digits of HMAC-SHA256(AKey, AName), AName in UTF-8 with its ASCII
    ///   letters in lower case. 'anonymous' for an empty name. Without the key the code says
    ///   nothing about the name.
    /// </summary>
    class function KeyedCode(const AKey: TBytes; const AName: string): string;
    /// <summary>
    ///   The key of the codes. It is the machine id the operating system keeps (MachineGuid on
    ///   Windows, /etc/machine-id on Linux); where there is none, a random value the SDK writes
    ///   once in a folder of the user. It is never sent and never logged.
    /// </summary>
    class function GetDeviceKey: TBytes;
    /// <summary>The machine id of the operating system, empty where there is none.</summary>
    class function GetMachineId: string;
    /// <summary>
    ///   The folders of the current user that appear in paths: USERPROFILE, APPDATA, LOCALAPPDATA
    ///   and TEMP on Windows, HOME elsewhere. Empty values are left out.
    /// </summary>
    class function GetUserPathRoots: TArray<TEWPathRoot>;
    /// <summary>
    ///   Replaces, anywhere in AText, a path that starts with one of the roots by its token
    ///   (longest root first). The root has to end at a separator, at a delimiter or at the end of
    ///   the text, and not start in the middle of a name. '/' and '\' are the same separator.
    /// </summary>
    class function ScrubUserPaths(const AText: string; const ARoots: TArray<TEWPathRoot>;
      ACaseSensitive: Boolean): string;
    class function GetDefaultStoragePath(const AApiKey: string = ''): string;
    class function GetTimezoneOffset: string;  // Returns offset like "+01:00" or "-05:00"
    class function GetAppVersionInfo: TAppVersionInfo;  // Auto-reads from current exe
    class function GetCurrentProcessId: Cardinal;
  end;

/// <summary>
///   The parsers behind the Linux hardware readers. Pure text in, text out, so they are public for the
///   tests and run on every system.
/// </summary>
function EWParseCpuModelName(const AText: string): string;
function EWIsPseudoFileSystem(const AFileSystem: string): Boolean;
function EWIsNetworkFileSystem(const AFileSystem: string): Boolean;
function EWParseMountLine(const ALine: string; out ADevice, AMountPoint, AFileSystem: string): Boolean;
function EWBlockDeviceName(const ADevice: string): string;

/// <summary>
///   SHA-256 (FIPS 180-4) and HMAC-SHA256 (RFC 2104). The RTL has no SHA-2 before Delphi 10, and
///   the codes of user and host must be the same from XE8 on: hence one implementation here,
///   public so that the tests check it against the published vectors.
/// </summary>
function EWSha256(const AData: TBytes): TBytes;
function EWHmacSha256(const AKey, AData: TBytes): TBytes;

/// <summary>
///   The key kept in AFolder\device.key, written there the first time. With no folder given it
///   is the folder of the user the SDK uses where the operating system has no machine id.
///   ANewKey is the key to write where there is none: the one of this process, unless a test
///   stands for several processes at once. Public so that the tests reach it.
/// </summary>
function EWDeviceKeyFromFile(const AFolder: string = ''; const ANewKey: string = ''): string;
/// <summary>
///   True for 32 hex digits, which is how Linux writes its machine id. Public for the tests.
/// </summary>
function EWIsLinuxMachineId(const AValue: string): Boolean;

function ExeWatch: TExeWatch;
function EW: TExeWatch; inline;  // Short alias for ExeWatch
function ExeWatchIsInitialized: Boolean;
function _ExeWatch: TExeWatch; inline;  // Alias to avoid name conflict with unit name
procedure InitializeExeWatch(const AApiKey, ACustomerId: string; AAppVersion: String = ''; AAnonymizeDeviceId: Boolean = True); overload;
procedure InitializeExeWatch(const AConfig: TExeWatchConfig); overload;
procedure FinalizeExeWatch;

/// <summary>
/// Returns True if the current application is a GUI application (Windows subsystem).
/// Used to detect if VCL/FMX hook unit should be added.
/// </summary>
function ExeWatchIsGUIApplication: Boolean;

/// <summary>
/// Called by ExeWatchSDKv1.VCL or ExeWatchSDKv1.FMX to register framework exception hook.
/// </summary>
procedure ExeWatchRegisterFrameworkHook;

// Internal: used by ExeWatchSDKv1.VCL/FMX hooks — not part of the public API
function GetStackTraceStr(FramesToSkip: Integer = 0): string;
function GetNoStackTraceReason: Integer;
// Where the host module's symbols come from: 'embedded' (.ewmap section or
// EXEWATCH_MAP resource, travels with the binary), 'map_file' (a .map beside
// the exe: works on the developer's machine, not on the customer's) or 'none'.
// Two more say the exe DOES carry a map this SDK cannot use:
// 'unsupported_map_format' (linked by a newer tool than this SDK: update the
// SDK) and 'corrupt_map'. Empty where traces are not supported.
function GetSymbolSource: string;
// Adds 'symbol_source' to the extra data of an event that carries a stack
// trace, so the console can tell an unreadable trace from a readable one.
procedure AttachSymbolSource(AExtraData: TJSONObject);
// The trace lives on the exception object, so the caller must say which
// exception it is asking about. No default: a nil argument can only ever
// return an empty string, and the compiler should say so.
function GetLastExceptionStackTrace(E: Exception): string;

{$IFDEF MSWINDOWS}
type
  /// <summary>
  ///   The module an address belongs to: handle, load base, image size and
  ///   base file name. Module=0 means no loaded module owns the address.
  /// </summary>
  TSTModuleInfo = record
    Module: THandle;
    Base: NativeUInt;
    SizeOfImage: Cardinal;
    ModuleName: string;
  end;

{$ENDIF}

{$IFDEF EXEWATCH_TESTING}
function EWGetStackTraceStr(FramesToSkip: Integer = 0): string;
{$IFDEF MSWINDOWS}
/// <summary>
///   Exposed for the test project only. The symbol table is built once, on the
///   first exception of the process, and the race lives in exactly that
///   moment - so a test has to be able to put it back to never-loaded.
///   AYieldBeforeClaim widens the window so the race is reproducible instead
///   of depending on a two-instruction gap between threads.
/// </summary>
procedure EWTestResetStackTraceInit(AYieldBeforeClaim: Boolean);
/// <summary>
///   Highest number of threads that were ever inside the symbol-table build
///   for the same module at the same time. Above 1 means two threads were
///   freeing and regrowing the same arrays under each other.
/// </summary>
function EWTestMaxConcurrentMapLoads: Integer;
/// <summary>
///   Replaces the symbol table with synthetic entries, so resolution can be
///   probed without an executable of the size that would be needed to reach
///   those addresses for real.
/// </summary>
procedure EWTestSeedSymbols(ACount: Integer; AStep: NativeUInt; ACodeBase: NativeUInt);
function EWTestFindSymbol(AAddress: NativeUInt): string;
/// <summary>
///   Exposed for the test project only: the module attribution used to decide
///   which symbol table answers for a frame.
/// </summary>
function EWTestModuleInfoForAddress(AAddress: NativeUInt): TSTModuleInfo;
/// <summary>
///   Exposed for the test project only: the full per-frame resolution the
///   traces go through (module table, exports, module+offset).
/// </summary>
function EWTestResolveAddress(AAddress: NativeUInt): string;
/// <summary>
///   Exposed for the test project only: counts the public symbols in a
///   module's embedded map (.ewmap section first, then the RCDATA resource;
///   0 = no usable embedded map there).
/// </summary>
function EWTestCountEmbeddedMapSymbols(AModule: THandle): Integer;
/// <summary>
///   Exposed for the test project only: reads the .ewmap section alone, so a
///   test can tell that storage form apart from the resource and file forms.
/// </summary>
function EWTestSectionMapText(AModule: THandle): string;
/// <summary>
///   Exposed for the test project only: the .ewmap payload decoder on raw
///   bytes (header, then the stored map), so a test can feed it formats no
///   injector writes. Returns Ord(TSTMapStatus): 0 ok, 2 unsupported, 3 corrupt.
/// </summary>
function EWTestDecodeMapPayload(AData: PByte; ASize: Integer;
  out ABytes: TBytes): Integer;
/// <summary>
///   Exposed for the test project only: the runtime's own symbol-text reader
///   for a module (embedded section, then resource, then the .map file beside
///   it), so a test can prove which source a resolution would come from.
/// </summary>
function EWTestModuleText(AModule: THandle): string;
/// <summary>
///   Exposed for the test project only: where the symbol text of a module comes
///   from ('embedded', 'map_file' or 'none'), read straight from the module.
/// </summary>
function EWTestModuleSource(AModule: THandle): string;
/// <summary>
///   Exposed for the test project only: the symbol source of the HOST module as
///   the runtime reports it on events.
/// </summary>
function EWTestHostSymbolSource: string;
/// <summary>
///   Exposed for the test project only: builds a symbol table from map text and
///   answers what a trace would print for an offset of that module (the name,
///   with the line when the map has one).
/// </summary>
function EWTestDescribeFromMapText(const AMapText: string; AOffset: NativeUInt): string;
/// <summary>
///   Exposed for the test project only: whether a module image is linked for
///   the console subsystem (read from its PE header).
/// </summary>
function EWTestIsConsoleSubsystem(AModule: THandle): Boolean;
{$IFDEF CPUX86}
/// <summary>
///   Exposed for the test project only: the CALL-instruction size detector
///   the Win32 walk uses to correct call sites.
/// </summary>
function EWTestCallSiteSize(AReturnAddress: NativeUInt): Cardinal;
{$ENDIF}
/// <summary>
///   Exposed for the test project only. Drives the real restore path with a
///   probe: the finalization runs at process exit, after the last test has
///   reported, so this is the only way to exercise the line. Returns an empty
///   string when both properties hold, otherwise what went wrong.
/// </summary>
function EWTestRtlHookRestoreCheck: string;
{$ENDIF}
{$IFDEF LINUX}
/// <summary>
///   Exposed for the test project only. /sys and /proc files report a size of
///   zero and break the RTL readers, so this one has to be proven to work
///   against a real virtual file rather than trusted.
/// </summary>
function EWTestReadSysInt(const APath: string; out AValue: Int64): Boolean;
{$ENDIF}
{$ENDIF}

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.WinSock,
  System.Win.Registry,
  System.ZLib,
{$ENDIF}
{$IFDEF LINUX}
  Posix.Base,
  Posix.Fcntl,
  Posix.Unistd,
  Posix.Pwd,
  Posix.SysStatvfs,
{$ENDIF}
{$IFDEF ANDROID}
  Posix.Unistd,
  Posix.Pthread,
  Androidapi.Helpers,
  Androidapi.JNI.Os,
  Androidapi.JNI.JavaTypes,
  Androidapi.JNI.App,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.JNIBridge,
{$ENDIF}
  System.Character,
  System.StrUtils,
  System.Types,
  System.TimeSpan,
  System.NetConsts;

{$IFDEF ANDROID}
// gettid() returns the kernel thread ID (unique per thread, changes across process runs)
// Available since Android API 17 (bionic libc)
function gettid: Int32; cdecl; external 'libc.so' name 'gettid';
{$ENDIF}

// Cross-platform current thread ID
function EWCurrentThreadId: UInt64; inline;
begin
  {$IFDEF ANDROID}
  Result := UInt64(gettid);
  {$ELSE}
  Result := TThread.Current.ThreadID;
  {$ENDIF}
end;

// XE8 has no TJSONBool (TJSONTrue / TJSONFalse only)
function EWJsonBool(AValue: Boolean): TJSONValue;
begin
  if AValue then
    Result := TJSONTrue.Create
  else
    Result := TJSONFalse.Create;
end;

{$IFDEF MSWINDOWS}
// Not declared by XE8's Winapi.Windows; present on Vista and later
function EWGetTickCount64: UInt64; stdcall; external 'kernel32.dll' name 'GetTickCount64';
{$ENDIF}

{$IFDEF MSWINDOWS}
// Types for GetLogicalProcessorInformation (may not be in older Delphi)
type
  TLogicalProcessorRelationship = (
    RelationProcessorCore = 0,
    RelationNumaNode = 1,
    RelationCache = 2,
    RelationProcessorPackage = 3,
    RelationGroup = 4,
    RelationAll = $FFFF
  );

  TProcessorCoreFlags = BYTE;

  TCacheDescriptor = record
    Level: BYTE;
    Associativity: BYTE;
    LineSize: WORD;
    Size: DWORD;
    CacheType: DWORD;
  end;

  TSystemLogicalProcessorInformation = record
    ProcessorMask: ULONG_PTR;
    Relationship: TLogicalProcessorRelationship;
    case Integer of
      0: (Flags: TProcessorCoreFlags);
      1: (NodeNumber: DWORD);
      2: (Cache: TCacheDescriptor);
      3: (Reserved: array[0..1] of UInt64);
  end;
  PSystemLogicalProcessorInformation = ^TSystemLogicalProcessorInformation;

function GetLogicalProcessorInformation(
  Buffer: PSystemLogicalProcessorInformation;
  var ReturnLength: DWORD): BOOL; stdcall; external kernel32;

// SetThreadErrorMode is Vista+ and may not be declared in older Delphi Winapi.Windows.
// Declared locally to keep the SDK independent of the RTL version.
// Used to suppress the Windows "No Disk" critical-error popup when probing
// empty removable drives (e.g. a physical floppy with no media inserted).
const
  EW_SEM_FAILCRITICALERRORS = $0001;
  EW_SEM_NOOPENFILEERRORBOX = $8000;

function SetThreadErrorMode(NewMode: DWORD; OldMode: PDWORD): BOOL; stdcall;
  external kernel32 name 'SetThreadErrorMode';
{$ENDIF}

{$IFDEF LINUX}
const
  libc = 'libc.so';

type
  TSysInfo = record
    uptime: Int64;
    loads: array[0..2] of UInt64;
    totalram: UInt64;
    freeram: UInt64;
    sharedram: UInt64;
    bufferram: UInt64;
    totalswap: UInt64;
    freeswap: UInt64;
    procs: Word;
    totalhigh: UInt64;
    freehigh: UInt64;
    mem_unit: Cardinal;
    _f: array[0..7] of AnsiChar;
  end;
  PSysInfo = ^TSysInfo;

function sysinfo(info: PSysInfo): Integer; cdecl; external libc name 'sysinfo';
{$ENDIF}

var
  GExeWatch: TExeWatch = nil;
  GExeWatchLock: TCriticalSection = nil;
  // Exception capture
  GOldExceptProc: procedure(ExceptObject: TObject; ExceptAddr: Pointer) = nil;
  GFrameworkHookInstalled: Boolean = False;
  GExceptionHandlingInProgress: Integer = 0;  // 0=false, 1=true - Integer for TInterlocked
  // Breadcrumb thread ownership — atomic counter to detect ThreadID reuse on Linux
  GBreadcrumbNextGen: Int64 = 0;
  // Timing thread ownership — same pattern as breadcrumbs, for per-thread timings
  GTimingNextGen: Int64 = 0;

threadvar
  GMyBreadcrumbGen: Int64; // unique generation for current thread (0 = not assigned yet)
  GMyTimingGen: Int64;     // unique generation for current thread's timing dict


{$IFDEF MSWINDOWS}
// The stack must be captured at raise time, before SEH unwinding destroys the
// frames, but it is only read later, by the VCL/FMX hooks. It therefore has to
// survive between the two, and it is held on the exception object: Delphi calls
// CleanUpStackInfoProc from Exception.Destroy, so the trace dies with the
// exception that owns it.
//
// It used to be parked in a threadvar instead, which had two consequences.
// Delphi does not finalize managed threadvars when a thread ends, so every
// thread that raised a handled exception leaked its trace string for the life
// of the process. And since nothing consumed the value outside a GUI app, the
// next exception on that thread was handed the previous one's stack.
type
  PEWStackInfo = ^TEWStackInfo;
  TEWStackInfo = record
    Signature: NativeUInt; // proves the block came from here, see EWStackInfoOf
    Trace: string;
    Inner: Pointer;        // whatever the previously installed provider returned
  end;

const
  EW_STACKINFO_SIGNATURE = NativeUInt($45575354); // 'EWST'

var
  GOldGetExceptionStackInfoProc: function(P: System.PExceptionRecord): Pointer = nil;
  GOldGetStackInfoStringProc: function(Info: Pointer): string = nil;
  GOldCleanUpStackInfoProc: procedure(Info: Pointer) = nil;

// Returns Info as ours, or nil when it belongs to another stack-trace provider
// that installed itself after us (other exception-reporting libraries).
function EWStackInfoOf(Info: Pointer): PEWStackInfo;
begin
  if (Info <> nil) and (PEWStackInfo(Info)^.Signature = EW_STACKINFO_SIGNATURE) then
    Result := PEWStackInfo(Info)
  else
    Result := nil;
end;

{$IFDEF MSWINDOWS}
function GetExceptionTraceStr(AExceptAddr: Pointer): string; forward;
{$ENDIF}

function ExeWatchGetExceptionStackInfo(P: System.PExceptionRecord): Pointer;
var
  Info: PEWStackInfo;
begin
  New(Info);
  Info^.Signature := EW_STACKINFO_SIGNATURE;
  Info^.Inner := nil;
  try
    Info^.Trace := GetExceptionTraceStr(P^.ExceptionAddress);
    if Assigned(GOldGetExceptionStackInfoProc) then
      Info^.Inner := GOldGetExceptionStackInfoProc(P);
  except
    // This runs while an exception is being raised. Letting a second one out
    // of here would recurse through the same hook, so a failed capture costs
    // the trace and nothing else.
  end;
  Result := Info;
end;

// E.StackTrace goes through here. Whoever was providing the text before us
// keeps providing it, so installing the SDK does not change what an existing
// stack-trace library prints.
function ExeWatchGetStackInfoString(Info: Pointer): string;
var
  Ours: PEWStackInfo;
begin
  Ours := EWStackInfoOf(Info);
  if Ours = nil then
  begin
    if Assigned(GOldGetStackInfoStringProc) then
      Result := GOldGetStackInfoStringProc(Info)
    else
      Result := '';
    Exit;
  end;

  if Assigned(GOldGetStackInfoStringProc) and (Ours^.Inner <> nil) then
    Result := GOldGetStackInfoStringProc(Ours^.Inner)
  else
    Result := Ours^.Trace;
end;

procedure ExeWatchCleanUpStackInfo(Info: Pointer);
var
  Ours: PEWStackInfo;
begin
  Ours := EWStackInfoOf(Info);
  if Ours = nil then
  begin
    if Assigned(GOldCleanUpStackInfoProc) then
      GOldCleanUpStackInfoProc(Info);
    Exit;
  end;

  if Assigned(GOldCleanUpStackInfoProc) and (Ours^.Inner <> nil) then
    GOldCleanUpStackInfoProc(Ours^.Inner);
  Dispose(Ours);
end;
{$ENDIF}
// Old code marker for deletion start

// Forward declaration
procedure CheckAndWarnAboutFrameworkHook; forward;

function ExeWatch: TExeWatch;
begin
  if GExeWatch = nil then
    raise Exception.Create('ExeWatch not initialized. Call InitializeExeWatch first.');
  Result := GExeWatch;
end;

function EW: TExeWatch;
begin
  Result := ExeWatch;
end;

function ExeWatchIsInitialized: Boolean;
begin
  Result := GExeWatch <> nil;
end;

function _ExeWatch: TExeWatch;
begin
  Result := ExeWatch;
end;

procedure InitializeExeWatch(const AApiKey, ACustomerId: string; AAppVersion: String; AAnonymizeDeviceId: Boolean); overload;
var
  Config: TExeWatchConfig;
begin
  Config := TExeWatchConfig.Create(AApiKey, ACustomerId);
  Config.AppVersion := AAppVersion;
  Config.AnonymizeDeviceId := AAnonymizeDeviceId;
  // The constructor already queues the device info: calling SendDeviceInfo here
  // would collect the hardware a second time on the caller's thread.
  InitializeExeWatch(Config);
  // Warn if GUI app without VCL/FMX hook (deferred to allow hook units to register first)
  CheckAndWarnAboutFrameworkHook;
end;

procedure InitializeExeWatch(const AConfig: TExeWatchConfig);
begin
  GExeWatchLock.Enter;
  try
    if GExeWatch <> nil then
      FreeAndNil(GExeWatch);
    GExeWatch := TExeWatch.Create(AConfig);
  finally
    GExeWatchLock.Leave;
  end;
  // Warn if GUI app without VCL/FMX hook (deferred to allow hook units to register first)
  CheckAndWarnAboutFrameworkHook;
end;

procedure FinalizeExeWatch;
begin
  GExeWatchLock.Enter;
  try
    if GExeWatch <> nil then
    begin
      GExeWatch.Shutdown;
      FreeAndNil(GExeWatch);
    end;
  finally
    GExeWatchLock.Leave;
  end;
end;

// ============================================================
// Automatic Exception Capture
// ============================================================

{$IFDEF MSWINDOWS}
// True when the image is linked for the console subsystem. Read from the PE
// header of the image itself: the CONSOLE define says how THIS unit was
// compiled, and a C++Builder console program compiles the SDK unit as GUI.
function STIsConsoleSubsystem(AModule: THandle): Boolean;
var
  DosHeader: PImageDosHeader;
  Nt: PImageNtHeaders32;
begin
  Result := False;
  if AModule = 0 then
    Exit;
  DosHeader := PImageDosHeader(AModule);
  if DosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    Exit;
  Nt := PImageNtHeaders32(NativeUInt(AModule) + NativeUInt(DosHeader^._lfanew));
  if Nt^.Signature <> IMAGE_NT_SIGNATURE then
    Exit;
  // Same offset in the 32-bit and the 64-bit optional header.
  Result := Nt^.OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_CUI;
end;
{$ENDIF}

function ExeWatchIsGUIApplication: Boolean;
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(CONSOLE)}
var
  WinSta: HWINSTA;
  Flags: TUserObjectFlags;
  LengthNeeded: DWORD;
{$IFEND}
begin
  {$IFDEF CONSOLE}
  // {$APPTYPE CONSOLE} defines CONSOLE at compile time → never a GUI app
  Result := False;
  {$ELSE}
  {$IFDEF MSWINDOWS}
  // Compiled as GUI, but the program that hosts it may still be a console one.
  if STIsConsoleSubsystem(GetModuleHandle(nil)) then
    Exit(False);
  // Non-console Windows app: could be a VCL/FMX GUI or a TService/daemon.
  // Services run on non-interactive window stations (e.g. "Service-0x0-3e7$")
  // which lack the WSF_VISIBLE flag — use this to tell them apart from GUI apps.
  Result := True;
  WinSta := GetProcessWindowStation;
  if WinSta <> 0 then
  begin
    FillChar(Flags, SizeOf(Flags), 0);
    LengthNeeded := 0;
    if GetUserObjectInformation(WinSta, UOI_FLAGS, @Flags, SizeOf(Flags), LengthNeeded) then
      Result := (Flags.dwFlags and WSF_VISIBLE) <> 0;
  end;
  {$ELSE}
  // Non-Windows, non-console → assume GUI (FMX on macOS/Linux/mobile)
  Result := True;
  {$ENDIF}
  {$ENDIF}
end;

procedure ExeWatchRegisterFrameworkHook;
begin
  GFrameworkHookInstalled := True;
end;

procedure ExeWatchExceptProc(ExceptObject: TObject; ExceptAddr: Pointer);
var
  E: Exception;
  ExtraData: TJSONObject;
begin
  // Prevent re-entry if exception during logging (thread-safe with TInterlocked)
  // TInterlocked.CompareExchange returns the original value; if it was already 1, another thread is handling
  if TInterlocked.CompareExchange(GExceptionHandlingInProgress, 1, 0) = 1 then
  begin
    // Another thread is already handling an exception, just call old handler
    if Assigned(GOldExceptProc) then
      GOldExceptProc(ExceptObject, ExceptAddr);
    Exit;
  end;

  try
    // Log the exception if SDK is initialized
    if ExeWatchIsInitialized then
    begin
      ExtraData := TJSONObject.Create;
      try
        ExtraData.AddPair('exception_address', Format('$%p', [ExceptAddr]));
        ExtraData.AddPair('exception_source', 'unhandled');
        {$IFDEF MSWINDOWS}
        ExtraData.AddPair('stack_trace', GetStackTraceStr(3));
        {$ENDIF}

        if ExceptObject is Exception then
        begin
          E := Exception(ExceptObject);
          ExtraData.AddPair('exception_class', E.ClassName);
          GExeWatch.Log(llFatal, 'Unhandled exception: ' + GExeWatch.ScrubUserPaths(E.Message), 'exception', ExtraData);
        end
        else
        begin
          ExtraData.AddPair('exception_class', ExceptObject.ClassName);
          GExeWatch.Log(llFatal, 'Unhandled exception: ' + ExceptObject.ClassName, 'exception', ExtraData);
        end;

        // Force immediate flush since app is terminating
        GExeWatch.Flush;
      except
        // Silently ignore errors during exception logging
        ExtraData.Free;
      end;
    end;
  finally
    TInterlocked.Exchange(GExceptionHandlingInProgress, 0);
  end;

  // Call old handler if present
  if Assigned(GOldExceptProc) then
    GOldExceptProc(ExceptObject, ExceptAddr);
end;

procedure CheckAndWarnAboutFrameworkHook;
begin
  // Only warn if:
  // 1. SDK is initialized
  // 2. App is GUI (VCL/FMX)
  // 3. No framework hook is installed
  // (not IsLibrary): inside the DLL SDK the VCL/FMX hook advice is inapplicable
  // (a non-Delphi host can't add Delphi units); the host wires its own handler,
  // so suppress the false-alarm warning when running as a library.
  if ExeWatchIsInitialized and ExeWatchIsGUIApplication and (not GFrameworkHookInstalled)
     and (not IsLibrary) then
  begin
    GExeWatch.Warning(
      'GUI application detected but no VCL/FMX exception hook installed. ' +
      'Add ExeWatchSDKv1.VCL (for VCL apps) or ExeWatchSDKv1.FMX (for FMX apps) ' +
      'to your uses clause to capture GUI exceptions.',
      'exewatch'
    );
  end;
end;

{ TBreadcrumb }

class function TBreadcrumb.Create(ABreadcrumbType: TBreadcrumbType; const ACategory, AMessage: string;
  AData: TJSONObject): TBreadcrumb;
begin
  Result.Timestamp := TTimeZone.Local.ToUniversalTime(Now);
  Result.BreadcrumbType := ABreadcrumbType;
  Result.Category := ACategory;
  Result.Message := AMessage;
  Result.Data := AData;
end;

function TBreadcrumb.ToJSON: TJSONObject;
const
  BreadcrumbTypeNames: array[TBreadcrumbType] of string = (
    'click', 'navigation', 'http', 'console', 'custom', 'error',
    'query', 'transaction', 'user', 'system', 'file', 'state',
    'form', 'config', 'message', 'debug'
  );
begin
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', DateToISO8601(Timestamp, True));
  Result.AddPair('type', BreadcrumbTypeNames[BreadcrumbType]);
  Result.AddPair('category', Category);
  Result.AddPair('message', Message);
  if Data <> nil then
    Result.AddPair('data', Data.Clone as TJSONObject);
end;

{ TTimingEntry }

class function TTimingEntry.Create(const ATag: string; AMetadata: TJSONObject): TTimingEntry;
begin
  Result.StartTicks := TStopwatch.GetTimeStamp;  // High-precision timing
  Result.Tag := ATag;
  Result.Metadata := AMetadata;
  Result.SpanId := '';
  Result.TraceId := '';
  Result.ParentSpanId := '';
end;

// Nested timing traces: 16-hex random id (trace_id / span_id). Mirrors the
// session-id generation (a GUID with separators stripped, first 16 chars).
function ExeWatchGenerateId16: string;
begin
  Result := Copy(TGUID.NewGuid.ToString.Replace('-', '').Replace('{', '').Replace('}', ''), 1, 16);
end;

{ TMetricAccumulator }

class function TMetricAccumulator.CreateCounter(const AName, ATag: string): TMetricAccumulator;
begin
  Result.MetricType := 'counter';
  Result.Name := AName;
  Result.Tag := ATag;
  Result.Value := 0;
  Result.MinValue := 0;
  Result.MaxValue := 0;
  Result.SumValue := 0;
  Result.SampleCount := 0;
  Result.PeriodStart := Now;
end;

class function TMetricAccumulator.CreateGauge(const AName, ATag: string; AValue: Double): TMetricAccumulator;
begin
  Result.MetricType := 'gauge';
  Result.Name := AName;
  Result.Tag := ATag;
  Result.Value := AValue;
  Result.MinValue := AValue;
  Result.MaxValue := AValue;
  Result.SumValue := AValue;
  Result.SampleCount := 1;
  Result.PeriodStart := Now;
end;

{ TUserIdentity }

class function TUserIdentity.Create(const AId, AEmail, AName: string): TUserIdentity;
begin
  Result.Id := AId;
  Result.Email := AEmail;
  Result.Name := AName;
end;

function TUserIdentity.IsEmpty: Boolean;
begin
  Result := (Id = '') and (Email = '') and (Name = '');
end;

function TUserIdentity.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if Id <> '' then
    Result.AddPair('id', Id);
  if Email <> '' then
    Result.AddPair('email', Email);
  if Name <> '' then
    Result.AddPair('name', Name);
end;

{ TLogEvent }

class function TLogEvent.Create(ALevel: TEWLogLevel; const AMessage, ATag, ASessionId: string;
  AExtraData: TJSONObject): TLogEvent;
begin
  Result.Level := ALevel;
  Result.Message := AMessage;
  Result.Tag := ATag;
  Result.Timestamp := TTimeZone.Local.ToUniversalTime(Now);
  Result.ThreadId := EWCurrentThreadId;
  Result.ProcessId := TExeWatchHelper.GetCurrentProcessId;
  Result.SessionId := ASessionId;
  Result.ExtraData := AExtraData;
end;

class function TLogEvent.Create(ALevel: TEWLogLevel; const AMessage, ATag, ASessionId: string;
  ATimestamp: TDateTime; AThreadId: UInt64; AProcessId: Cardinal;
  AExtraData: TJSONObject): TLogEvent;
begin
  Result.Level := ALevel;
  Result.Message := AMessage;
  Result.Tag := ATag;
  Result.Timestamp := TTimeZone.Local.ToUniversalTime(ATimestamp);  // Convert local time to UTC
  Result.ThreadId := AThreadId;
  Result.ProcessId := AProcessId;
  Result.SessionId := ASessionId;
  Result.ExtraData := AExtraData;
end;

function TLogEvent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('level', LogLevelNames[Level]);
  Result.AddPair('message', Message);
  Result.AddPair('tag', Tag);
  Result.AddPair('timestamp', DateToISO8601(Timestamp, True));
  Result.AddPair('thread_id', TJSONNumber.Create(ThreadId));
  Result.AddPair('process_id', TJSONNumber.Create(ProcessId));
  Result.AddPair('session_id', SessionId);
  if ExtraData <> nil then
    Result.AddPair('extra_data', ExtraData.Clone as TJSONObject);
end;

class function TLogEvent.FromJSON(AJSON: TJSONObject): TLogEvent;
var
  LevelStr: string;
  ExtraDataJSON: TJSONObject;
  L: TEWLogLevel;
begin
  LevelStr := AJSON.GetValue<string>('level', 'info');
  Result.Level := llInfo;  // default
  for L := Low(TEWLogLevel) to High(TEWLogLevel) do
    if LogLevelNames[L] = LevelStr then
    begin
      Result.Level := L;
      Break;
    end;

  Result.Message := AJSON.GetValue<string>('message', '');
  Result.Tag := AJSON.GetValue<string>('tag', '');
  Result.Timestamp := ISO8601ToDate(AJSON.GetValue<string>('timestamp', ''), True);
  Result.ThreadId := AJSON.GetValue<UInt64>('thread_id', 0);
  Result.ProcessId := AJSON.GetValue<Cardinal>('process_id', 0);
  Result.SessionId := AJSON.GetValue<string>('session_id', '');

  if AJSON.TryGetValue<TJSONObject>('extra_data', ExtraDataJSON) then
    Result.ExtraData := ExtraDataJSON.Clone as TJSONObject
  else
    Result.ExtraData := nil;
end;

{ TDeviceInfo }

class function TDeviceInfo.CreateFromSystem(const AAppBinaryVersion: string): TDeviceInfo;
var
  VersionInfo: TAppVersionInfo;
begin
  Result.Hostname := TExeWatchHelper.GetHostname;
  Result.Username := TExeWatchHelper.GetUsername;
  Result.DeviceId := TExeWatchHelper.GetDeviceId;
  {$IFDEF MSWINDOWS}
  Result.OSType := 'windows';
  {$ELSE}
  {$IFDEF ANDROID}
  Result.OSType := 'android';
  {$ELSE}
  {$IFDEF LINUX}
  Result.OSType := 'linux';
  {$ELSE}
  {$IFDEF MACOS}
  Result.OSType := 'macos';
  {$ELSE}
  Result.OSType := 'unknown';
  {$ENDIF}
  {$ENDIF}
  {$ENDIF}
  {$ENDIF}
  Result.OSVersion := TExeWatchHelper.GetOSVersion;
  Result.TimezoneOffset := TExeWatchHelper.GetTimezoneOffset;
  Result.AppVersion := '';  // User-defined, set later if needed

  // Auto-detect app binary version from executable if not provided
  if AAppBinaryVersion <> '' then
    Result.AppBinaryVersion := AAppBinaryVersion
  else
  begin
    VersionInfo := TExeWatchHelper.GetAppVersionInfo;
    // Prefer FileVersion, fallback to ProductVersion, then 'not available'
    if VersionInfo.FileVersion <> '' then
      Result.AppBinaryVersion := VersionInfo.FileVersion
    else if VersionInfo.ProductVersion <> '' then
      Result.AppBinaryVersion := VersionInfo.ProductVersion
    else
      Result.AppBinaryVersion := 'not available';
  end;
end;

function TDeviceInfo.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('device_id', DeviceId);
  Result.AddPair('hostname', Hostname);
  Result.AddPair('username', Username);
  Result.AddPair('os_type', OSType);
  Result.AddPair('os_version', OSVersion);
  Result.AddPair('app_binary_version', AppBinaryVersion);
  if AppVersion <> '' then
    Result.AddPair('app_version', AppVersion);
  Result.AddPair('sdk_version', EXEWATCH_SDK_VERSION);
  if TimezoneOffset <> '' then
    Result.AddPair('timezone_offset', TimezoneOffset);
end;

class function TDeviceInfo.FromJSON(AJSON: TJSONObject): TDeviceInfo;
begin
  Result.DeviceId := AJSON.GetValue<string>('device_id', '');
  Result.Hostname := AJSON.GetValue<string>('hostname', '');
  Result.Username := AJSON.GetValue<string>('username', '');
  Result.OSType := AJSON.GetValue<string>('os_type', '');
  Result.OSVersion := AJSON.GetValue<string>('os_version', '');
  Result.AppBinaryVersion := AJSON.GetValue<string>('app_binary_version', '');
  Result.AppVersion := AJSON.GetValue<string>('app_version', '');
  Result.TimezoneOffset := AJSON.GetValue<string>('timezone_offset', '');
end;

{ TDiskInfo }

function TDiskInfo.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('drive', Drive);
  if VolumeName <> '' then
    Result.AddPair('volume_name', VolumeName);
  if FileSystem <> '' then
    Result.AddPair('file_system', FileSystem);
  Result.AddPair('total_bytes', TJSONNumber.Create(TotalBytes));
  Result.AddPair('free_bytes', TJSONNumber.Create(FreeBytes));
  if DriveType <> '' then
    Result.AddPair('drive_type', DriveType);
  if IsSSD >= 0 then
    Result.AddPair('is_ssd', EWJsonBool(IsSSD = 1));
end;

{ TMonitorInfo }

function TMonitorInfo.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Index));
  if Name <> '' then
    Result.AddPair('name', Name);
  Result.AddPair('width', TJSONNumber.Create(Width));
  Result.AddPair('height', TJSONNumber.Create(Height));
  if BitsPerPixel > 0 then
    Result.AddPair('bits_per_pixel', TJSONNumber.Create(BitsPerPixel));
  Result.AddPair('primary', EWJsonBool(Primary));
end;

{$IFDEF MSWINDOWS}
// ---------------------------------------------------------------------------
// A handful of facts that answer "why is this machine slow?" on their own.
//
// All of it is read once, at startup, for about 8 ms in total. Deliberately no
// WMI: a Win32_Processor query can block for seconds on a locked-down machine,
// and this runs while the host application is still starting. None of it needs
// administrator rights.
// ---------------------------------------------------------------------------
const
  EW_SM_REMOTESESSION = $1000;
  EW_IOCTL_STORAGE_QUERY_PROPERTY = $002D1400;
  EW_STORAGE_SEEK_PENALTY_PROPERTY = 7;
  EW_PROPERTY_STANDARD_QUERY = 0;
  EW_POWER_PROCESSOR_INFORMATION = 11;  // POWER_INFORMATION_LEVEL
  EW_GUID_PROCESSOR_SUBGROUP: TGUID = '{54533251-82BE-4824-96C1-47B60B740D00}';
  EW_GUID_PROCESSOR_THROTTLE_MAX: TGUID = '{BC5038F7-23E0-4960-96DA-33ABAF5935EC}';

type
  TEWProcessorPowerInformation = record
    Number: Cardinal;
    MaxMhz: Cardinal;
    CurrentMhz: Cardinal;
    MhzLimit: Cardinal;
    MaxIdleState: Cardinal;
    CurrentIdleState: Cardinal;
  end;

  TEWStoragePropertyQuery = record
    PropertyId: DWORD;
    QueryType: DWORD;
    AdditionalParameters: array[0..0] of Byte;
  end;

  TEWSeekPenaltyDescriptor = record
    Version: DWORD;
    Size: DWORD;
    IncursSeekPenalty: Boolean;
  end;

  TEWCallNtPowerInformation = function(InformationLevel: Integer;
    InputBuffer: Pointer; InputBufferSize: ULONG;
    OutputBuffer: Pointer; OutputBufferSize: ULONG): Integer; stdcall;
  TEWPowerGetActiveScheme = function(UserRootPowerKey: THandle;
    var ActivePolicyGuid: PGUID): DWORD; stdcall;
  TEWPowerReadACValueIndex = function(RootPowerKey: THandle;
    SchemeGuid, SubGroupGuid, PowerSettingGuid: PGUID;
    var ValueIndex: DWORD): DWORD; stdcall;

var
  GEWPowrProf: HMODULE = 0;
  GEWPowrProfTried: Boolean = False;

// powrprof.dll is loaded on demand rather than imported statically: a missing
// static import stops the host application from starting at all, and a
// monitoring SDK must never be the reason an app does not launch.
function EWPowrProf: HMODULE;
begin
  if not GEWPowrProfTried then
  begin
    // Handle first, flag second. Two loggers can be constructed at once (one
    // per tenant, say), and the other order lets the second thread see "already
    // tried" while the handle is still zero, losing the CPU fields for it.
    GEWPowrProf := LoadLibrary('powrprof.dll');
    GEWPowrProfTried := True;
  end;
  Result := GEWPowrProf;
end;

procedure EWGetCpuSpeed(ALogicalProcessors: Integer; out AMaxMhz, AMinCoreMhz: Integer);
var
  Call: TEWCallNtPowerInformation;
  Lib: HMODULE;
  Info: array of TEWProcessorPowerInformation;
  BufSize: Integer;
  I: Integer;
begin
  AMaxMhz := 0;
  AMinCoreMhz := 0;
  if ALogicalProcessors <= 0 then
    Exit;
  Lib := EWPowrProf;
  if Lib = 0 then
    Exit;
  Call := TEWCallNtPowerInformation(GetProcAddress(Lib, 'CallNtPowerInformation'));
  if not Assigned(Call) then
    Exit;

  SetLength(Info, ALogicalProcessors);
  BufSize := ALogicalProcessors * SizeOf(TEWProcessorPowerInformation);
  FillChar(Info[0], BufSize, 0);
  if Call(EW_POWER_PROCESSOR_INFORMATION, nil, 0, @Info[0], BufSize) <> 0 then
    Exit;

  for I := 0 to High(Info) do
  begin
    if Integer(Info[I].MaxMhz) > AMaxMhz then
      AMaxMhz := Integer(Info[I].MaxMhz);
    // MhzLimit is per core class, so on a hybrid CPU the lowest value is the
    // efficiency cores. It is a specification, not a live measurement.
    if (Info[I].MhzLimit > 0) and
       ((AMinCoreMhz = 0) or (Integer(Info[I].MhzLimit) < AMinCoreMhz)) then
      AMinCoreMhz := Integer(Info[I].MhzLimit);
  end;
end;

function EWGetCpuThrottleMaxPct: Integer;
var
  Lib: HMODULE;
  GetScheme: TEWPowerGetActiveScheme;
  ReadValue: TEWPowerReadACValueIndex;
  Scheme: PGUID;
  Value: DWORD;
begin
  Result := -1;
  Lib := EWPowrProf;
  if Lib = 0 then
    Exit;
  GetScheme := TEWPowerGetActiveScheme(GetProcAddress(Lib, 'PowerGetActiveScheme'));
  ReadValue := TEWPowerReadACValueIndex(GetProcAddress(Lib, 'PowerReadACValueIndex'));
  if not (Assigned(GetScheme) and Assigned(ReadValue)) then
    Exit;

  Scheme := nil;
  if GetScheme(0, Scheme) <> ERROR_SUCCESS then
    Exit;
  try
    Value := 0;
    if ReadValue(0, Scheme, @EW_GUID_PROCESSOR_SUBGROUP,
                 @EW_GUID_PROCESSOR_THROTTLE_MAX, Value) = ERROR_SUCCESS then
      Result := Integer(Value);
  finally
    LocalFree(HLOCAL(Scheme));
  end;
end;

function EWGetPowerSource: string;
var
  Status: TSystemPowerStatus;
begin
  Result := '';
  if not GetSystemPowerStatus(Status) then
    Exit;
  case Status.ACLineStatus of
    0: Result := 'battery';
    1: Result := 'ac';
  end;
end;

function EWGetDriveIsSSD(ADriveLetter: Char): Integer;
var
  H: THandle;
  Query: TEWStoragePropertyQuery;
  Descriptor: TEWSeekPenaltyDescriptor;
  Returned: DWORD;
begin
  Result := -1;
  // Zero desired access is enough for a property query, and it is what keeps
  // this working without administrator rights.
  H := CreateFile(PChar('\\.\' + ADriveLetter + ':'), 0,
                  FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    FillChar(Query, SizeOf(Query), 0);
    Query.PropertyId := EW_STORAGE_SEEK_PENALTY_PROPERTY;
    Query.QueryType := EW_PROPERTY_STANDARD_QUERY;
    FillChar(Descriptor, SizeOf(Descriptor), 0);
    Returned := 0;
    if DeviceIoControl(H, EW_IOCTL_STORAGE_QUERY_PROPERTY, @Query, SizeOf(Query),
                       @Descriptor, SizeOf(Descriptor), Returned, nil) then
    begin
      if Descriptor.IncursSeekPenalty then
        Result := 0
      else
        Result := 1;
    end;
  finally
    CloseHandle(H);
  end;
end;
{$ENDIF}

// The first "model name" of /proc/cpuinfo. The ARM layout has none: empty, and nothing is guessed.
function EWParseCpuModelName(const AText: string): string;
var
  Line: string;
  Colon: Integer;
begin
  Result := '';
  for Line in AText.Split([#10]) do
    if Line.StartsWith('model name') then
    begin
      Colon := Pos(':', Line);
      if Colon > 0 then
        Result := Trim(Copy(Line, Colon + 1, MaxInt));
      Exit;
    end;
end;

// Mounts that are the kernel talking to itself, not a disk: the same list as the Python and .NET SDKs.
function EWIsPseudoFileSystem(const AFileSystem: string): Boolean;
begin
  Result := MatchStr(AFileSystem, ['proc', 'sysfs', 'devtmpfs', 'tmpfs', 'devpts', 'cgroup', 'cgroup2',
    'pstore', 'securityfs', 'debugfs', 'hugetlbfs', 'mqueue', 'fusectl', 'binfmt_misc', 'autofs', 'tracefs',
    'configfs', 'efivarfs', 'bpf', 'nsfs', 'fuse.snapfuse']);
end;

// Shares: the size of one that no longer answers is a call that does not return.
function EWIsNetworkFileSystem(const AFileSystem: string): Boolean;
begin
  Result := MatchStr(AFileSystem, ['nfs', 'nfs4', 'cifs', 'smbfs', 'smb3', 'fuse.sshfs', '9p', 'ceph', 'glusterfs', 'afs']);
end;

// /proc/mounts writes a space, a tab, a newline and a backslash as a backslash and three octal digits.
function EWUnescapeMount(const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '\') and (I + 3 <= Length(AText)) and CharInSet(AText[I + 1], ['0'..'3']) and
       CharInSet(AText[I + 2], ['0'..'7']) and CharInSet(AText[I + 3], ['0'..'7']) then
    begin
      Result := Result + Char((Ord(AText[I + 1]) - 48) * 64 + (Ord(AText[I + 2]) - 48) * 8 + (Ord(AText[I + 3]) - 48));
      Inc(I, 4);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

// One line of /proc/mounts: device, mount point, file system, options and two numbers.
function EWParseMountLine(const ALine: string; out ADevice, AMountPoint, AFileSystem: string): Boolean;
var
  Fields: TArray<string>;
begin
  ADevice := '';
  AMountPoint := '';
  AFileSystem := '';
  Fields := ALine.Split([' ']);
  Result := (Length(Fields) >= 3) and (Fields[1] <> '') and (Fields[2] <> '');
  if Result then
  begin
    ADevice := EWUnescapeMount(Fields[0]);
    AMountPoint := EWUnescapeMount(Fields[1]);
    AFileSystem := Fields[2];
  end;
end;

// The disk behind a device ("sda1" -> "sda", "nvme0n1p2" -> "nvme0n1"), to ask the kernel whether it spins.
// Empty when it is not known. Virtual disks (vda, xvda) are not guessed at: their flag is whatever the
// hypervisor says, and "it spins" said about an SSD sends the diagnosis the wrong way.
function EWBlockDeviceName(const ADevice: string): string;
var
  Name: string;
  I: Integer;
begin
  Result := '';
  if not ADevice.StartsWith('/dev/') then
    Exit;
  Name := Copy(ADevice, 6, MaxInt);
  if (Name = '') or (Pos('/', Name) > 0) then
    Exit;
  if Name.StartsWith('nvme') or Name.StartsWith('mmcblk') then
  begin
    // The partition is a "p" and digits at the end, after a digit.
    I := Length(Name);
    while (I > 0) and CharInSet(Name[I], ['0'..'9']) do
      Dec(I);
    if (I > 1) and (I < Length(Name)) and (Name[I] = 'p') and CharInSet(Name[I - 1], ['0'..'9']) then
      Name := Copy(Name, 1, I - 1);
    Result := Name;
  end
  else if Name.StartsWith('sd') or Name.StartsWith('hd') then
  begin
    while (Name <> '') and CharInSet(Name[Length(Name)], ['0'..'9']) do
      SetLength(Name, Length(Name) - 1);
    if Length(Name) > 2 then
      Result := Name;
  end;
end;

{$IFDEF LINUX}
// ---------------------------------------------------------------------------
// The same "why is this machine slow?" facts, where Linux has an answer.
//
// Read from /sys, not /proc: the values are one number per file, and the CPU
// section of this unit already carries a note that reading /proc caused
// trouble. Every read is guarded, and a missing file leaves the field absent
// rather than guessed.
// ---------------------------------------------------------------------------
const
  EW_LINUX_CPU_SCAN_LIMIT = 512;   // stop walking cpuN long before /sys does

// Read one small integer out of a /sys or /proc file.
//
// Deliberately POSIX I/O and not TStringList or TFile: files under /sys and
// /proc report a size of zero, and the RTL readers that trust that size raise
// ERangeError on them. That is a documented trap in this SDK, see the Linux
// notes in docs/sdk-roadmap.md, and it is why CPU name and core count are
// still missing on Linux.
function EWReadSysInt(const APath: string; out AValue: Int64): Boolean;
var
  Handle: Integer;
  Buffer: array[0..63] of Byte;
  Count: NativeInt;
begin
  Result := False;
  AValue := 0;
  Handle := open(PAnsiChar(AnsiString(APath)), O_RDONLY);
  if Handle < 0 then
    Exit;
  try
    FillChar(Buffer, SizeOf(Buffer), 0);
    Count := __read(Handle, @Buffer[0], SizeOf(Buffer) - 1);
    if Count <= 0 then
      Exit;
    Result := TryStrToInt64(Trim(string(AnsiString(PAnsiChar(@Buffer[0])))), AValue);
  finally
    __close(Handle);
  end;
end;

// A whole /proc or /sys text file, by POSIX I/O for the same reason as above: the size it reports is zero.
function EWReadSysText(const APath: string; AMaxBytes: Integer; out AText: string): Boolean;
var
  Handle: Integer;
  Bytes: TBytes;
  Total: Integer;
  Count: NativeInt;
begin
  Result := False;
  AText := '';
  Handle := open(PAnsiChar(AnsiString(APath)), O_RDONLY);
  if Handle < 0 then
    Exit;
  try
    SetLength(Bytes, AMaxBytes);
    Total := 0;
    while Total < AMaxBytes do
    begin
      Count := __read(Handle, @Bytes[Total], AMaxBytes - Total);
      if Count <= 0 then
        Break;
      Inc(Total, Integer(Count));
    end;
    SetLength(Bytes, Total);
    AText := TEncoding.UTF8.GetString(Bytes);
    Result := Total > 0;
  finally
    __close(Handle);
  end;
end;

function EWLinuxGetCpuName: string;
var
  Text: string;
begin
  Result := '';
  // The name is in the first block of the file: no need to read every core.
  if EWReadSysText('/proc/cpuinfo', 65536, Text) then
    Result := EWParseCpuModelName(Text);
end;

// The disks, as the Python and .NET SDKs list them: the real mounts of /proc/mounts, with the size from statvfs.
function EWLinuxGetDisks: TArray<TDiskInfo>;
var
  Text, Device, MountPoint, FileSystem, BlockName: string;
  Line: string;
  Seen: TStringList;
  List: TList<TDiskInfo>;
  Stat: _statvfs;
  Disk: TDiskInfo;
  Total: Int64;
  Rotational: Int64;
begin
  SetLength(Result, 0);
  if not EWReadSysText('/proc/mounts', 262144, Text) then
    Exit;
  Seen := TStringList.Create;
  Seen.CaseSensitive := True;  // /mnt/Data and /mnt/data are two mounts
  List := TList<TDiskInfo>.Create;
  try
    for Line in Text.Split([#10]) do
    begin
      if not EWParseMountLine(Line, Device, MountPoint, FileSystem) then
        Continue;
      if EWIsPseudoFileSystem(FileSystem) or (Seen.IndexOf(MountPoint) >= 0) then
        Continue;
      // InitializeExeWatch collects the disks on the caller's thread: a share that no longer answers
      // must not hold the application at start-up, so a network mount is not asked for its size.
      if EWIsNetworkFileSystem(FileSystem) then
        Continue;
      FillChar(Stat, SizeOf(Stat), 0);
      if statvfs(PAnsiChar(AnsiString(MountPoint)), Stat) <> 0 then
        Continue;
      Total := Int64(Stat.f_blocks) * Int64(Stat.f_frsize);
      if Total = 0 then
        Continue;
      Seen.Add(MountPoint);

      Disk := Default(TDiskInfo);
      Disk.Drive := MountPoint;
      Disk.VolumeName := Device;
      Disk.FileSystem := FileSystem;
      Disk.TotalBytes := Total;
      Disk.FreeBytes := Int64(Stat.f_bfree) * Int64(Stat.f_frsize);
      Disk.DriveType := 'Fixed';
      Disk.IsSSD := -1;
      // 0 = solid state, 1 = it spins, in the kernel's own words. Absent when the device is not known.
      BlockName := EWBlockDeviceName(Device);
      if (BlockName <> '') and EWReadSysInt('/sys/block/' + BlockName + '/queue/rotational', Rotational) then
      begin
        if Rotational = 0 then
          Disk.IsSSD := 1
        else if Rotational = 1 then
          Disk.IsSSD := 0;
      end;
      List.Add(Disk);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

procedure EWLinuxGetCpuSpeed(out AMaxMhz, AMinCoreMhz, AThrottleMaxPct: Integer);
var
  I, Misses: Integer;
  Dir: string;
  Nominal, Scaling: Int64;
  MaxNominalKHz, MinNominalKHz, MaxScalingKHz: Int64;
begin
  AMaxMhz := 0;
  AMinCoreMhz := 0;
  AThrottleMaxPct := -1;
  MaxNominalKHz := 0;
  MinNominalKHz := 0;
  MaxScalingKHz := 0;
  Misses := 0;

  for I := 0 to EW_LINUX_CPU_SCAN_LIMIT - 1 do
  begin
    Dir := Format('/sys/devices/system/cpu/cpu%d/cpufreq/', [I]);
    if not DirectoryExists(Dir) then
    begin
      // A run of missing entries means either the end of the list or a machine
      // with no cpufreq at all, which is the common case inside a VM. A short
      // tolerance covers an offline core without walking all 512.
      Inc(Misses);
      if Misses >= 4 then
        Break;
      Continue;
    end;
    Misses := 0;

    // base_frequency is the nominal clock and matches what Windows reports.
    // cpuinfo_max_freq includes boost, so it is only the fallback: better a
    // slightly different meaning than no number at all.
    if not EWReadSysInt(Dir + 'base_frequency', Nominal) then
      if not EWReadSysInt(Dir + 'cpuinfo_max_freq', Nominal) then
        Nominal := 0;

    if Nominal > 0 then
    begin
      if Nominal > MaxNominalKHz then
        MaxNominalKHz := Nominal;
      if (MinNominalKHz = 0) or (Nominal < MinNominalKHz) then
        MinNominalKHz := Nominal;
    end;

    // What the governor currently allows. Below the nominal clock it is the
    // Linux equivalent of a power plan holding the processor down.
    if EWReadSysInt(Dir + 'scaling_max_freq', Scaling) and (Scaling > MaxScalingKHz) then
      MaxScalingKHz := Scaling;
  end;

  AMaxMhz := Integer(MaxNominalKHz div 1000);
  AMinCoreMhz := Integer(MinNominalKHz div 1000);
  if (MaxNominalKHz > 0) and (MaxScalingKHz > 0) then
    AThrottleMaxPct := Integer(Round(MaxScalingKHz / MaxNominalKHz * 100));
end;
{$ENDIF}

{ THardwareInfo }

class function THardwareInfo.Collect: THardwareInfo;
{$IFDEF MSWINDOWS}
const
  PROCESSOR_ARCHITECTURE_ARM64_LOCAL = 12;
  ENUM_CURRENT_SETTINGS = DWORD(-1);
var
  MemStatus: TMemoryStatusEx;
  SysInfo: TSystemInfo;
  DriveBits: DWORD;
  DriveChar: Char;
  DriveRoot: string;
  DriveTypeVal: UINT;
  VolumeNameBuf: array[0..MAX_PATH] of Char;
  FileSystemBuf: array[0..MAX_PATH] of Char;
  TotalBytesVal, FreeBytesVal: Int64;
  DiskInfoRec: TDiskInfo;
  DevMode: TDevMode;
  MonIdx: Integer;
  MonInfo: TMonitorInfo;
  Reg: TRegistry;
  TickCount64Val: UInt64;
  BootTime: TDateTime;
  WSADataRec: TWSAData;
  HostNameBuf: array[0..255] of AnsiChar;
  HostEnt: PHostEnt;
  AddrList: ^PInAddr;
  TZInfo: TTimeZoneInformation;
  LangIDVal: DWORD;
  LangName: array[0..255] of Char;
  VolSerial, MaxCompLen, FSFlags: DWORD;
  // For CPU core counting
  CPUBufferSize: DWORD;
  CPUBuffer: PSystemLogicalProcessorInformation;
  CPUPtr: PSystemLogicalProcessorInformation;
  CPUBytesRead: DWORD;
  // For monitor enumeration
  DisplayDevice: TDisplayDevice;
  // For floppy / empty-removable-drive "No Disk" popup suppression
  OldErrorMode: DWORD;
begin
  // Memory
  MemStatus.dwLength := SizeOf(MemStatus);
  GlobalMemoryStatusEx(MemStatus);
  Result.TotalPhysicalMemory := Int64(MemStatus.ullTotalPhys);
  Result.AvailablePhysicalMemory := Int64(MemStatus.ullAvailPhys);

  // CPU
  GetNativeSystemInfo(SysInfo);
  Result.CPUCores := 0; // Will be filled from registry
  Result.CPULogicalProcessors := Integer(SysInfo.dwNumberOfProcessors);

  case SysInfo.wProcessorArchitecture of
    PROCESSOR_ARCHITECTURE_AMD64: Result.CPUArchitecture := 'x64';
    PROCESSOR_ARCHITECTURE_INTEL: Result.CPUArchitecture := 'x86';
    PROCESSOR_ARCHITECTURE_ARM64_LOCAL: Result.CPUArchitecture := 'ARM64';
    PROCESSOR_ARCHITECTURE_ARM: Result.CPUArchitecture := 'ARM';
  else
    Result.CPUArchitecture := 'Unknown';
  end;

  // Get CPU name from registry
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\HARDWARE\DESCRIPTION\System\CentralProcessor\0') then
    begin
      Result.CPUName := Reg.ReadString('ProcessorNameString');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

  // Get physical core count using GetLogicalProcessorInformation
  Result.CPUCores := 0;
  CPUBufferSize := 0;
  GetLogicalProcessorInformation(nil, CPUBufferSize);
  if (GetLastError = ERROR_INSUFFICIENT_BUFFER) and (CPUBufferSize > 0) then
  begin
    GetMem(CPUBuffer, CPUBufferSize);
    try
      if GetLogicalProcessorInformation(CPUBuffer, CPUBufferSize) then
      begin
        CPUPtr := CPUBuffer;
        CPUBytesRead := 0;
        while CPUBytesRead < CPUBufferSize do
        begin
          if CPUPtr.Relationship = RelationProcessorCore then
            Inc(Result.CPUCores);
          Inc(CPUPtr);
          Inc(CPUBytesRead, SizeOf(TSystemLogicalProcessorInformation));
        end;
      end;
    finally
      FreeMem(CPUBuffer);
    end;
  end;
  if Result.CPUCores = 0 then
    Result.CPUCores := Result.CPULogicalProcessors; // Fallback

  // Why is this machine slow? The clock is only a denominator, useful for
  // comparing machines and normalising timings. The three that follow answer
  // the question on their own.
  EWGetCpuSpeed(Result.CPULogicalProcessors, Result.CPUMaxMhz, Result.CPUMinCoreMhz);
  Result.CPUThrottleMaxPct := EWGetCpuThrottleMaxPct;
  Result.PowerSource := EWGetPowerSource;
  if GetSystemMetrics(EW_SM_REMOTESESSION) <> 0 then
    Result.RemoteSession := 1
  else
    Result.RemoteSession := 0;

  // Disks
  //
  // GetVolumeInformation / GetDiskFreeSpaceEx on an empty removable drive
  // (e.g. a physical floppy with no media) trigger the Windows "No Disk"
  // critical-error popup ("Exception Processing Message 0xc0000013").
  // We suppress it for this thread for the duration of the enumeration,
  // and skip A:/B: which are historically reserved for floppies and bring
  // no useful information to an APM device profile.
  SetLength(Result.Disks, 0);
  OldErrorMode := 0;
  SetThreadErrorMode(EW_SEM_FAILCRITICALERRORS or EW_SEM_NOOPENFILEERRORBOX,
    @OldErrorMode);
  try
    DriveBits := GetLogicalDrives;
    for DriveChar := 'A' to 'Z' do
    begin
      if (DriveBits and 1) = 1 then
      begin
        // Skip floppy-reserved letters unconditionally
        if (DriveChar = 'A') or (DriveChar = 'B') then
        begin
          DriveBits := DriveBits shr 1;
          Continue;
        end;

        DriveRoot := DriveChar + ':\';
        DriveTypeVal := GetDriveType(PChar(DriveRoot));

        // Only include fixed and removable drives
        if DriveTypeVal in [DRIVE_REMOVABLE, DRIVE_FIXED, DRIVE_REMOTE, DRIVE_RAMDISK] then
        begin
          DiskInfoRec.Drive := DriveChar + ':';

          // A network drive is listed but never queried: on a mapped share whose
          // server is unreachable (a laptop away from the office) each call waits
          // for the SMB timeout, tens of seconds, on the host's startup thread.
          FillChar(VolumeNameBuf, SizeOf(VolumeNameBuf), 0);
          FillChar(FileSystemBuf, SizeOf(FileSystemBuf), 0);
          VolSerial := 0;
          MaxCompLen := 0;
          FSFlags := 0;
          if (DriveTypeVal <> DRIVE_REMOTE) and
            GetVolumeInformation(PChar(DriveRoot), VolumeNameBuf, MAX_PATH,
              @VolSerial, MaxCompLen, FSFlags, FileSystemBuf, MAX_PATH) then
          begin
            DiskInfoRec.VolumeName := VolumeNameBuf;
            DiskInfoRec.FileSystem := FileSystemBuf;
          end
          else
          begin
            DiskInfoRec.VolumeName := '';
            DiskInfoRec.FileSystem := '';
          end;

          // Get disk space
          FreeBytesVal := 0;
          TotalBytesVal := 0;
          if DriveTypeVal <> DRIVE_REMOTE then
            GetDiskFreeSpaceEx(PChar(DriveRoot), FreeBytesVal, TotalBytesVal, nil);
          DiskInfoRec.TotalBytes := TotalBytesVal;
          DiskInfoRec.FreeBytes := FreeBytesVal;

          case DriveTypeVal of
            DRIVE_REMOVABLE: DiskInfoRec.DriveType := 'Removable';
            DRIVE_FIXED: DiskInfoRec.DriveType := 'Fixed';
            DRIVE_REMOTE: DiskInfoRec.DriveType := 'Network';
            DRIVE_CDROM: DiskInfoRec.DriveType := 'CDRom';
            DRIVE_RAMDISK: DiskInfoRec.DriveType := 'RamDisk';
          else
            DiskInfoRec.DriveType := 'Unknown';
          end;

          // Only local disks: asking a network share or a CD whether it seeks
          // means waking hardware for an answer that would mean nothing.
          if DriveTypeVal = DRIVE_FIXED then
            DiskInfoRec.IsSSD := EWGetDriveIsSSD(DriveChar)
          else
            DiskInfoRec.IsSSD := -1;

          SetLength(Result.Disks, Length(Result.Disks) + 1);
          Result.Disks[High(Result.Disks)] := DiskInfoRec;
        end;
      end;
      DriveBits := DriveBits shr 1;
    end;
  finally
    SetThreadErrorMode(OldErrorMode, nil);
  end;

  // Monitors - enumerate physical display devices
  SetLength(Result.Monitors, 0);
  MonIdx := 0;
  while True do
  begin
    FillChar(DisplayDevice, SizeOf(DisplayDevice), 0);
    DisplayDevice.cb := SizeOf(DisplayDevice);

    if not EnumDisplayDevices(nil, Cardinal(MonIdx), DisplayDevice, 0) then
      Break;

    // Only include active monitors (attached to desktop)
    if (DisplayDevice.StateFlags and DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) <> 0 then
    begin
      // Get current display settings for this device
      FillChar(DevMode, SizeOf(DevMode), 0);
      DevMode.dmSize := SizeOf(DevMode);
      if EnumDisplaySettings(@DisplayDevice.DeviceName[0], ENUM_CURRENT_SETTINGS, DevMode) then
      begin
        MonInfo.Index := Length(Result.Monitors);
        MonInfo.Name := DisplayDevice.DeviceString;
        MonInfo.Width := Integer(DevMode.dmPelsWidth);
        MonInfo.Height := Integer(DevMode.dmPelsHeight);
        MonInfo.BitsPerPixel := Integer(DevMode.dmBitsPerPel);
        MonInfo.Primary := (DisplayDevice.StateFlags and DISPLAY_DEVICE_PRIMARY_DEVICE) <> 0;

        SetLength(Result.Monitors, Length(Result.Monitors) + 1);
        Result.Monitors[High(Result.Monitors)] := MonInfo;
      end;
    end;

    Inc(MonIdx);
    if MonIdx > 32 then Break; // Safety limit (32 monitors should be enough)
  end;

  // Paths
  Result.ExecutablePath := ParamStr(0);
  Result.WorkingDirectory := GetCurrentDir;
  Result.CommandLine := GetCommandLine;

  // System boot time
  try
    TickCount64Val := EWGetTickCount64;
    BootTime := Now - (TickCount64Val / (1000 * 60 * 60 * 24));
    Result.SystemBootTime := TTimeZone.Local.ToUniversalTime(BootTime);
  except
    Result.SystemBootTime := 0;
  end;

  // Local IP addresses
  SetLength(Result.LocalIPAddresses, 0);
  if WSAStartup($0202, WSADataRec) = 0 then
  try
    if Winapi.WinSock.gethostname(HostNameBuf, SizeOf(HostNameBuf)) = 0 then
    begin
      HostEnt := gethostbyname(HostNameBuf);
      if HostEnt <> nil then
      begin
        AddrList := Pointer(HostEnt^.h_addr_list);
        while AddrList^ <> nil do
        begin
          SetLength(Result.LocalIPAddresses, Length(Result.LocalIPAddresses) + 1);
          Result.LocalIPAddresses[High(Result.LocalIPAddresses)] :=
            string(AnsiString(inet_ntoa(AddrList^^)));
          Inc(AddrList);
        end;
      end;
    end;
  finally
    WSACleanup;
  end;

  // Timezone
  try
    case GetTimeZoneInformation(TZInfo) of
      TIME_ZONE_ID_STANDARD: Result.Timezone := TZInfo.StandardName;
      TIME_ZONE_ID_DAYLIGHT: Result.Timezone := TZInfo.DaylightName;
    else
      Result.Timezone := TZInfo.StandardName;
    end;
  except
    Result.Timezone := '';
  end;

  // System language
  LangIDVal := GetUserDefaultUILanguage;
  if GetLocaleInfo(LangIDVal, LOCALE_SENGLANGUAGE, LangName, SizeOf(LangName)) > 0 then
    Result.SystemLanguage := LangName
  else
    Result.SystemLanguage := '';

  // System locale
  if GetLocaleInfo(LOCALE_USER_DEFAULT, LOCALE_SNAME, LangName, SizeOf(LangName)) > 0 then
    Result.SystemLocale := LangName
  else
    Result.SystemLocale := '';

  // Application version info from executable
  Result.AppVersionInfo := TAppVersionInfo.GetFromFile(ParamStr(0));
end;
{$ELSE}
{$IFDEF ANDROID}
var
  ActivityManager: JObject;
  MemInfo: JActivityManager_MemoryInfo;
  Config: JConfiguration;
  DensityDpi: Integer;
begin
  // Memory via ActivityManager
  Result.TotalPhysicalMemory := 0;
  Result.AvailablePhysicalMemory := 0;
  try
    ActivityManager := TAndroidHelper.Context.getSystemService(
      TJContext.JavaClass.ACTIVITY_SERVICE);
    if ActivityManager <> nil then
    begin
      MemInfo := TJActivityManager_MemoryInfo.JavaClass.init;
      TJActivityManager.Wrap(ActivityManager).getMemoryInfo(MemInfo);
      Result.TotalPhysicalMemory := MemInfo.totalMem;
      Result.AvailablePhysicalMemory := MemInfo.availMem;
    end;
  except
    // Ignore errors
  end;

  // CPU info from Build
  try
    Result.CPUName := JStringToString(TJBuild.JavaClass.HARDWARE);
  except
    Result.CPUName := '';
  end;
  Result.CPUCores := TThread.ProcessorCount;
  Result.CPULogicalProcessors := TThread.ProcessorCount;

  // CPU Architecture
  {$IFDEF CPUARM64}
  Result.CPUArchitecture := 'ARM64';
  {$ELSE}
  {$IFDEF CPUARM}
  Result.CPUArchitecture := 'ARM';
  {$ELSE}
  Result.CPUArchitecture := 'Unknown';
  {$ENDIF}
  {$ENDIF}

  // Not available on this platform. Absent rather than wrong: the backend
  // treats every one of these as optional.
  Result.CPUMaxMhz := 0;
  Result.CPUMinCoreMhz := 0;
  Result.CPUThrottleMaxPct := -1;
  Result.PowerSource := '';
  Result.RemoteSession := -1;

  SetLength(Result.Disks, 0);

  // Screen info via Configuration (screenWidthDp * densityDpi / 160 = pixels)
  SetLength(Result.Monitors, 1);
  try
    Config := TAndroidHelper.Context.getResources.getConfiguration;
    DensityDpi := Config.densityDpi;
    Result.Monitors[0].Index := 0;
    Result.Monitors[0].Name := JStringToString(TJBuild.JavaClass.MODEL);
    Result.Monitors[0].Width := (Config.screenWidthDp * DensityDpi) div 160;
    Result.Monitors[0].Height := (Config.screenHeightDp * DensityDpi) div 160;
    Result.Monitors[0].BitsPerPixel := 32;
    Result.Monitors[0].Primary := True;
  except
    SetLength(Result.Monitors, 0);
  end;

  // Paths
  Result.ExecutablePath := ParamStr(0);
  Result.WorkingDirectory := '';
  Result.CommandLine := '';

  // Boot time not easily available
  Result.SystemBootTime := 0;

  SetLength(Result.LocalIPAddresses, 0);

  // Timezone
  try
    Result.Timezone := TTimeZone.Local.DisplayName;
  except
    Result.Timezone := '';
  end;

  // Language/Locale
  try
    Result.SystemLanguage := JStringToString(
      TJLocale.JavaClass.getDefault.getLanguage);
    Result.SystemLocale := JStringToString(
      TJLocale.JavaClass.getDefault.toString);
  except
    Result.SystemLanguage := '';
    Result.SystemLocale := '';
  end;

  // App version from PackageManager (via GetAppVersionInfo)
  Result.AppVersionInfo := TExeWatchHelper.GetAppVersionInfo;
end;
{$ELSE}
{$IFDEF LINUX}
var
  I: Integer;
  Info: TSysInfo;
begin
  // Memory using sysinfo (libc call)
  Result.TotalPhysicalMemory := 0;
  Result.AvailablePhysicalMemory := 0;
  try
    FillChar(Info, SizeOf(Info), 0);
    if sysinfo(@Info) = 0 then
    begin
      Result.TotalPhysicalMemory := Int64(Info.totalram) * Int64(Info.mem_unit);
      Result.AvailablePhysicalMemory := Int64(Info.freeram) * Int64(Info.mem_unit);
    end;
  except
    // Ignore errors
  end;

  // The name comes from /proc/cpuinfo (EWLinuxGetCpuName). The counts do not need it:
  // TThread.ProcessorCount goes through sysconf, which is what the Android branch of
  // this function already relies on.
  Result.CPUName := EWLinuxGetCpuName;
  Result.CPUCores := TThread.ProcessorCount;
  Result.CPULogicalProcessors := TThread.ProcessorCount;

  // CPU Architecture
  {$IFDEF CPUX64}
  Result.CPUArchitecture := 'x64';
  {$ELSE}
  {$IFDEF CPUX86}
  Result.CPUArchitecture := 'x86';
  {$ELSE}
  {$IFDEF CPUARM64}
  Result.CPUArchitecture := 'ARM64';
  {$ELSE}
  {$IFDEF CPUARM}
  Result.CPUArchitecture := 'ARM';
  {$ELSE}
  Result.CPUArchitecture := 'Unknown';
  {$ENDIF}
  {$ENDIF}
  {$ENDIF}

  EWLinuxGetCpuSpeed(Result.CPUMaxMhz, Result.CPUMinCoreMhz, Result.CPUThrottleMaxPct);
  // No battery on a Linux server, and reporting "ac" for every one of them says
  // nothing.
  Result.PowerSource := '';
  Result.RemoteSession := -1;
  {$ENDIF}

  SetLength(Result.Disks, 0);
  SetLength(Result.Monitors, 0);
  {$IFDEF LINUX}
  Result.Disks := EWLinuxGetDisks;
  {$ENDIF}

  // Paths
  Result.ExecutablePath := ParamStr(0);
  Result.WorkingDirectory := GetCurrentDir;
  Result.CommandLine := '';
  for I := 0 to ParamCount do
  begin
    if I > 0 then
      Result.CommandLine := Result.CommandLine + ' ';
    Result.CommandLine := Result.CommandLine + ParamStr(I);
  end;

  // Boot time from sysinfo uptime
  try
    if Info.uptime > 0 then
      Result.SystemBootTime := Now - (Info.uptime / SecsPerDay)
    else
      Result.SystemBootTime := 0;
  except
    Result.SystemBootTime := 0;
  end;

  SetLength(Result.LocalIPAddresses, 0);

  // Timezone
  try
    Result.Timezone := TTimeZone.Local.DisplayName;
  except
    Result.Timezone := '';
  end;

  // Language/Locale from environment
  Result.SystemLanguage := GetEnvironmentVariable('LANG');
  Result.SystemLocale := GetEnvironmentVariable('LC_ALL');
  if Result.SystemLocale = '' then
    Result.SystemLocale := Result.SystemLanguage;

  // No version info on Linux
  Result.AppVersionInfo := Default(TAppVersionInfo);
end;
{$ELSE}
begin
  // Non-Windows/Non-Linux: minimal info
  Result.TotalPhysicalMemory := 0;
  Result.AvailablePhysicalMemory := 0;
  Result.CPUName := '';
  Result.CPUCores := 0;
  Result.CPULogicalProcessors := 0;
  Result.CPUArchitecture := '';

  // Not available on this platform. Absent rather than wrong: the backend
  // treats every one of these as optional.
  Result.CPUMaxMhz := 0;
  Result.CPUMinCoreMhz := 0;
  Result.CPUThrottleMaxPct := -1;
  Result.PowerSource := '';
  Result.RemoteSession := -1;
  SetLength(Result.Disks, 0);
  SetLength(Result.Monitors, 0);
  Result.ExecutablePath := ParamStr(0);
  Result.WorkingDirectory := GetCurrentDir;
  Result.CommandLine := '';
  Result.SystemBootTime := 0;
  SetLength(Result.LocalIPAddresses, 0);
  Result.Timezone := '';
  Result.SystemLanguage := '';
  Result.SystemLocale := '';
end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

function THardwareInfo.ToJSON: TJSONObject;
var
  DisksArray, MonitorsArray, IPsArray: TJSONArray;
  Disk: TDiskInfo;
  Mon: TMonitorInfo;
  IP: string;
begin
  Result := TJSONObject.Create;

  // Memory
  if TotalPhysicalMemory > 0 then
    Result.AddPair('total_physical_memory', TJSONNumber.Create(TotalPhysicalMemory));
  if AvailablePhysicalMemory > 0 then
    Result.AddPair('available_physical_memory', TJSONNumber.Create(AvailablePhysicalMemory));

  // CPU
  if CPUName <> '' then
    Result.AddPair('cpu_name', CPUName);
  if CPUCores > 0 then
    Result.AddPair('cpu_cores', TJSONNumber.Create(CPUCores));
  if CPULogicalProcessors > 0 then
    Result.AddPair('cpu_logical_processors', TJSONNumber.Create(CPULogicalProcessors));
  if CPUArchitecture <> '' then
    Result.AddPair('cpu_architecture', CPUArchitecture);
  if CPUMaxMhz > 0 then
    Result.AddPair('cpu_max_mhz', TJSONNumber.Create(CPUMaxMhz));
  if CPUMinCoreMhz > 0 then
    Result.AddPair('cpu_min_core_mhz', TJSONNumber.Create(CPUMinCoreMhz));
  if CPUThrottleMaxPct >= 0 then
    Result.AddPair('cpu_throttle_max_pct', TJSONNumber.Create(CPUThrottleMaxPct));
  if PowerSource <> '' then
    Result.AddPair('power_source', PowerSource);
  if RemoteSession >= 0 then
    Result.AddPair('remote_session', EWJsonBool(RemoteSession = 1));

  // Disks
  if Length(Disks) > 0 then
  begin
    DisksArray := TJSONArray.Create;
    for Disk in Disks do
      DisksArray.AddElement(Disk.ToJSON);
    Result.AddPair('disks', DisksArray);
  end;

  // Monitors
  if Length(Monitors) > 0 then
  begin
    MonitorsArray := TJSONArray.Create;
    for Mon in Monitors do
      MonitorsArray.AddElement(Mon.ToJSON);
    Result.AddPair('monitors', MonitorsArray);
  end;

  // Paths
  if ExecutablePath <> '' then
    Result.AddPair('executable_path', ExecutablePath);
  if WorkingDirectory <> '' then
    Result.AddPair('working_directory', WorkingDirectory);
  if CommandLine <> '' then
    Result.AddPair('command_line', CommandLine);

  // System
  if SystemBootTime > 0 then
    Result.AddPair('system_boot_time', DateToISO8601(SystemBootTime, True));

  if Length(LocalIPAddresses) > 0 then
  begin
    IPsArray := TJSONArray.Create;
    for IP in LocalIPAddresses do
      IPsArray.Add(IP);
    Result.AddPair('local_ip_addresses', IPsArray);
  end;

  if Timezone <> '' then
    Result.AddPair('timezone', Timezone);
  if SystemLanguage <> '' then
    Result.AddPair('system_language', SystemLanguage);
  if SystemLocale <> '' then
    Result.AddPair('system_locale', SystemLocale);

  // Application version info
  if (AppVersionInfo.FileVersion <> '') or (AppVersionInfo.ProductName <> '') then
    Result.AddPair('app_version_info', AppVersionInfo.ToJSON);
end;

procedure THardwareInfo.Anonymize(const ARoots: TArray<TEWPathRoot>; ACaseSensitive: Boolean);
var
  I: Integer;
begin
  ExecutablePath := TExeWatchHelper.ScrubUserPaths(ExecutablePath, ARoots, ACaseSensitive);
  WorkingDirectory := TExeWatchHelper.ScrubUserPaths(WorkingDirectory, ARoots, ACaseSensitive);
  CommandLine := TExeWatchHelper.ScrubUserPaths(CommandLine, ARoots, ACaseSensitive);
  // A private address says where the person is; nothing in the diagnosis needs it.
  SetLength(LocalIPAddresses, 0);
  // A volume label is whatever its owner typed: "BOBS DISK".
  for I := 0 to High(Disks) do
  begin
    Disks[I].VolumeName := '';
    // On Linux a removable disk is mounted under the login's own folder.
    Disks[I].Drive := TExeWatchHelper.ScrubUserPaths(Disks[I].Drive, ARoots, ACaseSensitive);
    // What follows the media folder is the disk's label ("/media/bob/BOBS DISK"): it goes too.
    if Disks[I].Drive.StartsWith('[MEDIA]') then
      Disks[I].Drive := '[MEDIA]';
  end;
end;

{ TExeWatchConfig }

class function TExeWatchConfig.Create(const AApiKey, ACustomerId: string): TExeWatchConfig;
begin
  Result.ApiKey := AApiKey;
  Result.CustomerId := ACustomerId;
  Result.BufferSize := EXEWATCH_DEFAULT_BUFFER_SIZE;
  Result.FlushIntervalMs := EXEWATCH_DEFAULT_FLUSH_INTERVAL_MS;
  Result.RetryIntervalMs := EXEWATCH_DEFAULT_RETRY_INTERVAL_MS;
  Result.StoragePath := TExeWatchHelper.GetDefaultStoragePath(AApiKey);
  Result.DeviceInfo := TDeviceInfo.CreateFromSystem;
  Result.SampleRate := EXEWATCH_DEFAULT_SAMPLE_RATE;
  Result.AppBinaryVersion := '';  // Empty = auto-detect (already done in CreateFromSystem)
  Result.AppVersion := '';        // User-defined version, empty by default
  Result.GaugeSamplingIntervalSec := EXEWATCH_DEFAULT_GAUGE_SAMPLING_INTERVAL_SEC;
  Result.MaxPendingAgeDays := EXEWATCH_DEFAULT_MAX_PENDING_AGE_DAYS;
  Result.AnonymizeDeviceId := True;
end;

{ TExeWatchHelper }

class function TExeWatchHelper.GetHostname: string;
{$IFDEF MSWINDOWS}
var
  Buffer: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
begin
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  if Winapi.Windows.GetComputerName(Buffer, Size) then
    Result := Buffer
  else
    Result := 'unknown';
end;
{$ELSE}
{$IFDEF ANDROID}
begin
  // On Android, use the device model as hostname (e.g. "Pixel 7", "Galaxy S24")
  try
    Result := JStringToString(TJBuild.JavaClass.MODEL);
    if Result = '' then
      Result := 'unknown';
  except
    Result := 'unknown';
  end;
end;
{$ELSE}
{$IFDEF LINUX}
var
  Buffer: array[0..255] of AnsiChar;
begin
  Result := 'unknown';
  try
    FillChar(Buffer, SizeOf(Buffer), 0);
    if Posix.Unistd.gethostname(@Buffer[0], 255) = 0 then
      Result := UTF8ToString(Buffer);
  except
    // Ignore errors, keep 'unknown'
  end;
end;
{$ELSE}
begin
  Result := 'unknown';
end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

class function TExeWatchHelper.GetUsername: string;
{$IFDEF MSWINDOWS}
var
  Buffer: array[0..256] of Char;
  Size: DWORD;
begin
  Size := 257;
  if Winapi.Windows.GetUserName(Buffer, Size) then
    Result := Buffer
  else
    Result := 'unknown';
end;
{$ELSE}
{$IFDEF ANDROID}
begin
  // On Android, use the manufacturer as "username" (e.g. "samsung", "Google")
  try
    Result := JStringToString(TJBuild.JavaClass.MANUFACTURER);
    if Result = '' then
      Result := 'android';
  except
    Result := 'android';
  end;
end;
{$ELSE}
{$IFDEF LINUX}
begin
  // Use USER environment variable (simple and reliable)
  Result := GetEnvironmentVariable('USER');
  if Result = '' then
    Result := 'unknown';
end;
{$ELSE}
begin
  Result := 'unknown';
end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

class function TExeWatchHelper.GetOSVersion: string;
begin
  // TOSVersion.ToString is cross-platform in modern Delphi
  Result := TOSVersion.ToString;
end;

class function TExeWatchHelper.GetDeviceId: string;
begin
  Result := GetUsername + '@' + GetHostname;
end;

// ---------------------------------------------------------------------------
// SHA-256 and HMAC-SHA256. The sums wrap around on purpose: overflow and range checking are
// switched off for these two functions and put back after them.
// ---------------------------------------------------------------------------
{$IFOPT Q+}{$DEFINE EW_SHA_RESTORE_Q}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE EW_SHA_RESTORE_R}{$R-}{$ENDIF}
function EWSha256(const AData: TBytes): TBytes;
const
  K: array[0..63] of Cardinal = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);
var
  H: array[0..7] of Cardinal;
  W: array[0..63] of Cardinal;
  Msg: TBytes;
  BitLen: UInt64;
  DataLen, PadLen, Block, I, P: Integer;
  A, B, C, D, E, F, G, HH, T1, T2, S0, S1: Cardinal;

  function RotR(AValue: Cardinal; ABits: Integer): Cardinal;
  begin
    Result := (AValue shr ABits) or (AValue shl (32 - ABits));
  end;

begin
  // The message, one bit set, zeros up to 8 bytes short of a block, then its length in bits.
  DataLen := Length(AData);
  BitLen := UInt64(DataLen) * 8;
  PadLen := 64 - ((DataLen + 9) mod 64);
  if PadLen = 64 then
    PadLen := 0;
  Msg := nil;
  SetLength(Msg, DataLen + 1 + PadLen + 8);
  if DataLen > 0 then
    Move(AData[0], Msg[0], DataLen);
  Msg[DataLen] := $80;
  for I := 0 to 7 do
    Msg[Length(Msg) - 1 - I] := Byte(BitLen shr (8 * I));

  H[0] := $6A09E667; H[1] := $BB67AE85; H[2] := $3C6EF372; H[3] := $A54FF53A;
  H[4] := $510E527F; H[5] := $9B05688C; H[6] := $1F83D9AB; H[7] := $5BE0CD19;

  for Block := 0 to (Length(Msg) div 64) - 1 do
  begin
    P := Block * 64;
    for I := 0 to 15 do
      W[I] := (Cardinal(Msg[P + I * 4]) shl 24) or (Cardinal(Msg[P + I * 4 + 1]) shl 16) or
              (Cardinal(Msg[P + I * 4 + 2]) shl 8) or Cardinal(Msg[P + I * 4 + 3]);
    for I := 16 to 63 do
    begin
      S0 := RotR(W[I - 15], 7) xor RotR(W[I - 15], 18) xor (W[I - 15] shr 3);
      S1 := RotR(W[I - 2], 17) xor RotR(W[I - 2], 19) xor (W[I - 2] shr 10);
      W[I] := W[I - 16] + S0 + W[I - 7] + S1;
    end;
    A := H[0]; B := H[1]; C := H[2]; D := H[3];
    E := H[4]; F := H[5]; G := H[6]; HH := H[7];
    for I := 0 to 63 do
    begin
      S1 := RotR(E, 6) xor RotR(E, 11) xor RotR(E, 25);
      T1 := HH + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I];
      S0 := RotR(A, 2) xor RotR(A, 13) xor RotR(A, 22);
      T2 := S0 + ((A and B) xor (A and C) xor (B and C));
      HH := G; G := F; F := E; E := D + T1;
      D := C; C := B; B := A; A := T1 + T2;
    end;
    H[0] := H[0] + A; H[1] := H[1] + B; H[2] := H[2] + C; H[3] := H[3] + D;
    H[4] := H[4] + E; H[5] := H[5] + F; H[6] := H[6] + G; H[7] := H[7] + HH;
  end;

  SetLength(Result, 32);
  for I := 0 to 7 do
  begin
    Result[I * 4] := Byte(H[I] shr 24);
    Result[I * 4 + 1] := Byte(H[I] shr 16);
    Result[I * 4 + 2] := Byte(H[I] shr 8);
    Result[I * 4 + 3] := Byte(H[I]);
  end;
end;

function EWHmacSha256(const AKey, AData: TBytes): TBytes;
var
  Key, Inner, Outer, Digest: TBytes;
  I: Integer;
begin
  // A key longer than a block is replaced by its hash; then it is padded with zeros to a block.
  if Length(AKey) > 64 then
    Key := EWSha256(AKey)
  else
    Key := Copy(AKey, 0, Length(AKey));
  SetLength(Key, 64);
  SetLength(Inner, 64 + Length(AData));
  for I := 0 to 63 do
    Inner[I] := Key[I] xor $36;
  if Length(AData) > 0 then
    Move(AData[0], Inner[64], Length(AData));
  Digest := EWSha256(Inner);
  SetLength(Outer, 64 + 32);
  for I := 0 to 63 do
    Outer[I] := Key[I] xor $5C;
  Move(Digest[0], Outer[64], 32);
  Result := EWSha256(Outer);
end;
{$IFDEF EW_SHA_RESTORE_R}{$R+}{$UNDEF EW_SHA_RESTORE_R}{$ENDIF}
{$IFDEF EW_SHA_RESTORE_Q}{$Q+}{$UNDEF EW_SHA_RESTORE_Q}{$ENDIF}

var
  // The key of a process that has neither a machine id nor a file it can write: it lasts as
  // long as the process. Set once, when the unit starts.
  GEWVolatileDeviceKey: string;

// What is left when the system gives no random value: the clock, a counter of fine grain, the
// process and where its memory is. Who knows them can work it out, and it is still not a name.
function EWLastResortKey: string;
var
  Digest: TBytes;
  I: Integer;
begin
  Digest := EWSha256(TEncoding.UTF8.GetBytes(Format('%.10f/%d/%d/%d/%p',
    [Double(Now), Int64(TThread.GetTickCount), TStopwatch.GetTimeStamp,
     Int64(TExeWatchHelper.GetCurrentProcessId), Pointer(@Digest)])));
  Result := '';
  for I := 0 to High(Digest) do
    Result := Result + IntToHex(Digest[I], 2);
end;

// 64 hex digits that nobody can guess. A function of its own, and not an expression of the
// initialization section: there the Win64 compiler that writes COFF objects (the modern
// C++ toolchain) stops with an internal error. It never raises: the unit starts with it.
function EWNewVolatileDeviceKey: string;
{$IFDEF POSIX}
var
  Handle: THandle;
  Bytes: TBytes;
  I: Integer;
{$ENDIF}
begin
  Result := '';
  try
    {$IFDEF POSIX}
    // The random source of the kernel. A GUID is not one here: on Linux the runtime makes it of
    // the clock and of the network card, with a library that an image may not have.
    SetLength(Bytes, 32);
    Handle := FileOpen('/dev/urandom', fmOpenRead or fmShareDenyNone);
    if Handle <> INVALID_HANDLE_VALUE then
      try
        if FileRead(Handle, Bytes[0], Length(Bytes)) = Length(Bytes) then
          for I := 0 to High(Bytes) do
            Result := Result + IntToHex(Bytes[I], 2);
      finally
        FileClose(Handle);
      end;
    {$ELSE}
    // On Windows the two GUIDs are random: 122 bits each.
    Result := StringReplace(StringReplace(StringReplace(
      TGUID.NewGuid.ToString + TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]),
      '-', '', [rfReplaceAll]);
    {$ENDIF}
  except
    Result := '';
  end;
  if Result = '' then
    Result := EWLastResortKey;
  Result := LowerCase(Result);
end;

// Where the operating system keeps no machine id (a container, macOS, a phone) the key is a
// random value written once in a folder of the user: ~/.exewatch/device.key, the same file the
// .NET and Python SDKs use. A file that cannot be written leaves the key of the process: the
// codes then change at every start, and that is the price of not sending a name.
// The key in the file, empty when the file is not there or holds no key. A key is 32 to 1024
// printable ASCII characters, with the spaces, tabs and line ends around them left out: the
// same rule, on the same bytes, as the .NET and Python SDKs. A file of zeros, which a crash can
// leave, is not a key. Opened without denying anything to the others: on Windows a file that
// somebody is giving its name to, in that instant, would not open, and would be taken for a
// file with no key.
function EWReadDeviceKey(const AFileName: string): string;
var
  Handle: THandle;
  Buffer: TBytes;
  Count, First, Last, I: Integer;
begin
  Result := '';
  try
    {$IFDEF MSWINDOWS}
    Handle := CreateFile(PChar(AFileName), GENERIC_READ,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    {$ELSE}
    Handle := FileOpen(AFileName, fmOpenRead or fmShareDenyNone);
    {$ENDIF}
    if Handle <> INVALID_HANDLE_VALUE then
      try
        // What follows the first 4096 bytes is not read: a key is far shorter.
        SetLength(Buffer, 4096);
        Count := FileRead(Handle, Buffer[0], Length(Buffer));
        First := 0;
        Last := Count - 1;
        while (First <= Last) and (Buffer[First] in [9, 10, 13, 32]) do
          Inc(First);
        while (Last >= First) and (Buffer[Last] in [9, 10, 13, 32]) do
          Dec(Last);
        Count := Last - First + 1;
        if (Count >= 32) and (Count <= 1024) then
        begin
          for I := First to Last do
            if (Buffer[I] < 33) or (Buffer[I] > 126) then
              Exit;
          Result := TEncoding.ASCII.GetString(Buffer, First, Count);
        end;
      finally
        FileClose(Handle);
      end;
  except
    Result := '';
  end;
end;

function EWDeviceKeyFromFile(const AFolder: string = ''; const ANewKey: string = ''): string;
var
  Folder, FileName, Draft, NewKey: string;
  Handle: THandle;
  Bytes: TBytes;
  Whole, Named: Boolean;
begin
  Result := '';
  NewKey := ANewKey;
  if NewKey = '' then
    NewKey := GEWVolatileDeviceKey;
  try
    Folder := AFolder;
    if Folder = '' then
    begin
      {$IFDEF MSWINDOWS}
      Folder := TPath.GetDirectoryName(TPath.GetDirectoryName(TExeWatchHelper.GetDefaultStoragePath('k')));
      {$ELSE}
      Folder := TPath.GetHomePath;
      if Folder <> '' then
        Folder := TPath.Combine(Folder, '.exewatch');
      {$ENDIF}
    end;
    if Folder = '' then
      Exit(NewKey);
    FileName := TPath.Combine(Folder, 'device.key');
    Result := EWReadDeviceKey(FileName);
    if Result = '' then
    begin
      ForceDirectories(Folder);
      // Written whole under another name, then given its name in one step: processes that
      // start together never read half a key. $180 is rw for the owner alone. No share mode:
      // it is a lock, and where the folder refuses locks the file would be made and then left.
      Draft := FileName + '.' + Copy(EWNewVolatileDeviceKey, 1, 16);
      Handle := FileCreate(Draft, fmExclusive, $180);
      if Handle <> INVALID_HANDLE_VALUE then
      begin
        try
          Bytes := TEncoding.ASCII.GetBytes(NewKey);
          Whole := FileWrite(Handle, Bytes[0], Length(Bytes)) = Length(Bytes);
          // On the disk before it has its name: a power cut leaves no empty key file.
          {$IFDEF MSWINDOWS}
          FlushFileBuffers(Handle);
          {$ENDIF}
          {$IFDEF LINUX}
          fsync(Integer(Handle));
          {$ENDIF}
        finally
          FileClose(Handle);
        end;
        // A draft that is not whole (a full disk) is not given the name.
        if Whole then
        begin
          // The step that gives the name is refused when the file is there: the first one wins.
          {$IFDEF MSWINDOWS}
          Named := RenameFile(Draft, FileName);
          {$ELSE}
          {$IFDEF LINUX}
          Named := link(PAnsiChar(UTF8String(Draft)), PAnsiChar(UTF8String(FileName))) = 0;
          {$ELSE}
          Named := False;
          {$ENDIF}
          {$ENDIF}
          // Not given, and no good key there: a file left empty or cut short by a crash, or a
          // platform where that step does not exist. The draft takes its place.
          if (not Named) and (EWReadDeviceKey(FileName) = '') then
          begin
            {$IFDEF MSWINDOWS}
            System.SysUtils.DeleteFile(FileName);
            {$ENDIF}
            RenameFile(Draft, FileName);
          end;
        end;
        System.SysUtils.DeleteFile(Draft);
      end;
      Result := EWReadDeviceKey(FileName);
    end;
  except
    Result := '';
  end;
  if Result = '' then
    Result := NewKey;
end;

function EWIsLinuxMachineId(const AValue: string): Boolean;
var
  I: Integer;
begin
  // An image that never had its first boot holds the word "uninitialized" there: the same
  // key on every machine made from it, known to everybody.
  Result := Length(AValue) = 32;
  if Result then
    for I := 1 to Length(AValue) do
      if not CharInSet(AValue[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

class function TExeWatchHelper.GetMachineId: string;
{$IFDEF MSWINDOWS}
const
  // The 64-bit view of the registry: the 32-bit one, where a 32-bit process on 64-bit Windows
  // is sent, has no MachineGuid.
  EW_KEY_WOW64_64KEY = $0100;
var
  Key: HKEY;
  Buffer: array[0..127] of Char;
  Size, ValueType: DWORD;
begin
  Result := '';
  if RegOpenKeyEx(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Cryptography', 0,
       KEY_QUERY_VALUE or EW_KEY_WOW64_64KEY, Key) <> ERROR_SUCCESS then
    Exit;
  try
    FillChar(Buffer, SizeOf(Buffer), 0);
    Size := SizeOf(Buffer) - SizeOf(Char);
    ValueType := 0;
    if (RegQueryValueEx(Key, 'MachineGuid', nil, @ValueType, @Buffer[0], @Size) = ERROR_SUCCESS) and
       (ValueType = REG_SZ) then
      Result := Trim(string(PChar(@Buffer[0])));
  finally
    RegCloseKey(Key);
  end;
end;
{$ELSE}
{$IFDEF LINUX}
begin
  if not EWReadSysText('/etc/machine-id', 256, Result) then
    Result := '';
  Result := Trim(Result);
  if not EWIsLinuxMachineId(Result) then
  begin
    if not EWReadSysText('/var/lib/dbus/machine-id', 256, Result) then
      Result := '';
    Result := Trim(Result);
    if not EWIsLinuxMachineId(Result) then
      Result := '';
  end;
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}
{$ENDIF}

class function TExeWatchHelper.GetDeviceKey: TBytes;
var
  Id: string;
begin
  Id := GetMachineId;
  if Id = '' then
    Id := EWDeviceKeyFromFile;
  Result := TEncoding.UTF8.GetBytes(Id);
end;

class function TExeWatchHelper.KeyedCode(const AKey: TBytes; const AName: string): string;
var
  Msg, Mac: TBytes;
  I: Integer;
begin
  if AName = '' then
    Exit('anonymous');
  Msg := TEncoding.UTF8.GetBytes(AName);
  // Lower case for the ASCII letters only, and on the bytes: every language gives the same
  // result, whatever its idea of case is. A byte of a multi-byte sequence is never in A..Z.
  for I := 0 to High(Msg) do
    if (Msg[I] >= $41) and (Msg[I] <= $5A) then
      Msg[I] := Msg[I] + $20;
  Mac := EWHmacSha256(AKey, Msg);
  Result := LowerCase(IntToHex(Mac[0], 2) + IntToHex(Mac[1], 2) + IntToHex(Mac[2], 2) + IntToHex(Mac[3], 2));
end;

class function TExeWatchHelper.AnonymizeUsername(const AUsername: string): string;
begin
  Result := KeyedCode(GetDeviceKey, AUsername);
end;

class function TExeWatchHelper.AnonymizeHostname(const AHostname: string): string;
var
  DotPos: Integer;
begin
  DotPos := Pos('.', AHostname);
  if DotPos > 1 then
    Result := AnonymizeUsername(Copy(AHostname, 1, DotPos - 1))
  else
    Result := AnonymizeUsername(AHostname);
end;

class function TExeWatchHelper.GetUserPathRoots: TArray<TEWPathRoot>;
var
  List: TList<TEWPathRoot>;
  {$IFNDEF MSWINDOWS}
  Login: string;
  Root: TEWPathRoot;
  {$ENDIF}

  procedure Add(const AToken, AEnvName: string);
  var
    Root: TEWPathRoot;
  begin
    Root.Value := GetEnvironmentVariable(AEnvName);
    if Root.Value = '' then
      Exit;
    Root.Token := AToken;
    List.Add(Root);
  end;

begin
  List := TList<TEWPathRoot>.Create;
  try
    {$IFDEF MSWINDOWS}
    Add('[USERPROFILE]', 'USERPROFILE');
    Add('[APPDATA]', 'APPDATA');
    Add('[LOCALAPPDATA]', 'LOCALAPPDATA');
    Add('[TEMP]', 'TEMP');
    Add('[TEMP]', 'TMP');
    {$ELSE}
    Add('[HOME]', 'HOME');
    // A removable disk is mounted under the login's own folder: /media/<login>, /run/media/<login>.
    Login := GetUsername;
    if (Login <> '') and (Login <> 'unknown') then
    begin
      Root.Token := '[MEDIA]';
      Root.Value := '/media/' + Login;
      List.Add(Root);
      Root.Value := '/run/media/' + Login;
      List.Add(Root);
    end;
    {$ENDIF}
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// A character that can be part of a file or folder name. '/' and '\' are not: they end a name.
function EWIsNameChar(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_') or (C = '.') or (C = '-') or (C = '~');
end;

// Both separators are the same one for the comparison, and a root does not end with one.
function EWNormalizeRoot(const AValue: string; ACaseSensitive: Boolean): string;
begin
  Result := StringReplace(AValue, '/', '\', [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = '\') do
    SetLength(Result, Length(Result) - 1);
  // AnsiLowerCase, not LowerCase: the latter folds only ASCII, and a profile folder is often 'Müller'.
  if not ACaseSensitive then
    Result := AnsiLowerCase(Result);
end;

class function TExeWatchHelper.ScrubUserPaths(const AText: string; const ARoots: TArray<TEWPathRoot>;
  ACaseSensitive: Boolean): string;
const
  // A shorter value is a drive ("C:\"), the filesystem root or noise: replacing it would damage
  // the text instead of hiding a person.
  MIN_ROOT_LENGTH = 4;
var
  Values, Tokens: TArray<string>;
  Norm: string;
  Builder: TStringBuilder;
  I, J, K, Count, Len: Integer;
  Matched: Boolean;
  TmpValue, TmpToken: string;
begin
  Result := AText;
  if (AText = '') or (Length(ARoots) = 0) then
    Exit;

  // Keep the usable roots, without repeated values.
  SetLength(Values, Length(ARoots));
  SetLength(Tokens, Length(ARoots));
  Count := 0;
  for I := 0 to High(ARoots) do
  begin
    TmpValue := EWNormalizeRoot(ARoots[I].Value, ACaseSensitive);
    if (Length(TmpValue) < MIN_ROOT_LENGTH) or (ARoots[I].Token = '') then
      Continue;
    Matched := False;
    for J := 0 to Count - 1 do
      if Values[J] = TmpValue then
      begin
        Matched := True;
        Break;
      end;
    if Matched then
      Continue;
    Values[Count] := TmpValue;
    Tokens[Count] := ARoots[I].Token;
    Inc(Count);
  end;
  if Count = 0 then
    Exit;

  // Longest first, so that '...\AppData\Local' wins over '...\bob'.
  for I := 1 to Count - 1 do
    for J := I downto 1 do
    begin
      if Length(Values[J]) <= Length(Values[J - 1]) then
        Break;
      TmpValue := Values[J]; Values[J] := Values[J - 1]; Values[J - 1] := TmpValue;
      TmpToken := Tokens[J]; Tokens[J] := Tokens[J - 1]; Tokens[J - 1] := TmpToken;
    end;

  // The comparison runs on a copy with the same length as the text, so that an index in one is
  // an index in the other.
  Norm := StringReplace(AText, '/', '\', [rfReplaceAll]);
  if not ACaseSensitive then
  begin
    TmpValue := AnsiLowerCase(Norm);
    if Length(TmpValue) = Length(Norm) then
      Norm := TmpValue;
  end;

  Builder := TStringBuilder.Create;
  try
    I := 1;
    Len := Length(AText);
    while I <= Len do
    begin
      Matched := False;
      // A name does not start in the middle of another: 'xC:\Users\bob', '/mnt/home/bob'.
      if (I = 1) or not EWIsNameChar(Norm[I - 1]) then
        for K := 0 to Count - 1 do
        begin
          J := Length(Values[K]);
          if (I + J - 1 <= Len) and (Norm[I] = Values[K][1]) and (Copy(Norm, I, J) = Values[K]) and
             // ... and it does not end in the middle of one: 'bobby', 'bob.old', 'bob~1'.
             ((I + J > Len) or not EWIsNameChar(Norm[I + J])) then
          begin
            Builder.Append(Tokens[K]);
            Inc(I, J);
            Matched := True;
            Break;
          end;
        end;
      if not Matched then
      begin
        Builder.Append(AText[I]);
        Inc(I);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TExeWatchHelper.GetDefaultStoragePath(const AApiKey: string = ''): string;
// Each app gets its own subdirectory based on the API key prefix so that two
// apps running concurrently on the same machine cannot pick up each other's
// queued files from the shared %LOCALAPPDATA% tree.
//
// NOTE: if the API key is rotated while the app is running, files buffered
// under the old key prefix are not migrated and will be cleaned up by the
// max-age purge. Ensure the queue is flushed (WaitForSending) before
// rotating a key in a long-running process.
var
  KeyPrefix: string;
{$IFDEF MSWINDOWS}
  BaseDir: string;
{$ENDIF}
begin
  // 'default' is only reached if the caller explicitly passes an empty key,
  // which the SDK rejects during initialization. It is kept as a safety net
  // so this function never returns a path without a terminal subdirectory.
  if AApiKey <> '' then
    KeyPrefix := Copy(AApiKey, 1, 16)
  else
    KeyPrefix := 'default';

{$IFDEF MSWINDOWS}
  BaseDir := GetEnvironmentVariable('LOCALAPPDATA');
  if BaseDir = '' then
    BaseDir := TPath.GetTempPath;
  Result := TPath.Combine(TPath.Combine(TPath.Combine(BaseDir, 'ExeWatch'), 'pending'), KeyPrefix);
{$ELSE}
{$IFDEF ANDROID}
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    JStringToString(TAndroidHelper.Context.getFilesDir.getAbsolutePath),
    'ExeWatch'), 'pending'), KeyPrefix);
{$ELSE}
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetTempPath, 'ExeWatch'), 'pending'), KeyPrefix);
{$ENDIF}
{$ENDIF}
end;

class function TExeWatchHelper.GetTimezoneOffset: string;
var
  BiasMinutes: Integer;
  Hours, Minutes: Integer;
  Sign: Char;
{$IFDEF MSWINDOWS}
  TZInfo: TTimeZoneInformation;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  // Get current timezone bias (in minutes, negative for East of UTC)
  case GetTimeZoneInformation(TZInfo) of
    TIME_ZONE_ID_STANDARD:
      BiasMinutes := TZInfo.Bias + TZInfo.StandardBias;
    TIME_ZONE_ID_DAYLIGHT:
      BiasMinutes := TZInfo.Bias + TZInfo.DaylightBias;
  else
    BiasMinutes := TZInfo.Bias;
  end;
  // Bias is negative of offset (Bias = -Offset), so invert
  BiasMinutes := -BiasMinutes;
{$ELSE}
  // Cross-platform: use TTimeZone from System.DateUtils
  BiasMinutes := Round(TTimeZone.Local.UtcOffset.TotalMinutes);
{$ENDIF}

  if BiasMinutes >= 0 then
    Sign := '+'
  else
  begin
    Sign := '-';
    BiasMinutes := Abs(BiasMinutes);
  end;

  Hours := BiasMinutes div 60;
  Minutes := BiasMinutes mod 60;

  Result := Format('%s%.2d:%.2d', [Sign, Hours, Minutes]);
end;

class function TExeWatchHelper.GetAppVersionInfo: TAppVersionInfo;
{$IFDEF ANDROID}
var
  PackageInfo: JPackageInfo;
  VersionStr: JString;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  Result := Default(TAppVersionInfo);
  try
    PackageInfo := TAndroidHelper.Context.getPackageManager.getPackageInfo(
      TAndroidHelper.Context.getPackageName, 0);
    VersionStr := PackageInfo.versionName;
    if VersionStr <> nil then
    begin
      Result.FileVersion := JStringToString(VersionStr);
      Result.ProductVersion := Result.FileVersion;
    end;
    Result.ProductName := JStringToString(TAndroidHelper.Context.getPackageName);
  except
    // Ignore errors
  end;
  {$ELSE}
  Result := TAppVersionInfo.GetFromFile(ParamStr(0));
  {$ENDIF}
end;

class function TExeWatchHelper.GetCurrentProcessId: Cardinal;
begin
  {$IFDEF MSWINDOWS}
  Result := Winapi.Windows.GetCurrentProcessId;
  {$ELSE}
  {$IF DEFINED(LINUX) OR DEFINED(ANDROID)}
  Result := Cardinal(Posix.Unistd.getpid);
  {$ELSE}
  Result := 0;
  {$IFEND}
  {$ENDIF}
end;

{ TAppVersionInfo }

class function TAppVersionInfo.GetFromFile(const AFileName: string): TAppVersionInfo;
{$IFDEF MSWINDOWS}
var
  FileName: string;
  VerInfoSize, VerValueSize, Dummy: DWORD;
  VerInfo: Pointer;
  VerValue: PVSFixedFileInfo;
  LangCodePage: PLongInt;
  TranslateStr: string;

  function GetVersionString(const AKey: string): string;
  var
    ValuePtr: PChar;
    ValueLen: UINT;
  begin
    Result := '';
    if VerQueryValue(VerInfo, PChar('\StringFileInfo\' + TranslateStr + '\' + AKey),
      Pointer(ValuePtr), ValueLen) then
      Result := ValuePtr;
  end;

begin
  Result := Default(TAppVersionInfo);

  if AFileName = '' then
    FileName := ParamStr(0)
  else
    FileName := AFileName;

  VerInfoSize := GetFileVersionInfoSize(PChar(FileName), Dummy);
  if VerInfoSize = 0 then
    Exit;

  GetMem(VerInfo, VerInfoSize);
  try
    if not GetFileVersionInfo(PChar(FileName), 0, VerInfoSize, VerInfo) then
      Exit;

    // Get fixed file info for version numbers
    if VerQueryValue(VerInfo, '\', Pointer(VerValue), VerValueSize) then
    begin
      Result.FileVersion := Format('%d.%d.%d.%d', [
        HiWord(VerValue.dwFileVersionMS),
        LoWord(VerValue.dwFileVersionMS),
        HiWord(VerValue.dwFileVersionLS),
        LoWord(VerValue.dwFileVersionLS)
      ]);
      Result.ProductVersion := Format('%d.%d.%d.%d', [
        HiWord(VerValue.dwProductVersionMS),
        LoWord(VerValue.dwProductVersionMS),
        HiWord(VerValue.dwProductVersionLS),
        LoWord(VerValue.dwProductVersionLS)
      ]);
    end;

    // Get translation info for string queries
    if VerQueryValue(VerInfo, '\VarFileInfo\Translation', Pointer(LangCodePage), VerValueSize) then
    begin
      TranslateStr := IntToHex(LoWord(LangCodePage^), 4) + IntToHex(HiWord(LangCodePage^), 4);

      Result.ProductName := GetVersionString('ProductName');
      Result.FileDescription := GetVersionString('FileDescription');
      Result.CompanyName := GetVersionString('CompanyName');
      Result.InternalName := GetVersionString('InternalName');
      Result.OriginalFilename := GetVersionString('OriginalFilename');
      Result.LegalCopyright := GetVersionString('LegalCopyright');
    end;
  finally
    FreeMem(VerInfo);
  end;
end;
{$ELSE}
begin
  Result := Default(TAppVersionInfo);
end;
{$ENDIF}

function TAppVersionInfo.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if FileVersion <> '' then
    Result.AddPair('file_version', FileVersion);
  if ProductVersion <> '' then
    Result.AddPair('product_version', ProductVersion);
  if ProductName <> '' then
    Result.AddPair('product_name', ProductName);
  if FileDescription <> '' then
    Result.AddPair('file_description', FileDescription);
  if CompanyName <> '' then
    Result.AddPair('company_name', CompanyName);
  if InternalName <> '' then
    Result.AddPair('internal_name', InternalName);
  if OriginalFilename <> '' then
    Result.AddPair('original_filename', OriginalFilename);
  if LegalCopyright <> '' then
    Result.AddPair('legal_copyright', LegalCopyright);
end;

{ TExeWatch }

constructor TExeWatch.Create(const AConfig: TExeWatchConfig);
var
  SendingFiles: TStringDynArray;
  SendingFile: string;
  OriginalName: string;
  StartupData: TJSONObject;
  StartupMsg: string;
  Pair: TPair<string, string>;
  HasOwnDeviceId: Boolean;
begin
  inherited Create;
  FConfig := AConfig;

  // Validate API key is for native platforms (not browser)
  if FConfig.ApiKey.StartsWith('ew_web_') then
    raise Exception.Create('ExeWatch: Invalid API key - "ew_web_..." is a Browser key. Use a native platform key (ew_win_, ew_lin_, ew_mac_, ew_and_, ew_ios_) for the Delphi SDK.')
  else if not (FConfig.ApiKey.StartsWith('ew_win_') or
               FConfig.ApiKey.StartsWith('ew_lin_') or
               FConfig.ApiKey.StartsWith('ew_mac_') or
               FConfig.ApiKey.StartsWith('ew_and_') or
               FConfig.ApiKey.StartsWith('ew_ios_') or
               FConfig.ApiKey.StartsWith('ew_desk_')) then  // ew_desk_ for backward compatibility
    raise Exception.Create('ExeWatch: Invalid API key format. Expected key starting with ew_win_, ew_lin_, ew_mac_, ew_and_, or ew_ios_');

  // Override DeviceInfo.AppBinaryVersion if user explicitly set Config.AppBinaryVersion
  if FConfig.AppBinaryVersion <> '' then
    FConfig.DeviceInfo.AppBinaryVersion := FConfig.AppBinaryVersion;
  // Copy user-defined AppVersion from Config to DeviceInfo
  if FConfig.AppVersion <> '' then
    FConfig.DeviceInfo.AppVersion := FConfig.AppVersion;
  // Anonymize username (and DeviceId) if requested (GDPR compliance).
  // We overwrite Username here, not just DeviceId, so the real Windows login
  // is never shipped to the backend — avoids leaking via device tooltips,
  // the Devices page, or any other field that displays the username.
  if FConfig.AnonymizeDeviceId then
  begin
    // An application that set its own DeviceId keeps it: only the names are hashed.
    HasOwnDeviceId := (FConfig.DeviceInfo.DeviceId <> '') and
      (FConfig.DeviceInfo.DeviceId <> TExeWatchHelper.GetDeviceId);
    FConfig.DeviceInfo.Username := TExeWatchHelper.AnonymizeUsername(FConfig.DeviceInfo.Username);
    // The hostname can embed the username (e.g. host "DANIELETETIPC" contains
    // login "daniele"). It becomes a code too, and the Hostname field of the payload
    // carries that same code: the real name never leaves the machine, and
    // DeviceId stays stable per machine (code@code).
    FConfig.DeviceInfo.Hostname := TExeWatchHelper.AnonymizeHostname(FConfig.DeviceInfo.Hostname);
    if not HasOwnDeviceId then
      FConfig.DeviceInfo.DeviceId := FConfig.DeviceInfo.Username + '@' + FConfig.DeviceInfo.Hostname;
    FUserPathRoots := TExeWatchHelper.GetUserPathRoots;
  end;
  FBuffer := TList<TLogEvent>.Create;
  FBufferLock := TCriticalSection.Create;
  FCustomDeviceInfo := TDictionary<string, string>.Create;
  FCustomDeviceInfoLock := TCriticalSection.Create;
  // Breadcrumbs
  FBreadcrumbs := TDictionary<TThreadID, TList<TBreadcrumb>>.Create;
  FBreadcrumbOwners := TDictionary<TThreadID, Int64>.Create;
  FBreadcrumbsLock := TCriticalSection.Create;
  // Timing/Profiling
  // The stopwatch of the runtime has no frequency until its first instance: without this
  // one, on Delphi XE8 a timing that ends before the first send divides by zero.
  TStopwatch.StartNew;
  FPendingTimings := TDictionary<TThreadID, TDictionary<string, TTimingEntry>>.Create;
  FTimingStacks := TDictionary<TThreadID, TList<string>>.Create;
  FPendingTimingsOwners := TDictionary<TThreadID, Int64>.Create;
  FPendingTimingsLock := TCriticalSection.Create;
  // User identity - initialized as empty
  FCurrentUser := Default(TUserIdentity);
  FCurrentUserLock := TCriticalSection.Create;
  // Global tags
  FGlobalTags := TDictionary<string, string>.Create;
  FGlobalTagsLock := TCriticalSection.Create;

  // Apply initial tags before the startup log is emitted
  for Pair in AConfig.GlobalTags do
    FGlobalTags.AddOrSetValue(Pair.Key, Pair.Value);

  FShutdown := False;
  FShutdownEvent := TEvent.Create(nil, True, False, '');
  FPersistEvent := TEvent.Create(nil, False, False, '');
  FEnabled := True;
  {$IFDEF MSWINDOWS}
  FFileCounter := EWGetTickCount64;
  {$ELSE}
  FFileCounter := TThread.GetTickCount;
  {$ENDIF}
  FDeviceInfoSent := False;

  // Generate unique session ID (16 hex chars from GUID for better uniqueness)
  FSessionId := Copy(TGUID.NewGuid.ToString.Replace('-', '').Replace('{', '').Replace('}', ''), 1, 16);

  // Cache process ID at startup (never changes during execution)
  FProcessId := TExeWatchHelper.GetCurrentProcessId;

  // Initialize server-driven configuration with defaults
  FServerConfigVersion := 0;  // 0 = not yet received from server
  FServerFlushIntervalMs := FConfig.FlushIntervalMs;
  FServerBatchSize := FConfig.BufferSize;
  FServerSamplingRate := FConfig.SampleRate;
  FServerMaxMessageLength := 50000;  // Default server limit
  FServerMinLevel := llDebug;
  FServerEnabled := True;
  FServerConfigLock := TCriticalSection.Create;

  // Internal diagnostic logging
  FInternalLogLock := TCriticalSection.Create;
  FLastSendFailed := False;

  // API Trace
  FAPITraceLock := TCriticalSection.Create;
  FAPITraceWriteCount := 0;

  // Metrics (Counters & Gauges)
  FMetricAccumulators := TDictionary<string, TMetricAccumulator>.Create;
  FMetricAccumulatorsLock := TCriticalSection.Create;
  FRegisteredGauges := TList<TGaugeRegistration>.Create;
  FRegisteredGaugesLock := TCriticalSection.Create;
  FSamplerThread := nil;
  FLastMetricFlushTime := Now;

  // Ensure storage directory exists
  EnsureStoragePath;

  // Cleanup old internal logs and log SDK startup
  CleanupOldInternalLogs;

  // Initialize API trace
  InitializeAPITrace;
  WriteInternalLog('SDK STARTUP | Version=' + EXEWATCH_SDK_VERSION +
    ' | SessionId=' + FSessionId +
    ' | ProcessId=' + IntToStr(FProcessId) +
    ' | CustomerId=' + IfThen(FConfig.CustomerId <> '', FConfig.CustomerId, '(empty)') +
    ' | Endpoint=' + EffectiveEndpoint);

  // Clean up any .sending files from previous crashed sessions
  // (rename them back to .ewlog so they get retried)
  SendingFiles := TDirectory.GetFiles(FConfig.StoragePath, '*' + EXEWATCH_SENDING_EXTENSION);
  for SendingFile in SendingFiles do
  begin
    OriginalName := ChangeFileExt(SendingFile, EXEWATCH_LOG_FILE_EXTENSION);
    if not TFile.Exists(OriginalName) then
      TFile.Move(SendingFile, OriginalName)
    else
      TFile.Delete(SendingFile);
  end;

  // Start background shipper thread
  FShipperThread := TThread.CreateAnonymousThread(ShipperThreadExecute);
  FShipperThread.FreeOnTerminate := False;
  FShipperThread.Start;

  // Background persist thread: writes the buffer to disk when an error or the
  // startup event asks for it, so the caller never waits for the disk and a slow
  // upload on the shipper thread cannot delay the write.
  FPersistThread := TThread.CreateAnonymousThread(PersistThreadExecute);
  FPersistThread.FreeOnTerminate := False;
  FPersistThread.Start;

  // Queue device info to be sent (with retry on failure)
  QueueDeviceInfo;

  // Log application startup with structured data for analytics
  StartupData := TJSONObject.Create;
  StartupData.AddPair('event_type', 'app_startup');
  StartupData.AddPair('session_id', FSessionId);
  StartupData.AddPair('sdk_version', EXEWATCH_SDK_VERSION);
  StartupData.AddPair('app_binary_version', FConfig.DeviceInfo.AppBinaryVersion);
  if FConfig.DeviceInfo.AppVersion <> '' then
    StartupData.AddPair('app_version', FConfig.DeviceInfo.AppVersion);
  if FConfig.CustomerId <> '' then
  begin
    StartupData.AddPair('customer_id', FConfig.CustomerId);
    StartupMsg := 'Application started [' + FConfig.CustomerId + ']';
  end
  else
    StartupMsg := 'Application started';
  Log(llInfo, StartupMsg, 'exewatch', StartupData);
  // The first record of a run must survive a crash in its first seconds.
  if FConfig.CustomerId <> '' then
    FPersistEvent.SetEvent;
end;

destructor TExeWatch.Destroy;
var
  I: Integer;
  TimingPair: TPair<string, TTimingEntry>;
  ThreadTimingsPair: TPair<TThreadID, TDictionary<string, TTimingEntry>>;
  ThreadStackPair: TPair<TThreadID, TList<string>>;
  Pair: TPair<TThreadID, TList<TBreadcrumb>>;
begin
  // A constructor that raised (a malformed API key is refused before anything
  // is allocated) still runs this destructor, with every field nil: there is
  // nothing to shut down or free, and touching it would replace the real
  // exception with an access violation.
  if FBuffer = nil then
  begin
    inherited Destroy;
    Exit;
  end;
  Shutdown;

  // Free TJSONObject instances inside buffer records
  FBufferLock.Enter;
  try
    for I := 0 to FBuffer.Count - 1 do
      if FBuffer[I].ExtraData <> nil then
        FBuffer[I].ExtraData.Free;
    FBuffer.Clear;
  finally
    FBufferLock.Leave;
  end;
  FBuffer.Free;
  FBufferLock.Free;

  FCustomDeviceInfo.Free;
  FCustomDeviceInfoLock.Free;

  // Free TJSONObject instances inside breadcrumb records (all threads) and free lists
  FBreadcrumbsLock.Enter;
  try
    for Pair in FBreadcrumbs do
    begin
      for I := 0 to Pair.Value.Count - 1 do
        if Pair.Value[I].Data <> nil then
          Pair.Value[I].Data.Free;
      Pair.Value.Free; // Free the TList instance
    end;
    FBreadcrumbs.Clear;
  finally
    FBreadcrumbsLock.Leave;
  end;
  FBreadcrumbs.Free;
  FBreadcrumbOwners.Free;
  FBreadcrumbsLock.Free;

  // Free per-thread timing dicts (and TJSONObject metadata inside entries)
  FPendingTimingsLock.Enter;
  try
    for ThreadTimingsPair in FPendingTimings do
    begin
      for TimingPair in ThreadTimingsPair.Value do
        if TimingPair.Value.Metadata <> nil then
          TimingPair.Value.Metadata.Free;
      ThreadTimingsPair.Value.Free;
    end;
    FPendingTimings.Clear;
    for ThreadStackPair in FTimingStacks do
      ThreadStackPair.Value.Free;
    FTimingStacks.Clear;
  finally
    FPendingTimingsLock.Leave;
  end;
  FPendingTimings.Free;
  FTimingStacks.Free;
  FPendingTimingsOwners.Free;
  FPendingTimingsLock.Free;

  // Free metrics resources
  if FSamplerThread <> nil then
  begin
    FSamplerThread.WaitFor;
    FSamplerThread.Free;
  end;
  FMetricAccumulators.Free;
  FMetricAccumulatorsLock.Free;
  FRegisteredGauges.Free;
  FRegisteredGaugesLock.Free;

  FCurrentUserLock.Free;
  FGlobalTags.Free;
  FGlobalTagsLock.Free;
  FServerConfigLock.Free;
  FInternalLogLock.Free;
  FAPITraceLock.Free;
  FShutdownEvent.Free;
  FPersistEvent.Free;
  inherited;
end;

procedure TExeWatch.EnsureStoragePath;
begin
  if not TDirectory.Exists(FConfig.StoragePath) then
    TDirectory.CreateDirectory(FConfig.StoragePath);
end;

procedure TExeWatch.PurgeExpiredFiles;
var
  AllFiles: TStringDynArray;
  FilePath: string;
  FileAge: TDateTime;
  DaysOld: Double;
  PurgedCount: Integer;
begin
  if FConfig.MaxPendingAgeDays <= 0 then
    Exit;

  try
    EnsureStoragePath;
    AllFiles := TDirectory.GetFiles(FConfig.StoragePath, '*.*');
    PurgedCount := 0;

    for FilePath in AllFiles do
    begin
      // Only purge pending data files, not internal logs or traces
      if not (FilePath.EndsWith(EXEWATCH_LOG_FILE_EXTENSION) or
              FilePath.EndsWith(EXEWATCH_DEVICE_FILE_EXTENSION) or
              FilePath.EndsWith(EXEWATCH_METRIC_FILE_EXTENSION) or
              FilePath.EndsWith(EXEWATCH_TEMP_EXTENSION)) then
        Continue;

      FileAge := TFile.GetCreationTime(FilePath);
      DaysOld := Now - FileAge;

      if DaysOld > FConfig.MaxPendingAgeDays then
      begin
        try
          TFile.Delete(FilePath);
          Inc(PurgedCount);
        except
          // Ignore delete errors
        end;
      end;
    end;

    if PurgedCount > 0 then
      WriteInternalLog(Format('PURGE | Deleted %d expired files (older than %d days)',
        [PurgedCount, FConfig.MaxPendingAgeDays]));
  except
    on E: Exception do
      WriteInternalLog('ERROR | PurgeExpiredFiles failed: ' + E.Message);
  end;
end;

procedure TExeWatch.WriteInternalLog(const AMessage: string);
var
  LogPath: string;
  Lines: TStringList;
  LogLine: string;
  I, LinesToRemove: Integer;
begin
  FInternalLogLock.Enter;
  try
    LogPath := TPath.Combine(FConfig.StoragePath, EXEWATCH_INTERNAL_LOG_FILE);
    {$IFDEF DEBUG}{$IFDEF MSWINDOWS}
    OutputDebugString(PChar('WriteInternalLog: ' + LogPath + ' | ' + AMessage));
    {$ENDIF}{$ENDIF}
    Lines := TStringList.Create;
    try
      // Load existing log if present
      if TFile.Exists(LogPath) then
      begin
        try
          Lines.LoadFromFile(LogPath, TEncoding.UTF8);
        except
          // Ignore load errors, start fresh
          Lines.Clear;
        end;
      end;

      // Add new log line with timestamp
      LogLine := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' | ' + AMessage;
      Lines.Add(LogLine);

      // Rotation: keep only last EXEWATCH_INTERNAL_LOG_MAX_LINES lines
      if Lines.Count > EXEWATCH_INTERNAL_LOG_MAX_LINES then
      begin
        LinesToRemove := Lines.Count - EXEWATCH_INTERNAL_LOG_MAX_LINES;
        for I := 1 to LinesToRemove do
          Lines.Delete(0);
      end;

      // Save
      try
        Lines.SaveToFile(LogPath, TEncoding.UTF8);
        {$IFDEF DEBUG}{$IFDEF MSWINDOWS}
        OutputDebugString(PChar('WriteInternalLog: SAVED OK to ' + LogPath));
        {$ENDIF}{$ENDIF}
      except
        on E: Exception do
        begin
          {$IFDEF DEBUG}{$IFDEF MSWINDOWS}
          OutputDebugString(PChar('WriteInternalLog: SAVE FAILED - ' + E.Message));
          {$ENDIF}{$ENDIF}
        end;
      end;
    finally
      Lines.Free;
    end;
  finally
    FInternalLogLock.Leave;
  end;
end;

procedure TExeWatch.CleanupOldInternalLogs;
var
  LogPath: string;
  Lines: TStringList;
  I: Integer;
  LineDate: TDateTime;
  CutoffDate: TDateTime;
  FirstValidLine: Integer;
  FmtSettings: TFormatSettings;
begin
  FInternalLogLock.Enter;
  try
    LogPath := TPath.Combine(FConfig.StoragePath, EXEWATCH_INTERNAL_LOG_FILE);
    if not TFile.Exists(LogPath) then
      Exit;

    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(LogPath, TEncoding.UTF8);
      except
        // I/O error (file locked, permissions, etc.) - skip cleanup
        Exit;
      end;

      if Lines.Count = 0 then
        Exit;

      // Setup format settings for parsing "yyyy-mm-dd hh:nn:ss.zzz"
      FmtSettings := TFormatSettings.Create;
      FmtSettings.DateSeparator := '-';
      FmtSettings.TimeSeparator := ':';
      FmtSettings.ShortDateFormat := 'yyyy-mm-dd';
      FmtSettings.LongTimeFormat := 'hh:nn:ss.zzz';

      CutoffDate := Now - EXEWATCH_INTERNAL_LOG_MAX_AGE_DAYS;
      FirstValidLine := 0;

      // Find first line that is newer than cutoff
      for I := 0 to Lines.Count - 1 do
      begin
        // Extract date from line format: "yyyy-mm-dd hh:nn:ss.zzz | message"
        // Minimum length for date part is 23 chars
        if (Length(Lines[I]) >= 23) and
           TryStrToDateTime(Copy(Lines[I], 1, 10) + ' ' + Copy(Lines[I], 12, 12), LineDate, FmtSettings) then
        begin
          if LineDate >= CutoffDate then
          begin
            FirstValidLine := I;
            Break;
          end;
        end
        else
        begin
          // Can't parse date or malformed line, keep from here
          FirstValidLine := I;
          Break;
        end;
      end;

      // Remove old lines
      if FirstValidLine > 0 then
      begin
        for I := 1 to FirstValidLine do
          Lines.Delete(0);

        try
          Lines.SaveToFile(LogPath, TEncoding.UTF8);
        except
          // Ignore save errors
        end;
      end;
    finally
      Lines.Free;
    end;
  finally
    FInternalLogLock.Leave;
  end;
end;

procedure TExeWatch.InitializeAPITrace;
var
  TraceFile, OldFile: string;
  FileAge: TDateTime;
  HoursSinceCreation: Double;
begin
  FAPITraceLock.Enter;
  try
    TraceFile := TPath.Combine(FConfig.StoragePath, EXEWATCH_API_TRACE_FILE);
    OldFile := TraceFile + '.old';
    FAPITraceFile := TraceFile;

    try
      // Cleanup main trace file if too old (> 12h)
      if TFile.Exists(TraceFile) then
      begin
        FileAge := TFile.GetCreationTime(TraceFile);
        HoursSinceCreation := HoursBetween(Now, FileAge);

        if HoursSinceCreation > EXEWATCH_API_TRACE_MAX_AGE_HOURS then
        begin
          // Rotate old file
          if TFile.Exists(OldFile) then
            TFile.Delete(OldFile);
          TFile.Move(TraceFile, OldFile);
        end;
      end;

      // Cleanup .old file if too old (> 24h)
      if TFile.Exists(OldFile) then
      begin
        FileAge := TFile.GetCreationTime(OldFile);
        HoursSinceCreation := HoursBetween(Now, FileAge);

        if HoursSinceCreation > (EXEWATCH_API_TRACE_MAX_AGE_HOURS * 2) then
          TFile.Delete(OldFile);
      end;
    except
      // Ignore any errors during initialization - trace is non-critical
    end;
  finally
    FAPITraceLock.Leave;
  end;
end;

procedure TExeWatch.WriteAPITrace(const AEntry: string);
var
  Writer: TStreamWriter;
  TraceFile: string;
  Attempt: Integer;
begin
  FAPITraceLock.Enter;
  try
    TraceFile := FAPITraceFile;

    // Try up to 3 times with different file names
    for Attempt := 1 to 3 do
    begin
      try
        Writer := TStreamWriter.Create(TraceFile, True, TEncoding.UTF8);
        try
          Writer.WriteLine(AEntry);
        finally
          Writer.Free;
        end;

        // Success - increment counter and check rotation
        Inc(FAPITraceWriteCount);
        if FAPITraceWriteCount mod EXEWATCH_API_TRACE_CHECK_INTERVAL = 0 then
          CheckAPITraceRotation;

        Exit; // Success, exit method
      except
        // Failed to write - try alternative file
        case Attempt of
          1: TraceFile := FAPITraceFile + '.alt';
          2: TraceFile := FAPITraceFile + '.2';
        end;
      end;
    end;

    // All attempts failed - silently ignore (trace is non-critical)
  finally
    FAPITraceLock.Leave;
  end;
end;

function GetFileSizeCompat(const AFileName: string): Int64;
var
  SearchRec: TSearchRec;
begin
  // TFile.GetSize requires Delphi 11+. FindFirst works from XE8 (and earlier),
  // is cross-platform (Windows/Linux/Android), and reads the size from directory
  // metadata without opening or locking the file. Fully qualified because
  // Winapi.Windows (in scope) declares a clashing FindClose(THandle).
  if System.SysUtils.FindFirst(AFileName, faAnyFile, SearchRec) = 0 then
  begin
    Result := SearchRec.Size;
    System.SysUtils.FindClose(SearchRec);
  end
  else
    Result := -1;
end;

procedure TExeWatch.CheckAPITraceRotation;
var
  FileSize: Int64;
begin
  // Called from within FAPITraceLock - no need to lock again
  try
    if not TFile.Exists(FAPITraceFile) then
      Exit;

    FileSize := GetFileSizeCompat(FAPITraceFile);
    if FileSize > EXEWATCH_API_TRACE_MAX_SIZE then
      RotateAPITraceFile;
  except
    // Ignore any errors - trace is non-critical
  end;
end;

procedure TExeWatch.RotateAPITraceFile;
var
  OldFile: string;
begin
  // Called from within FAPITraceLock - no need to lock again
  try
    OldFile := FAPITraceFile + '.old';

    // Delete existing .old file if present
    if TFile.Exists(OldFile) then
      TFile.Delete(OldFile);

    // Rename current file to .old
    if TFile.Exists(FAPITraceFile) then
      TFile.Move(FAPITraceFile, OldFile);

    // Next write will create a new file
  except
    // Ignore any errors - trace is non-critical
    // If rotation fails, we'll just keep appending to current file
  end;
end;

procedure TExeWatch.ApplyServerConfig(AConfigJson: TJSONObject);
var
  MinLevelStr: string;
begin
  if AConfigJson = nil then
    Exit;

  FServerConfigLock.Enter;
  try
    FServerConfigVersion := AConfigJson.GetValue<Integer>('version', FServerConfigVersion);
    FServerFlushIntervalMs := AConfigJson.GetValue<Integer>('flush_interval_ms', FServerFlushIntervalMs);
    FServerBatchSize := AConfigJson.GetValue<Integer>('batch_size', FServerBatchSize);
    FServerSamplingRate := AConfigJson.GetValue<Double>('sampling_rate', FServerSamplingRate);
    FServerMaxMessageLength := AConfigJson.GetValue<Integer>('max_message_length', FServerMaxMessageLength);
    FServerEnabled := AConfigJson.GetValue<Boolean>('enabled', FServerEnabled);

    // Parse min_level string to enum
    MinLevelStr := LowerCase(AConfigJson.GetValue<string>('min_level', 'debug'));
    if MinLevelStr = 'debug' then
      FServerMinLevel := llDebug
    else if MinLevelStr = 'info' then
      FServerMinLevel := llInfo
    else if MinLevelStr = 'warning' then
      FServerMinLevel := llWarning
    else if MinLevelStr = 'error' then
      FServerMinLevel := llError
    else if MinLevelStr = 'fatal' then
      FServerMinLevel := llFatal
    else
      FServerMinLevel := llDebug;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.GetEffectiveFlushInterval: Integer;
begin
  FServerConfigLock.Enter;
  try
    Result := FServerFlushIntervalMs;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.GetEffectiveSamplingRate: Double;
begin
  FServerConfigLock.Enter;
  try
    Result := FServerSamplingRate;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.GetEffectiveMaxMessageLength: Integer;
begin
  FServerConfigLock.Enter;
  try
    Result := FServerMaxMessageLength;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.GetEffectiveMinLevel: TEWLogLevel;
begin
  FServerConfigLock.Enter;
  try
    Result := FServerMinLevel;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.GetEffectiveEnabled: Boolean;
begin
  FServerConfigLock.Enter;
  try
    Result := FServerEnabled;
  finally
    FServerConfigLock.Leave;
  end;
end;

function TExeWatch.EffectiveEndpoint: string;
begin
  if FConfig.Endpoint <> '' then
    Result := FConfig.Endpoint
  else
    Result := EXEWATCH_ENDPOINT;
end;

function TExeWatch.TruncateMessage(const AMessage: string): string;
var
  MaxLen: Integer;
  TruncSuffix: string;
begin
  MaxLen := GetEffectiveMaxMessageLength;
  if Length(AMessage) <= MaxLen then
    Result := AMessage
  else
  begin
    TruncSuffix := #13#10#13#10'[MESSAGE TRUNCATED]';
    Result := Copy(AMessage, 1, MaxLen - Length(TruncSuffix)) + TruncSuffix;
  end;
end;

function TExeWatch.GetNextFileName: string;
begin
  Inc(FFileCounter);
  Result := TPath.Combine(FConfig.StoragePath,
    Format('%s_%d_%d%s', [
      FormatDateTime('yyyymmdd_hhnnsszzz', Now),
      FFileCounter,
      TThread.CurrentThread.ThreadID,
      EXEWATCH_LOG_FILE_EXTENSION
    ]));
end;

function TExeWatch.GetPendingLogFiles: TArray<string>;
var
  LogFiles, DeviceFiles, MetricFiles: TStringDynArray;
  I, Idx: Integer;
begin
  EnsureStoragePath;
  // Get log files, device info files, and metric files
  LogFiles := TDirectory.GetFiles(FConfig.StoragePath, '*' + EXEWATCH_LOG_FILE_EXTENSION);
  DeviceFiles := TDirectory.GetFiles(FConfig.StoragePath, '*' + EXEWATCH_DEVICE_FILE_EXTENSION);
  MetricFiles := TDirectory.GetFiles(FConfig.StoragePath, '*' + EXEWATCH_METRIC_FILE_EXTENSION);
  // Combine arrays properly (Move doesn't work safely with managed types like string)
  SetLength(Result, Length(LogFiles) + Length(DeviceFiles) + Length(MetricFiles));
  Idx := 0;
  for I := 0 to Length(LogFiles) - 1 do
  begin
    Result[Idx] := LogFiles[I];
    Inc(Idx);
  end;
  for I := 0 to Length(DeviceFiles) - 1 do
  begin
    Result[Idx] := DeviceFiles[I];
    Inc(Idx);
  end;
  for I := 0 to Length(MetricFiles) - 1 do
  begin
    Result[Idx] := MetricFiles[I];
    Inc(Idx);
  end;
  // Sort by name (which includes timestamp) to process oldest first
  TArray.Sort<string>(Result);
end;

procedure TExeWatch.PersistBuffer;
var
  Events: TArray<TLogEvent>;
  FileContent: TJSONObject;
  EventsArray: TJSONArray;
  Event: TLogEvent;
  FileName, TempName: string;
  I: Integer;
begin
  // Don't persist if customer_id is not set - logs would be rejected by server
  if FConfig.CustomerId = '' then
  begin
    WriteInternalLog('WARNING | PersistBuffer skipped - customer_id is empty');
    Exit;
  end;

  FBufferLock.Enter;
  try
    if FBuffer.Count = 0 then
      Exit;
    Events := FBuffer.ToArray;
    FBuffer.Clear;
  finally
    FBufferLock.Leave;
  end;

  // Create JSON file with events and device info
  FileContent := TJSONObject.Create;
  try
    FileContent.AddPair('customer_id', FConfig.CustomerId);
    FileContent.AddPair('device', FConfig.DeviceInfo.ToJSON);

    EventsArray := TJSONArray.Create;
    for Event in Events do
      EventsArray.AddElement(Event.ToJSON);
    FileContent.AddPair('events', EventsArray);

    // Write to a temp name, then rename: a process killed mid-write leaves no
    // truncated .ewlog for the next run to throw away as invalid JSON.
    FileName := GetNextFileName;
    TempName := FileName + EXEWATCH_TEMP_EXTENSION;
    TFile.WriteAllText(TempName, FileContent.ToJSON, TEncoding.UTF8);
    TFile.Move(TempName, FileName);
  finally
    FileContent.Free;
    // Free ExtraData TJSONObjects from the copied events, also when the write failed
    for I := 0 to Length(Events) - 1 do
      if Events[I].ExtraData <> nil then
        Events[I].ExtraData.Free;
  end;
end;

function TExeWatch.RemoveInvalidEventsFromFile(const AFilePath, AResponseJson: string): Boolean;
var
  ResponseObj, FileJSON: TJSONObject;
  DetailArray, LocArray, EventsArray, NewEventsArray: TJSONArray;
  InvalidIndices: TList<Integer>;
  I, EventIndex: Integer;
  DetailItem: TJSONValue;
  FileContent: string;
begin
  Result := False;
  ResponseObj := nil;
  FileJSON := nil;
  InvalidIndices := TList<Integer>.Create;
  try
    // Parse the 422 response to extract invalid event indices
    // Format: {"detail":[{"loc":["body","events",INDEX,"field"],...},...]}
    ResponseObj := TJSONObject.ParseJSONValue(AResponseJson) as TJSONObject;
    if ResponseObj = nil then
      Exit;

    if not ResponseObj.TryGetValue<TJSONArray>('detail', DetailArray) then
      Exit;

    // Extract invalid event indices from "loc" arrays
    for I := 0 to DetailArray.Count - 1 do
    begin
      DetailItem := DetailArray.Items[I];
      if (DetailItem is TJSONObject) and
         (DetailItem as TJSONObject).TryGetValue<TJSONArray>('loc', LocArray) then
      begin
        // loc format: ["body", "events", INDEX, "field"]
        if (LocArray.Count >= 3) and
           (LocArray.Items[1].Value = 'events') and
           (LocArray.Items[2] is TJSONNumber) then
        begin
          EventIndex := (LocArray.Items[2] as TJSONNumber).AsInt;
          if not InvalidIndices.Contains(EventIndex) then
            InvalidIndices.Add(EventIndex);
        end;
      end;
    end;

    if InvalidIndices.Count = 0 then
      Exit;  // No specific events identified, can't filter

    // Read and parse the file
    if not TFile.Exists(AFilePath) then
      Exit;

    FileContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    FileJSON := TJSONObject.ParseJSONValue(FileContent) as TJSONObject;
    if FileJSON = nil then
      Exit;

    if not FileJSON.TryGetValue<TJSONArray>('events', EventsArray) then
      Exit;

    // Build new events array without invalid events
    NewEventsArray := TJSONArray.Create;
    for I := 0 to EventsArray.Count - 1 do
    begin
      if not InvalidIndices.Contains(I) then
        NewEventsArray.AddElement(EventsArray.Items[I].Clone as TJSONObject);
    end;

    // If no valid events remain, return false (caller will delete file)
    if NewEventsArray.Count = 0 then
    begin
      NewEventsArray.Free;
      Exit;
    end;

    // Replace events array in file JSON
    FileJSON.RemovePair('events');
    FileJSON.AddPair('events', NewEventsArray);

    // Write modified file
    TFile.WriteAllText(AFilePath, FileJSON.ToJSON, TEncoding.UTF8);
    Result := True;  // File modified, has valid events to retry
  finally
    InvalidIndices.Free;
    ResponseObj.Free;
    FileJSON.Free;
  end;
end;

function TExeWatch.SendToServer(const AFilePath: string): Boolean;
var
  HttpClient: THTTPClient;
  FileContent: string;
  FileJSON: TJSONObject;
  Payload: TJSONObject;
  RequestContent: TStringStream;
  Response: IHTTPResponse;
  ResponseJson: TJSONObject;
  Accepted, Rejected: Integer;
  EventsArray: TJSONArray;
  DeviceJSON, HardwareJSON, CustomInfoJSON: TJSONObject;
  MetricsArray: TJSONArray;
  SendingPath: string;
  I: Integer;
  IsDeviceInfoFile: Boolean;
  IsCustomInfoFile: Boolean;  // a device file made by SendCustomDeviceInfo: no hardware_info in it
  IsMetricFile: Boolean;
  Endpoint: string;
  OriginalExt: string;
  SourceEvents: TJSONArray;
  EventJSON, APIEvent: TJSONObject;
  LevelStr, TagValue, SessionIdValue: string;
  ExtraData, lJValue: TJSONValue;
  NetworkError: Boolean;
  RequestStartTime: TStopwatch;
  RequestPayload: string;
  RequestSize: Integer;
  TraceEntry, ExceptionTrace: string;
begin
  Result := True;  // Default: continue to next file
  NetworkError := False;
  RequestPayload := '';
  RequestSize := 0;

  // Check if source file exists
  if not TFile.Exists(AFilePath) then
  begin
    WriteInternalLog('WARNING | File not found, skipping: ' + ExtractFileName(AFilePath));
    Exit;
  end;

  // Determine file type from original extension
  OriginalExt := ExtractFileExt(AFilePath);
  IsDeviceInfoFile := SameText(OriginalExt, EXEWATCH_DEVICE_FILE_EXTENSION);
  IsMetricFile := SameText(OriginalExt, EXEWATCH_METRIC_FILE_EXTENSION);

  // Rename file to .sending to mark it as being processed
  SendingPath := ChangeFileExt(AFilePath, EXEWATCH_SENDING_EXTENSION);
  try
    if TFile.Exists(SendingPath) then
      TFile.Delete(SendingPath);
    TFile.Move(AFilePath, SendingPath);
  except
    on E: Exception do
    begin
      WriteInternalLog('WARNING | Cannot process file (locked?): ' + ExtractFileName(AFilePath) + ' - ' + E.Message);
      Exit;  // Skip this file, try next
    end;
  end;

  HttpClient := THTTPClient.Create;
  FileJSON := nil;
  Payload := nil;
  RequestContent := nil;
  try
    try
      // Read and parse the file
      if not TFile.Exists(SendingPath) then
      begin
        WriteInternalLog('WARNING | Sending file disappeared: ' + ExtractFileName(SendingPath));
        Exit;
      end;

      FileContent := TFile.ReadAllText(SendingPath, TEncoding.UTF8);
      FileJSON := TJSONObject.ParseJSONValue(FileContent) as TJSONObject;

      if FileJSON = nil then
      begin
        // Invalid JSON, delete the file and continue
        WriteInternalLog('WARNING | Invalid JSON in file, deleting: ' + ExtractFileName(AFilePath));
        TFile.Delete(SendingPath);
        Exit;
      end;

      // Check if customer_id is empty - if so, delete file (unrecoverable)
      if FileJSON.GetValue<string>('customer_id', '') = '' then
      begin
        WriteInternalLog('WARNING | Empty customer_id in file, deleting (unrecoverable): ' + ExtractFileName(AFilePath));
        TFile.Delete(SendingPath);
        Exit;
      end;

      // SendCustomDeviceInfo writes a device file without hardware_info; the
      // regular device info always has it
      IsCustomInfoFile := IsDeviceInfoFile and (FileJSON.GetValue('hardware_info') = nil);

      // Build payload for API
      Payload := TJSONObject.Create;
      Payload.AddPair('customer_id', FileJSON.GetValue<string>('customer_id'));

      // Copy device info
      if FileJSON.TryGetValue<TJSONObject>('device', DeviceJSON) then
        Payload.AddPair('device', DeviceJSON.Clone as TJSONObject);

      if IsDeviceInfoFile then
      begin
        // Device info file - send to device-info endpoint
        Endpoint := '/api/' + EXEWATCH_API_VERSION + '/ingest/device-info';

        // Copy hardware_info
        if FileJSON.TryGetValue<TJSONObject>('hardware_info', HardwareJSON) then
          Payload.AddPair('hardware_info', HardwareJSON.Clone as TJSONObject);

        // Copy custom_device_info if present
        if FileJSON.TryGetValue<TJSONObject>('custom_device_info', CustomInfoJSON) then
          Payload.AddPair('custom_device_info', CustomInfoJSON.Clone as TJSONObject);
      end
      else if IsMetricFile then
      begin
        // Metric file - send to metrics endpoint
        Endpoint := '/api/' + EXEWATCH_API_VERSION + '/ingest/metrics';

        // Copy metrics array and session_id directly from file
        if FileJSON.TryGetValue<TJSONArray>('metrics', MetricsArray) then
          Payload.AddPair('metrics', MetricsArray.Clone as TJSONArray);
        if FileJSON.GetValue<string>('session_id', '') <> '' then
          Payload.AddPair('session_id', FileJSON.GetValue<string>('session_id'));
      end
      else
      begin
        // Log file - send to logs endpoint
        Endpoint := '/api/' + EXEWATCH_API_VERSION + '/ingest/logs';

        // Convert events to API format
        EventsArray := TJSONArray.Create;
        if FileJSON.TryGetValue<TJSONArray>('events', SourceEvents) and (SourceEvents.Count > 0) then
        begin
          for I := 0 to SourceEvents.Count - 1 do
          begin
            EventJSON := SourceEvents.Items[I] as TJSONObject;
            APIEvent := TJSONObject.Create;

            // Convert level from enum name to API string
            LevelStr := EventJSON.GetValue<string>('level', 'llInfo');
            if LevelStr.StartsWith('ll') then
              LevelStr := LowerCase(Copy(LevelStr, 3, Length(LevelStr)));
            APIEvent.AddPair('level', LevelStr);

            APIEvent.AddPair('message', EventJSON.GetValue<string>('message', ''));
            TagValue := EventJSON.GetValue<string>('tag', '');
            if TagValue <> '' then
              APIEvent.AddPair('tag', TagValue);
            APIEvent.AddPair('timestamp', EventJSON.GetValue<string>('timestamp', ''));
            APIEvent.AddPair('thread_id', TJSONNumber.Create(EventJSON.GetValue<UInt64>('thread_id', 0)));
            APIEvent.AddPair('process_id', TJSONNumber.Create(EventJSON.GetValue<Cardinal>('process_id', 0)));
            SessionIdValue := EventJSON.GetValue<string>('session_id', '');
            if SessionIdValue <> '' then
              APIEvent.AddPair('session_id', SessionIdValue);

            ExtraData := EventJSON.GetValue('extra_data');
            if (ExtraData <> nil) and (ExtraData is TJSONObject) then
              APIEvent.AddPair('extra_data', (ExtraData as TJSONObject).Clone as TJSONObject);

            EventsArray.AddElement(APIEvent);
          end;
        end;

        // Skip sending if no events (corrupted/empty file)
        if EventsArray.Count = 0 then
        begin
          WriteInternalLog('WARNING | Empty events file, deleting: ' + ExtractFileName(AFilePath));
          EventsArray.Free;
          TFile.Delete(SendingPath);
          Exit;
        end;

        Payload.AddPair('events', EventsArray);
      end;

      // Send to server
      HttpClient.ContentType := 'application/json';
      HttpClient.CustomHeaders['X-API-Key'] := FConfig.ApiKey;
      // Send current config version for dynamic configuration
      if FServerConfigVersion > 0 then
        HttpClient.CustomHeaders['X-Config-Version'] := IntToStr(FServerConfigVersion);
      {$IF CompilerVersion >= 33}
      HttpClient.ConnectionTimeout := 10000;
      HttpClient.ResponseTimeout := 30000;
      {$IFEND}

      RequestContent := TStringStream.Create(Payload.ToJSON, TEncoding.UTF8);

      // Capture request start time for API trace
      RequestStartTime := TStopwatch.StartNew;
      RequestPayload := Payload.ToJSON;
      RequestSize := Length(RequestPayload);

      Response := HttpClient.Post(EffectiveEndpoint + Endpoint, RequestContent);

      // Log API trace (non-blocking)
      RequestStartTime.Stop;
      TraceEntry := Format('[%s] POST %s | %dms | HTTP %d',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
         Endpoint,
         RequestStartTime.ElapsedMilliseconds,
         Response.StatusCode]);
      TraceEntry := TraceEntry + sLineBreak +
        Format('  → Payload (%d bytes): %s',
          [RequestSize,
           Copy(RequestPayload, 1, 500)]);  // First 500 chars
      if Length(RequestPayload) > 500 then
        TraceEntry := TraceEntry + '...';
      TraceEntry := TraceEntry + sLineBreak +
        Format('  ← Response: %s',
          [Copy(Response.ContentAsString, 1, 500)]);  // First 500 chars
      if Length(Response.ContentAsString) > 500 then
        TraceEntry := TraceEntry + '...';
      TraceEntry := TraceEntry + sLineBreak + '---';
      WriteAPITrace(TraceEntry);

      if Response.StatusCode = 200 then
      begin
        // Parse response to check for config updates
        ResponseJson := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
        try
          if ResponseJson <> nil then
          begin
            // Check for dynamic configuration update from server
            lJValue := ResponseJson.GetValue('config');
            if Assigned(lJValue) and (not lJValue.Null) then
            begin
              ApplyServerConfig(lJValue as TJSONObject);
            end;

            if IsCustomInfoFile then
              DoCustomDeviceInfoSent(True, '')
            else if IsDeviceInfoFile then
            begin
              DoDeviceInfoSent(True, '')
            end
            else if IsMetricFile then
            begin
              ResponseJson.GetValue<Integer>('accepted', 0);
              // Metric file sent successfully, no specific callback needed
            end
            else
            begin
              Accepted := ResponseJson.GetValue<Integer>('accepted', 0);
              Rejected := ResponseJson.GetValue<Integer>('rejected', 0);
              DoLogsSent(Accepted, Rejected);
            end;
          end;
        finally
          ResponseJson.Free;
        end;

        // Success! Delete the file
        TFile.Delete(SendingPath);

        // Log first success after failure (so we know when system recovered)
        if FLastSendFailed then
        begin
          WriteInternalLog('OK | Send recovered | File: ' + ExtractFileName(AFilePath));
          FLastSendFailed := False;
        end;
      end
      else if Response.StatusCode = 422 then
      begin
        // Validation error - remove only invalid events from file
        if IsDeviceInfoFile then
        begin
          // Device info has no events to filter, just delete
          WriteInternalLog(Format('WARNING | HTTP 422 on device-info, deleting | File: %s | Response: %s',
            [ExtractFileName(AFilePath), Response.ContentAsString]));
          TFile.Delete(SendingPath);
          // final refusal: the caller is told (a retry would get the same answer)
          if IsCustomInfoFile then
            DoCustomDeviceInfoSent(False, 'HTTP 422: ' + Copy(Response.ContentAsString, 1, 200));
        end
        else
        begin
          // Try to remove invalid events and retry with valid ones
          if RemoveInvalidEventsFromFile(SendingPath, Response.ContentAsString) then
          begin
            // File was modified, restore it for retry with valid events only
            WriteInternalLog(Format('WARNING | HTTP 422, removed invalid events | File: %s',
              [ExtractFileName(AFilePath)]));
            try
              if TFile.Exists(SendingPath) and not TFile.Exists(AFilePath) then
                TFile.Move(SendingPath, AFilePath);
            except
              // If restore fails, delete the sending file
              TFile.Delete(SendingPath);
            end;
          end
          else
          begin
            // No valid events remaining or couldn't parse, delete file
            WriteInternalLog(Format('WARNING | HTTP 422, no valid events remaining, deleting | File: %s | Response: %s',
              [ExtractFileName(AFilePath), Response.ContentAsString]));
            TFile.Delete(SendingPath);
          end;
        end;
        // Don't set NetworkError, continue to next file
      end
      else if Response.StatusCode = 429 then
      begin
        // Plan limit exceeded (metric limit or quota) - delete file, do NOT retry
        WriteInternalLog(Format('WARNING | HTTP 429 - Plan limit exceeded, data dropped | File: %s | Response: %s',
          [ExtractFileName(AFilePath), Copy(Response.ContentAsString, 1, 200)]));
        TFile.Delete(SendingPath);
        if IsCustomInfoFile then
          DoCustomDeviceInfoSent(False, 'HTTP 429: ' + Copy(Response.ContentAsString, 1, 200));
        // Don't set NetworkError - continue to next file
      end
      else
      begin
        // Server error (5xx) or other - restore the file for retry later
        NetworkError := True;
        FLastSendFailed := True;
        WriteInternalLog(Format('ERROR | HTTP %d from %s | File: %s | Response: %s',
          [Response.StatusCode, Endpoint, ExtractFileName(AFilePath), Response.ContentAsString]));
        DoError(Format('HTTP %d: %s', [Response.StatusCode, Response.ContentAsString]));
      end;

    except
      on E: Exception do
      begin
        NetworkError := True;
        FLastSendFailed := True;
        WriteInternalLog(Format('ERROR | Send failed: %s | File: %s | Endpoint: %s',
          [E.Message, ExtractFileName(AFilePath), EffectiveEndpoint + Endpoint]));
        DoError('Send failed: ' + E.Message);

        // Log exception to API trace
        ExceptionTrace := Format('[%s] POST %s | EXCEPTION: %s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
           Endpoint,
           E.Message]);
        ExceptionTrace := ExceptionTrace + sLineBreak +
          Format('  → Payload (%d bytes): %s',
            [RequestSize,
             Copy(RequestPayload, 1, 500)]);
        if Length(RequestPayload) > 500 then
          ExceptionTrace := ExceptionTrace + '...';
        ExceptionTrace := ExceptionTrace + sLineBreak + '---';
        WriteAPITrace(ExceptionTrace);
      end;
    end;
  finally
    HttpClient.Free;
    FileJSON.Free;
    Payload.Free;
    RequestContent.Free;

    // If network error, restore file for retry; otherwise it was processed
    if NetworkError then
    begin
      try
        if TFile.Exists(SendingPath) and not TFile.Exists(AFilePath) then
          TFile.Move(SendingPath, AFilePath);
      except
        // Ignore restore errors
      end;
      Result := False;  // Signal to wait before retrying
    end;
  end;
end;

procedure TExeWatch.PersistThreadExecute;
begin
  while not FShutdown do
  begin
    FPersistEvent.WaitFor;
    if FShutdown then
      Break;
    try
      PersistBuffer;
    except
      on E: Exception do
        WriteInternalLog('ERROR | PersistBuffer failed on the persist thread: ' + E.Message);
    end;
  end;
end;

procedure TExeWatch.ShipperThreadExecute;
var
  PendingFiles: TArray<string>;
  WaitTime: Integer;
  LastFlushTime: TDateTime;
  LastPurgeTime: TDateTime;
  LogFile: string;
begin
  LastFlushTime := Now;
  LastPurgeTime := Now;

  while not FShutdown do
  begin
    // Determine wait time based on whether we have pending files
    // Uses server-configured flush interval (dynamic configuration)
    PendingFiles := GetPendingLogFiles;
    if Length(PendingFiles) > 0 then
      WaitTime := 100  // Quick retry when files are pending
    else
      WaitTime := GetEffectiveFlushInterval;

    FShutdownEvent.WaitFor(WaitTime);

    if FShutdown then
    begin
      // Final persist before shutdown
      PersistBuffer;
      PersistMetricBuffer;
      // Try to send remaining files
      PendingFiles := GetPendingLogFiles;
      for LogFile in PendingFiles do
      begin
        if not SendToServer(LogFile) then
          Break;  // Stop if sending fails
      end;
      Break;
    end;

    // Check if it's time to persist buffer
    if MilliSecondsBetween(Now, LastFlushTime) >= FConfig.FlushIntervalMs then
    begin
      PersistBuffer;
      LastFlushTime := Now;
    end;

    // Check if it's time to flush metric accumulators (every 60 seconds)
    if MilliSecondsBetween(Now, FLastMetricFlushTime) >= EXEWATCH_METRIC_FLUSH_INTERVAL_MS then
    begin
      PersistMetricBuffer;
      FLastMetricFlushTime := Now;
    end;

    // Purge expired files once per hour
    if HoursBetween(Now, LastPurgeTime) >= 1 then
    begin
      PurgeExpiredFiles;
      LastPurgeTime := Now;
    end;

    // Try to send pending files (oldest first)
    PendingFiles := GetPendingLogFiles;
    for LogFile in PendingFiles do
    begin
      if FShutdown then
        Break;

      if not SendToServer(LogFile) then
      begin
        // Wait before retrying
        FShutdownEvent.WaitFor(FConfig.RetryIntervalMs);
        Break;  // Don't try other files, wait for retry
      end;
    end;
  end;
end;

procedure TExeWatch.DoError(const AMessage: string);
begin
  // Note: Called from background thread. Handler should use TThread.Queue if UI access needed.
  if Assigned(FOnError) then
    FOnError(AMessage);
  if Assigned(FClientListener) then
    FClientListener.OnExeWatchError(AMessage);
end;

procedure TExeWatch.DoLogsSent(AAccepted, ARejected: Integer);
begin
  // Note: Called from background thread. Handler should use TThread.Queue if UI access needed.
  if Assigned(FOnLogsSent) then
    FOnLogsSent(AAccepted, ARejected);
  if Assigned(FClientListener) then
    FClientListener.OnExeWatchLogsSent(AAccepted, ARejected);
end;

procedure TExeWatch.DoDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
begin
  // Note: Called from background thread. Handler should use TThread.Queue if UI access needed.
  if Assigned(FOnDeviceInfoSent) then
    FOnDeviceInfoSent(ASuccess, AErrorMessage);
end;

procedure TExeWatch.DoCustomDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
begin
  // Called from the shipper thread, once per SendCustomDeviceInfo file: True when the
  // server took it, False when it refused it for good (422, 429). A failure that will
  // be retried (network, 5xx) is reported by OnError only.
  if Assigned(FOnCustomDeviceInfoSent) then
    FOnCustomDeviceInfoSent(ASuccess, AErrorMessage);
end;

procedure TExeWatch.SetCustomDeviceInfo(const AKey, AValue: string);
begin
  FCustomDeviceInfoLock.Enter;
  try
    FCustomDeviceInfo.AddOrSetValue(AKey, AValue);
  finally
    FCustomDeviceInfoLock.Leave;
  end;
end;

procedure TExeWatch.ClearCustomDeviceInfo(const AKey: string);
begin
  FCustomDeviceInfoLock.Enter;
  try
    FCustomDeviceInfo.Remove(AKey);
  finally
    FCustomDeviceInfoLock.Leave;
  end;
end;

procedure TExeWatch.ClearAllCustomDeviceInfo;
begin
  FCustomDeviceInfoLock.Enter;
  try
    FCustomDeviceInfo.Clear;
  finally
    FCustomDeviceInfoLock.Leave;
  end;
end;

procedure TExeWatch.SendCustomDeviceInfo;
var
  FileContent: TJSONObject;
  CustomInfoJSON: TJSONObject;
  Pair: TPair<string, string>;
  InfoCopy: TDictionary<string, string>;
  FileName: string;
begin
  // Skip if customer_id is not set yet
  if FConfig.CustomerId = '' then
    Exit;

  // Make a copy of the custom info to send
  FCustomDeviceInfoLock.Enter;
  try
    if FCustomDeviceInfo.Count = 0 then
      Exit;
    InfoCopy := TDictionary<string, string>.Create(FCustomDeviceInfo);
  finally
    FCustomDeviceInfoLock.Leave;
  end;

  EnsureStoragePath;

  FileContent := TJSONObject.Create;
  try
    // Build the file content (same format as device info file)
    FileContent.AddPair('customer_id', FConfig.CustomerId);
    FileContent.AddPair('device', FConfig.DeviceInfo.ToJSON);

    // Build custom_device_info JSON object
    CustomInfoJSON := TJSONObject.Create;
    for Pair in InfoCopy do
      CustomInfoJSON.AddPair(Pair.Key, Pair.Value);
    FileContent.AddPair('custom_device_info', CustomInfoJSON);

    // Write to file with .ewdevice extension (will be sent by shipper thread)
    FileName := TPath.Combine(FConfig.StoragePath, FormatDateTime('yyyymmddhhnnsszzz', Now) +
      '_' + IntToStr(TThread.Current.ThreadID) + '_' + IntToStr(AtomicIncrement(FFileCounter)) +
      EXEWATCH_DEVICE_FILE_EXTENSION);
    TFile.WriteAllText(FileName, FileContent.ToJSON, TEncoding.UTF8);
  finally
    FileContent.Free;
    InfoCopy.Free;
  end;
end;

procedure TExeWatch.SendCustomDeviceInfo(const AKey, AValue: string);
begin
  SetCustomDeviceInfo(AKey, AValue);
  SendCustomDeviceInfo;
end;

procedure TExeWatch.SendDeviceInfo;
begin
  // Reset flag to allow re-sending (e.g., after updating custom device info)
  FDeviceInfoSent := False;
  // Queue device info to be sent by the shipper thread
  QueueDeviceInfo;
end;

function TExeWatch.BuildDeviceInfoFile: TJSONObject;
var
  HardwareInfo: THardwareInfo;
  CustomInfoJSON: TJSONObject;
  Pair: TPair<string, string>;
  MergedInfo: TDictionary<string, string>;
begin
  // Collect hardware info
  HardwareInfo := THardwareInfo.Collect;
  if FConfig.AnonymizeDeviceId then
    HardwareInfo.Anonymize(FUserPathRoots, {$IFDEF MSWINDOWS}False{$ELSE}True{$ENDIF});

  Result := TJSONObject.Create;
  try
    // Build the file content
    Result.AddPair('customer_id', FConfig.CustomerId);
    Result.AddPair('device', FConfig.DeviceInfo.ToJSON);
    Result.AddPair('hardware_info', HardwareInfo.ToJSON);

    // Include custom device info (merge InitialCustomDeviceInfo + runtime FCustomDeviceInfo)
    // Always include this field, even if empty, to indicate current state to backend
    MergedInfo := TDictionary<string, string>.Create;
    try
      // Add InitialCustomDeviceInfo (from config)
      for Pair in FConfig.InitialCustomDeviceInfo do
        MergedInfo.AddOrSetValue(Pair.Key, Pair.Value);

      // Add/override with runtime FCustomDeviceInfo
      FCustomDeviceInfoLock.Enter;
      try
        for Pair in FCustomDeviceInfo do
          MergedInfo.AddOrSetValue(Pair.Key, Pair.Value);
      finally
        FCustomDeviceInfoLock.Leave;
      end;

      // Build JSON from merged info (always include, even if empty)
      // Empty {} tells backend to clear custom device info
      CustomInfoJSON := TJSONObject.Create;
      for Pair in MergedInfo do
        CustomInfoJSON.AddPair(Pair.Key, Pair.Value);
      Result.AddPair('custom_device_info', CustomInfoJSON);
    finally
      MergedInfo.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TExeWatch.QueueDeviceInfo;
var
  FileContent: TJSONObject;
  FileName: string;
begin
  // Skip if customer_id is not set yet (will be sent when SetCustomerId is called)
  if FConfig.CustomerId = '' then
    Exit;

  // Skip if already sent
  if FDeviceInfoSent then
    Exit;

  EnsureStoragePath;

  FileContent := BuildDeviceInfoFile;
  try
    // Write to file with .ewdevice extension
    FileName := TPath.Combine(FConfig.StoragePath, FormatDateTime('yyyymmddhhnnsszzz', Now) +
      '_' + IntToStr(TThread.Current.ThreadID) + '_' + IntToStr(AtomicIncrement(FFileCounter)) +
      EXEWATCH_DEVICE_FILE_EXTENSION);
    TFile.WriteAllText(FileName, FileContent.ToJSON, TEncoding.UTF8);

    // Mark as sent so we don't send again
    FDeviceInfoSent := True;
  finally
    FileContent.Free;
  end;
end;

procedure TExeWatch.Log(ALevel: TEWLogLevel; const AMessage, ATag: string;
  AExtraData: TJSONObject);
begin
  // Delegate to the full overload with current timestamp and thread ID
  Log(ALevel, AMessage, ATag, Now, EWCurrentThreadId, AExtraData);
end;

procedure TExeWatch.Log(ALevel: TEWLogLevel; const AMessage, ATag: string;
  ATimestamp: TDateTime; AThreadId: UInt64; AExtraData: TJSONObject);
var
  Event: TLogEvent;
  ShouldPersist: Boolean;
  PersistAsync: Boolean;
  NowTick: UInt64;
  BuiltExtraData: TJSONObject;
  IncludeBreadcrumbs: Boolean;
  IsErrorLevel: Boolean;
  TruncatedMessage: string;
  EffectiveBatchSize: Integer;
  StackTrace: string;
begin
  // Check both local and server-driven enabled flags
  if not FEnabled or not GetEffectiveEnabled then
  begin
    AExtraData.Free;
    Exit;
  end;

  // Skip empty messages (backend requires at least 1 character)
  if Trim(AMessage) = '' then
  begin
    AExtraData.Free;
    Exit;
  end;

  IsErrorLevel := ALevel in [llError, llFatal];

  // Apply min_level filtering from server. Error and fatal used to bypass this,
  // which turned the console's "Minimum Level" into a suggestion: a customer who
  // picked Fatal kept sending, and paying for, every Error. Sampling below still
  // spares them, which is a separate setting.
  if Ord(ALevel) < Ord(GetEffectiveMinLevel) then
  begin
    AExtraData.Free;
    Exit;
  end;

  // Apply sampling (errors and fatal always bypass sampling)
  if not IsErrorLevel and not ShouldSample then
  begin
    AExtraData.Free;
    Exit;
  end;

  // Truncate message if it exceeds server-configured limit
  TruncatedMessage := TruncateMessage(AMessage);

  // Notify listener for pass-through to other logging systems
  if Assigned(FClientListener) then
    FClientListener.OnExeWatchLog(ALevel, TruncatedMessage, ATag);

  // Attach stack trace for ERROR/FATAL logs
  if IsErrorLevel then
  begin
    if AExtraData = nil then
      AExtraData := TJSONObject.Create;
    if AExtraData.GetValue('stack_trace') = nil then
    begin
      StackTrace := GetStackTraceStr(3);
      if StackTrace <> '' then
        AExtraData.AddPair('stack_trace', StackTrace)
      else
        AExtraData.AddPair('no_stacktrace_reason', TJSONNumber.Create(GetNoStackTraceReason));
    end;
    AttachSymbolSource(AExtraData);
  end;

  // Build extra data with user, tags, release, and optionally breadcrumbs
  IncludeBreadcrumbs := IsErrorLevel;
  BuiltExtraData := BuildExtraData(AExtraData, IncludeBreadcrumbs);
  AExtraData.Free;

  // Clear breadcrumbs after including them in an error
  if IncludeBreadcrumbs then
    ClearBreadcrumbs;

  // Use custom timestamp, thread ID and cached process ID
  Event := TLogEvent.Create(ALevel, TruncatedMessage, ATag, FSessionId, ATimestamp, AThreadId, FProcessId, BuiltExtraData);

  // Use server-configured batch size
  FServerConfigLock.Enter;
  try
    EffectiveBatchSize := FServerBatchSize;
  finally
    FServerConfigLock.Leave;
  end;

  FBufferLock.Enter;
  try
    FBuffer.Add(Event);
    ShouldPersist := FBuffer.Count >= EffectiveBatchSize;
    PersistAsync := False;
    // An error or fatal can be the last thing the process records before it dies:
    // it has the persist thread write the whole buffer now instead of waiting for
    // the timer, and the caller does not wait for the disk. At most once per
    // second (the first error of a burst), so a burst does not become a burst of
    // files. The rest waits for the timer.
    if IsErrorLevel and not ShouldPersist and (FConfig.CustomerId <> '') then
    begin
      {$IFDEF MSWINDOWS}
      NowTick := EWGetTickCount64;
      {$ELSE}
      NowTick := TThread.GetTickCount;
      {$ENDIF}
      if NowTick - FLastErrorPersistTick >= EXEWATCH_ERROR_PERSIST_MIN_GAP_MS then
      begin
        FLastErrorPersistTick := NowTick;
        PersistAsync := True;
      end;
    end;
  finally
    FBufferLock.Leave;
  end;

  if PersistAsync then
    FPersistEvent.SetEvent;

  // Logging must never raise into the host; an error is often logged from inside
  // the host's own handler.
  if ShouldPersist then
  try
    PersistBuffer;
  except
    on E: Exception do
      WriteInternalLog('ERROR | PersistBuffer failed in Log: ' + E.Message);
  end;
end;

procedure TExeWatch.Debug(const AMessage, ATag: string);
begin
  Log(llDebug, AMessage, ATag);
end;

procedure TExeWatch.Info(const AMessage, ATag: string);
begin
  Log(llInfo, AMessage, ATag);
end;

procedure TExeWatch.Warning(const AMessage, ATag: string);
begin
  Log(llWarning, AMessage, ATag);
end;

procedure TExeWatch.Error(const AMessage, ATag: string);
begin
  Log(llError, AMessage, ATag);
end;

procedure TExeWatch.Fatal(const AMessage, ATag: string);
begin
  Log(llFatal, AMessage, ATag);
end;

// Format-style overloads

procedure TExeWatch.Debug(const AFormat: string; const AArgs: array of const; const ATag: string);
begin
  Log(llDebug, Format(AFormat, AArgs), ATag);
end;

procedure TExeWatch.Info(const AFormat: string; const AArgs: array of const; const ATag: string);
begin
  Log(llInfo, Format(AFormat, AArgs), ATag);
end;

procedure TExeWatch.Warning(const AFormat: string; const AArgs: array of const; const ATag: string);
begin
  Log(llWarning, Format(AFormat, AArgs), ATag);
end;

procedure TExeWatch.Error(const AFormat: string; const AArgs: array of const; const ATag: string);
begin
  Log(llError, Format(AFormat, AArgs), ATag);
end;

procedure TExeWatch.Fatal(const AFormat: string; const AArgs: array of const; const ATag: string);
begin
  Log(llFatal, Format(AFormat, AArgs), ATag);
end;

procedure TExeWatch.ErrorWithException(E: Exception; const ATag,
  AAdditionalMessage: string);
var
  ExtraData: TJSONObject;
  Msg: string;
{$IFDEF MSWINDOWS}
  StackTrace: string;
{$ENDIF}
begin
  ExtraData := TJSONObject.Create;
  if E <> nil then
  begin
    ExtraData.AddPair('exception_class', E.ClassName);
    ExtraData.AddPair('exception_message', ScrubUserPaths(E.Message));
  end;
  {$IFDEF MSWINDOWS}
  // The trace taken where the exception was raised, when it has one: from a
  // handler that caught it far from the raise, the current stack is only the
  // handler's own chain. The current stack (skipping this method) is the
  // fallback: an exception raised before the hook was installed, one never
  // raised, and no exception at all (nil), where it is the only trace there is.
  StackTrace := GetLastExceptionStackTrace(E);
  if StackTrace = '' then
    StackTrace := GetStackTraceStr(1);
  ExtraData.AddPair('stack_trace', StackTrace);
  {$ENDIF}

  // A framework's exception handler can be called without an exception (a
  // route that does not exist, for one): logging must never raise, so the
  // call is reported as what it is.
  if E = nil then
  begin
    if Trim(AAdditionalMessage) <> '' then
      Msg := AAdditionalMessage
    else
      Msg := 'ErrorWithException called without an exception';
  end
  else if AAdditionalMessage <> '' then
    Msg := AAdditionalMessage + ': ' + ScrubUserPaths(E.Message)
  else
    Msg := ScrubUserPaths(E.Message);

  Log(llError, Msg, ATag, ExtraData);
end;

function TExeWatch.ScrubUserPaths(const AText: string): string;
begin
  // The message the runtime writes for a file it cannot open holds the folder of the user,
  // and with it the name.
  if FConfig.AnonymizeDeviceId then
    Result := TExeWatchHelper.ScrubUserPaths(AText, FUserPathRoots, {$IFDEF MSWINDOWS}False{$ELSE}True{$ENDIF})
  else
    Result := AText;
end;

procedure TExeWatch.Flush;
begin
  PersistBuffer;
  PersistMetricBuffer;
end;

function TExeWatch.GetPendingCount: Integer;
begin
  Result := Length(GetPendingLogFiles);
  FBufferLock.Enter;
  try
    Inc(Result, FBuffer.Count);
  finally
    FBufferLock.Leave;
  end;
end;

function TExeWatch.WaitForSending(ATimeoutSec: Integer): Integer;
const
  POLL_MS = 100;
var
  SW: TStopwatch;
  TimeoutMs: Int64;
begin
  Flush;
  if ATimeoutSec < 0 then ATimeoutSec := 0;
  TimeoutMs := Int64(ATimeoutSec) * 1000;
  SW := TStopwatch.StartNew;
  while GetPendingCount > 0 do
  begin
    if SW.ElapsedMilliseconds >= TimeoutMs then Break;
    Sleep(POLL_MS);
  end;
  Result := GetPendingCount;
end;

procedure TExeWatch.Shutdown;
begin
  if FShutdown then
    Exit;

  // Clear callbacks first to prevent access violations if caller's
  // object is destroyed before shipper thread finishes
  FOnError := nil;
  FOnLogsSent := nil;
  FOnDeviceInfoSent := nil;
  FOnCustomDeviceInfoSent := nil;
  FClientListener := nil;

  FShutdown := True;
  FShutdownEvent.SetEvent;
  FPersistEvent.SetEvent;

  if FShipperThread <> nil then
  begin
    FShipperThread.WaitFor;
    FreeAndNil(FShipperThread);
  end;
  if FPersistThread <> nil then
  begin
    FPersistThread.WaitFor;
    FreeAndNil(FPersistThread);
  end;
end;

// ============================================================
// Sampling
// ============================================================

function TExeWatch.ShouldSample: Boolean;
var
  EffectiveRate: Double;
begin
  // Use server-configured sampling rate (takes precedence over local config)
  EffectiveRate := GetEffectiveSamplingRate;
  if EffectiveRate >= 1.0 then
    Result := True
  else if EffectiveRate <= 0 then
    Result := False
  else
    Result := Random < EffectiveRate;
end;

// ============================================================
// Build Extra Data with user, tags, release, breadcrumbs
// ============================================================

function TExeWatch.BuildExtraData(AExtraData: TJSONObject; AIncludeBreadcrumbs: Boolean): TJSONObject;
var
  Pair: TPair<string, string>;
  BreadcrumbsArray: TJSONArray;
  Breadcrumb: TBreadcrumb;
  ThreadId: TThreadID;
  ThreadBreadcrumbs: TList<TBreadcrumb>;
  I: Integer;
begin
  Result := TJSONObject.Create;

  // Copy user-provided extra data
  if AExtraData <> nil then
  begin
    for I := 0 to AExtraData.Count - 1 do
      Result.AddPair(AExtraData.Pairs[I].JsonString.Value,
        AExtraData.Pairs[I].JsonValue.Clone as TJSONValue);
  end;

  // Add global tags (prefixed with 'tag_')
  FGlobalTagsLock.Enter;
  try
    for Pair in FGlobalTags do
      Result.AddPair('tag_' + Pair.Key, Pair.Value);
  finally
    FGlobalTagsLock.Leave;
  end;

  // Add user info
  FCurrentUserLock.Enter;
  try
    if not FCurrentUser.IsEmpty then
    begin
      if FCurrentUser.Id <> '' then
        Result.AddPair('user_id', FCurrentUser.Id);
      if FCurrentUser.Email <> '' then
        Result.AddPair('user_email', FCurrentUser.Email);
      if FCurrentUser.Name <> '' then
        Result.AddPair('user_name', FCurrentUser.Name);
    end;
  finally
    FCurrentUserLock.Leave;
  end;

  // Add breadcrumbs for errors (only from current thread)
  if AIncludeBreadcrumbs then
  begin
    FBreadcrumbsLock.Enter;
    try
      ThreadId := TThread.Current.ThreadID;
      if FBreadcrumbs.TryGetValue(ThreadId, ThreadBreadcrumbs) and (ThreadBreadcrumbs.Count > 0) and
         (not FBreadcrumbOwners.ContainsKey(ThreadId) or (GMyBreadcrumbGen = 0) or (FBreadcrumbOwners[ThreadId] = GMyBreadcrumbGen)) then
      begin
        BreadcrumbsArray := TJSONArray.Create;
        for Breadcrumb in ThreadBreadcrumbs do
          BreadcrumbsArray.AddElement(Breadcrumb.ToJSON);
        Result.AddPair('breadcrumbs', BreadcrumbsArray);
      end;
    finally
      FBreadcrumbsLock.Leave;
    end;
  end;

  // If result is empty, free it and return nil
  if Result.Count = 0 then
  begin
    Result.Free;
    Result := nil;
  end;
end;

// ============================================================
// Breadcrumbs
// ============================================================

procedure TExeWatch.AddBreadcrumb(ABreadcrumbType: TBreadcrumbType; const ACategory, AMessage: string;
  AData: TJSONObject);
var
  Crumb: TBreadcrumb;
  ThreadId: TThreadID;
  ThreadBreadcrumbs: TList<TBreadcrumb>;
begin
  Crumb := TBreadcrumb.Create(ABreadcrumbType, ACategory, AMessage, AData);
  ThreadId := TThread.Current.ThreadID;

  FBreadcrumbsLock.Enter;
  try
    // Assign unique generation to this thread on first breadcrumb access
    if GMyBreadcrumbGen = 0 then
      GMyBreadcrumbGen := TInterlocked.Increment(GBreadcrumbNextGen);

    // Get or create breadcrumb list for current thread
    if not FBreadcrumbs.TryGetValue(ThreadId, ThreadBreadcrumbs) then
    begin
      ThreadBreadcrumbs := TList<TBreadcrumb>.Create;
      FBreadcrumbs.Add(ThreadId, ThreadBreadcrumbs);
      FBreadcrumbOwners.AddOrSetValue(ThreadId, GMyBreadcrumbGen);
    end
    else
    begin
      // Detect ThreadID reuse (common on Linux) — clear stale breadcrumbs
      if FBreadcrumbOwners.ContainsKey(ThreadId) and
         (FBreadcrumbOwners[ThreadId] <> GMyBreadcrumbGen) then
      begin
        ThreadBreadcrumbs.Clear;
        FBreadcrumbOwners[ThreadId] := GMyBreadcrumbGen;
      end;
    end;

    ThreadBreadcrumbs.Add(Crumb);

    // Keep only last N breadcrumbs for this thread, freeing Data of removed ones
    while ThreadBreadcrumbs.Count > EXEWATCH_MAX_BREADCRUMBS do
    begin
      if ThreadBreadcrumbs[0].Data <> nil then
        ThreadBreadcrumbs[0].Data.Free;
      ThreadBreadcrumbs.Delete(0);
    end;
  finally
    FBreadcrumbsLock.Leave;
  end;
end;

procedure TExeWatch.AddBreadcrumb(const AMessage: string; const ACategory: string);
begin
  AddBreadcrumb(btCustom, ACategory, AMessage, nil);
end;

function TExeWatch.GetBreadcrumbs: TArray<TBreadcrumb>;
var
  ThreadId: TThreadID;
  ThreadBreadcrumbs: TList<TBreadcrumb>;
begin
  ThreadId := TThread.Current.ThreadID;

  // Assign unique generation to this thread if not yet assigned
  if GMyBreadcrumbGen = 0 then
    GMyBreadcrumbGen := TInterlocked.Increment(GBreadcrumbNextGen);

  FBreadcrumbsLock.Enter;
  try
    // Return breadcrumbs only for current thread
    if FBreadcrumbs.TryGetValue(ThreadId, ThreadBreadcrumbs) then
    begin
      // Detect ThreadID reuse — return empty if owner changed
      if FBreadcrumbOwners.ContainsKey(ThreadId) and
         (FBreadcrumbOwners[ThreadId] <> GMyBreadcrumbGen) then
        SetLength(Result, 0)
      else
        Result := ThreadBreadcrumbs.ToArray;
    end
    else
      SetLength(Result, 0); // No breadcrumbs for this thread
  finally
    FBreadcrumbsLock.Leave;
  end;
end;

procedure TExeWatch.ClearBreadcrumbs;
var
  I: Integer;
  ThreadId: TThreadID;
  ThreadBreadcrumbs: TList<TBreadcrumb>;
begin
  ThreadId := TThread.Current.ThreadID;

  FBreadcrumbsLock.Enter;
  try
    // Clear breadcrumbs only for current thread
    if FBreadcrumbs.TryGetValue(ThreadId, ThreadBreadcrumbs) then
    begin
      for I := 0 to ThreadBreadcrumbs.Count - 1 do
        if ThreadBreadcrumbs[I].Data <> nil then
          ThreadBreadcrumbs[I].Data.Free;
      ThreadBreadcrumbs.Free;
      // Remove from dictionary
      FBreadcrumbs.Remove(ThreadId);
      FBreadcrumbOwners.Remove(ThreadId);
    end;
  finally
    FBreadcrumbsLock.Leave;
  end;
end;

// ============================================================
// Timing / Profiling
// ============================================================

procedure TExeWatch.StartTiming(const AId: string; const ATag: string);
begin
  StartTiming(AId, ATag, nil);
end;

procedure TExeWatch.StartTiming(const AId: string; const ATag: string; AMetadata: TJSONObject);
var
  Entry: TTimingEntry;
  OldestId: string;
  OldEntry: TTimingEntry;
  HasDuplicate: Boolean;
  DuplicateEntry: TTimingEntry;
  EvictedIds: TArray<string>;
  EvictedValues: TArray<TTimingEntry>;
  EvictedCount: Integer;
  I: Integer;
  AutoCloseDurationMs: Double;
  AutoCloseExtraData: TJSONObject;
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
  ParentId: string;
  ParentEntry: TTimingEntry;
begin
  if AId = '' then
    Exit;

  Entry := TTimingEntry.Create(ATag, AMetadata);

  HasDuplicate := False;
  ThreadId := TThread.Current.ThreadID;

  FPendingTimingsLock.Enter;
  try
    // Assign unique generation to this thread on first timing access
    if GMyTimingGen = 0 then
      GMyTimingGen := TInterlocked.Increment(GTimingNextGen);

    // Get or create per-thread dicts (+ detect ThreadID reuse on Linux)
    if not FPendingTimings.TryGetValue(ThreadId, ThreadTimings) then
    begin
      ThreadTimings := TDictionary<string, TTimingEntry>.Create;
      FPendingTimings.Add(ThreadId, ThreadTimings);
      ThreadStack := TList<string>.Create;
      FTimingStacks.Add(ThreadId, ThreadStack);
      FPendingTimingsOwners.AddOrSetValue(ThreadId, GMyTimingGen);
    end
    else
    begin
      // ThreadID was seen before — check whether it's still owned by this thread.
      // If not (ThreadID reuse after a different thread exited without EndTiming),
      // drop the stale entries silently: they belonged to a dead thread.
      if FPendingTimingsOwners.ContainsKey(ThreadId) and
         (FPendingTimingsOwners[ThreadId] <> GMyTimingGen) then
      begin
        for OldEntry in ThreadTimings.Values do
          if OldEntry.Metadata <> nil then
            OldEntry.Metadata.Free;
        ThreadTimings.Clear;
        if FTimingStacks.TryGetValue(ThreadId, ThreadStack) then
          ThreadStack.Clear;
        FPendingTimingsOwners[ThreadId] := GMyTimingGen;
      end;
      if not FTimingStacks.TryGetValue(ThreadId, ThreadStack) then
      begin
        ThreadStack := TList<string>.Create;
        FTimingStacks.Add(ThreadId, ThreadStack);
      end;
    end;

    // Check for duplicate - auto-close the previous timing before starting new one
    if ThreadTimings.TryGetValue(AId, DuplicateEntry) then
    begin
      HasDuplicate := True;
      ThreadTimings.Remove(AId);
      ThreadStack.Remove(AId);
    end;

    // Check max pending timings (per-thread) — collect oldest for auto-close (FIFO)
    EvictedCount := 0;
    while ThreadTimings.Count >= EXEWATCH_MAX_PENDING_TIMINGS do
    begin
      if ThreadStack.Count > 0 then
      begin
        OldestId := ThreadStack[0];
        if ThreadTimings.TryGetValue(OldestId, OldEntry) then
        begin
          SetLength(EvictedIds, EvictedCount + 1);
          SetLength(EvictedValues, EvictedCount + 1);
          EvictedIds[EvictedCount] := OldestId;
          EvictedValues[EvictedCount] := OldEntry;
          Inc(EvictedCount);
          ThreadTimings.Remove(OldestId);
        end;
        ThreadStack.Delete(0);
      end
      else
        Break;
    end;

    // Nested timing traces: inherit the trace from the span currently on top of
    // the stack. Only spans inside an active trace (parent TraceId <> '') get ids,
    // so a plain nested StartTiming without StartTrace stays flat (TraceId '').
    if ThreadStack.Count > 0 then
    begin
      ParentId := ThreadStack[ThreadStack.Count - 1];
      if ThreadTimings.TryGetValue(ParentId, ParentEntry) and (ParentEntry.TraceId <> '') then
      begin
        Entry.TraceId := ParentEntry.TraceId;
        Entry.ParentSpanId := ParentEntry.SpanId;
        Entry.SpanId := ExeWatchGenerateId16;
      end;
    end;

    ThreadTimings.Add(AId, Entry);
    ThreadStack.Add(AId);
  finally
    FPendingTimingsLock.Leave;
  end;

  // Auto-close entries OUTSIDE the lock (Log acquires other locks)

  // Auto-close duplicate timing
  if HasDuplicate then
  begin
    AutoCloseExtraData := TJSONObject.Create;
    AutoCloseExtraData.AddPair('timing_type', 'duration');
    AutoCloseExtraData.AddPair('timing_id', AId);
    AutoCloseDurationMs := (TStopwatch.GetTimeStamp - DuplicateEntry.StartTicks)
      / TStopwatch.Frequency * 1000;
    AutoCloseExtraData.AddPair('duration_ms', TJSONNumber.Create(AutoCloseDurationMs));
    AutoCloseExtraData.AddPair('success', EWJsonBool(False));
    AutoCloseExtraData.AddPair('auto_closed', EWJsonBool(True));
    AutoCloseExtraData.AddPair('auto_close_reason', 'duplicate_start');
    if DuplicateEntry.Metadata <> nil then
    begin
      AutoCloseExtraData.AddPair('metadata', DuplicateEntry.Metadata.Clone as TJSONObject);
      DuplicateEntry.Metadata.Free;
    end;
    Log(llWarning, Format('[TIMING] %s: %.2fms (auto-closed, duplicate StartTiming)', [AId, AutoCloseDurationMs]),
      DuplicateEntry.Tag, AutoCloseExtraData);
  end;

  // Auto-close evicted timings (max pending reached)
  for I := 0 to EvictedCount - 1 do
  begin
    AutoCloseExtraData := TJSONObject.Create;
    AutoCloseExtraData.AddPair('timing_type', 'duration');
    AutoCloseExtraData.AddPair('timing_id', EvictedIds[I]);
    AutoCloseDurationMs := (TStopwatch.GetTimeStamp - EvictedValues[I].StartTicks)
      / TStopwatch.Frequency * 1000;
    AutoCloseExtraData.AddPair('duration_ms', TJSONNumber.Create(AutoCloseDurationMs));
    AutoCloseExtraData.AddPair('success', EWJsonBool(False));
    AutoCloseExtraData.AddPair('auto_closed', EWJsonBool(True));
    AutoCloseExtraData.AddPair('auto_close_reason', 'max_pending_reached');
    if EvictedValues[I].Metadata <> nil then
    begin
      AutoCloseExtraData.AddPair('metadata', EvictedValues[I].Metadata.Clone as TJSONObject);
      EvictedValues[I].Metadata.Free;
    end;
    Log(llWarning, Format('[TIMING] %s: %.2fms (auto-closed, max pending timings reached)', [EvictedIds[I], AutoCloseDurationMs]),
      EvictedValues[I].Tag, AutoCloseExtraData);
  end;
end;

procedure TExeWatch.StartTiming(const AIdFormat: string; const AArgs: array of const; const ATag: string);
begin
  StartTiming(Format(AIdFormat, AArgs), ATag, nil);
end;

function TExeWatch.EndTiming(const AId: string; AEndMetadata: TJSONObject; ASuccess: Boolean): Double;
var
  Entry: TTimingEntry;
  Found: Boolean;
  DurationMs: Double;
  ExtraData: TJSONObject;
  MergedMetadata: TJSONObject;
  I: Integer;
  LogMessage: string;
  StackIdx: Integer;
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
begin
  Result := -1;

  if AId = '' then
  begin
    Log(llDebug, 'EndTiming: Empty ID provided', 'exewatch');
    if AEndMetadata <> nil then
      AEndMetadata.Free;
    Exit;
  end;

  ThreadId := TThread.Current.ThreadID;
  Found := False;

  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       FPendingTimingsOwners.ContainsKey(ThreadId) and
       (GMyTimingGen <> 0) and
       (FPendingTimingsOwners[ThreadId] = GMyTimingGen) then
    begin
      Found := ThreadTimings.TryGetValue(AId, Entry);
      if Found then
      begin
        ThreadTimings.Remove(AId);
        if FTimingStacks.TryGetValue(ThreadId, ThreadStack) then
        begin
          StackIdx := ThreadStack.IndexOf(AId);
          if StackIdx >= 0 then
            ThreadStack.Delete(StackIdx);
        end;
      end;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;

  if not Found then
  begin
    Log(llDebug, Format('EndTiming: No active timing found for ID "%s"', [AId]), 'exewatch');
    if AEndMetadata <> nil then
      AEndMetadata.Free;
    Exit;
  end;

  // Calculate duration in milliseconds using high-precision TStopwatch
  DurationMs := (TStopwatch.GetTimeStamp - Entry.StartTicks) / TStopwatch.Frequency * 1000;
  Result := DurationMs;

  // Build extra_data for the log
  ExtraData := TJSONObject.Create;
  ExtraData.AddPair('timing_type', 'duration');
  ExtraData.AddPair('timing_id', AId);
  ExtraData.AddPair('duration_ms', TJSONNumber.Create(DurationMs));
  ExtraData.AddPair('success', EWJsonBool(ASuccess));

  // Nested timing traces: emit the tree relationship when this span belongs to a
  // trace. parent_span_id '' marks the root (the backend maps it to NULL).
  if Entry.TraceId <> '' then
  begin
    ExtraData.AddPair('trace_id', Entry.TraceId);
    ExtraData.AddPair('span_id', Entry.SpanId);
    ExtraData.AddPair('parent_span_id', Entry.ParentSpanId);
  end;

  // Merge metadata: start metadata + end metadata
  if (Entry.Metadata <> nil) or (AEndMetadata <> nil) then
  begin
    MergedMetadata := TJSONObject.Create;
    // Copy start metadata
    if Entry.Metadata <> nil then
    begin
      for I := 0 to Entry.Metadata.Count - 1 do
        MergedMetadata.AddPair(Entry.Metadata.Pairs[I].JsonString.Value,
          Entry.Metadata.Pairs[I].JsonValue.Clone as TJSONValue);
    end;
    // Copy/overwrite with end metadata
    if AEndMetadata <> nil then
    begin
      for I := 0 to AEndMetadata.Count - 1 do
        MergedMetadata.AddPair(AEndMetadata.Pairs[I].JsonString.Value,
          AEndMetadata.Pairs[I].JsonValue.Clone as TJSONValue);
    end;
    if MergedMetadata.Count > 0 then
      ExtraData.AddPair('metadata', MergedMetadata)
    else
      MergedMetadata.Free;
  end;

  // Free original metadata objects
  if Entry.Metadata <> nil then
    Entry.Metadata.Free;
  if AEndMetadata <> nil then
    AEndMetadata.Free;

  // Build log message
  LogMessage := Format('[TIMING] %s: %.2fms', [AId, DurationMs]);

  // Send as INFO log with user-defined tag
  Log(llInfo, LogMessage, Entry.Tag, ExtraData);
end;

function TExeWatch.EndTiming(const AIdFormat: string; const AArgs: array of const;
  AEndMetadata: TJSONObject; ASuccess: Boolean): Double;
begin
  Result := EndTiming(Format(AIdFormat, AArgs), AEndMetadata, ASuccess);
end;

function TExeWatch.EndTiming: Double;
var
  LastId: string;
  ThreadId: TThreadID;
  ThreadStack: TList<string>;
begin
  Result := -1;
  LastId := '';
  ThreadId := TThread.Current.ThreadID;

  FPendingTimingsLock.Enter;
  try
    if FTimingStacks.TryGetValue(ThreadId, ThreadStack) and
       FPendingTimingsOwners.ContainsKey(ThreadId) and
       (GMyTimingGen <> 0) and
       (FPendingTimingsOwners[ThreadId] = GMyTimingGen) and
       (ThreadStack.Count > 0) then
      LastId := ThreadStack[ThreadStack.Count - 1];
  finally
    FPendingTimingsLock.Leave;
  end;

  if LastId = '' then
  begin
    Log(llDebug, 'EndTiming: No active timing to end (stack empty)', 'exewatch');
    Exit;
  end;

  Result := EndTiming(LastId, nil, True);
end;

function TExeWatch.StartTrace(const AName: string): string;
var
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
  TopId: string;
  TopEntry: TTimingEntry;
  ActiveTraceId: string;
  NewTraceId: string;
  RootEntry: TTimingEntry;
begin
  Result := '';
  if AName = '' then
    Exit;

  ThreadId := TThread.Current.ThreadID;
  ActiveTraceId := '';

  // Is a trace already open on this thread? (top-of-stack span carries its trace id)
  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       FTimingStacks.TryGetValue(ThreadId, ThreadStack) and
       (ThreadStack.Count > 0) then
    begin
      TopId := ThreadStack[ThreadStack.Count - 1];
      if ThreadTimings.TryGetValue(TopId, TopEntry) then
        ActiveTraceId := TopEntry.TraceId;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;

  if ActiveTraceId <> '' then
  begin
    // No nested traces — degrade to a child span under the active trace.
    Log(llDebug, Format('StartTrace("%s") while a trace is active — nesting as a child span', [AName]), 'exewatch');
    StartTiming(AName, '');
    Result := ActiveTraceId;
    Exit;
  end;

  // Open a new root: create the entry via the robust StartTiming path (handles
  // per-thread dict/stack creation, ownership, eviction), then promote it to a
  // root by stamping its trace/span ids. At stack-empty StartTiming leaves it flat.
  StartTiming(AName, '');
  NewTraceId := ExeWatchGenerateId16;

  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       ThreadTimings.TryGetValue(AName, RootEntry) then
    begin
      RootEntry.TraceId := NewTraceId;
      RootEntry.SpanId := ExeWatchGenerateId16;
      RootEntry.ParentSpanId := '';  // root
      ThreadTimings.AddOrSetValue(AName, RootEntry);  // store the modified record back
      Result := NewTraceId;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;
end;

function TExeWatch.EndTrace: Double;
var
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
  TopId: string;
  TopEntry: TTimingEntry;
  ActiveTraceId: string;
  RootId: string;
  OpenChildIds: TArray<string>;
  ChildCount: Integer;
  I: Integer;
begin
  Result := -1;
  ThreadId := TThread.Current.ThreadID;
  ActiveTraceId := '';
  RootId := '';
  ChildCount := 0;

  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       FTimingStacks.TryGetValue(ThreadId, ThreadStack) and
       (ThreadStack.Count > 0) then
    begin
      TopId := ThreadStack[ThreadStack.Count - 1];
      if ThreadTimings.TryGetValue(TopId, TopEntry) then
        ActiveTraceId := TopEntry.TraceId;

      if ActiveTraceId <> '' then
      begin
        // Walk the stack top-down: the root carries ParentSpanId ''; everything
        // else of this trace still open is a forgotten child to force-close.
        for I := ThreadStack.Count - 1 downto 0 do
        begin
          TopId := ThreadStack[I];
          if ThreadTimings.TryGetValue(TopId, TopEntry) and (TopEntry.TraceId = ActiveTraceId) then
          begin
            if TopEntry.ParentSpanId = '' then
              RootId := TopId
            else
            begin
              SetLength(OpenChildIds, ChildCount + 1);
              OpenChildIds[ChildCount] := TopId;
              Inc(ChildCount);
            end;
          end;
        end;
      end;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;

  if ActiveTraceId = '' then
  begin
    Log(llDebug, 'EndTrace: no active trace on this thread', 'exewatch');
    Exit;
  end;

  // Force-close any child timings left open (forgotten EndTiming) as failed, so
  // the tree is complete; then close the root (reuses EndTiming's span emit).
  for I := 0 to ChildCount - 1 do
    EndTiming(OpenChildIds[I], nil, False);

  if RootId <> '' then
    Result := EndTiming(RootId, nil, True);
end;

function TExeWatch.IsTimingActive(const AId: string): Boolean;
var
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
begin
  Result := False;
  ThreadId := TThread.Current.ThreadID;
  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       FPendingTimingsOwners.ContainsKey(ThreadId) and
       (GMyTimingGen <> 0) and
       (FPendingTimingsOwners[ThreadId] = GMyTimingGen) then
      Result := ThreadTimings.ContainsKey(AId);
  finally
    FPendingTimingsLock.Leave;
  end;
end;

procedure TExeWatch.CancelTiming(const AId: string);
var
  Entry: TTimingEntry;
  StackIdx: Integer;
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
begin
  if AId = '' then
    Exit;

  ThreadId := TThread.Current.ThreadID;
  FPendingTimingsLock.Enter;
  try
    if FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
       FPendingTimingsOwners.ContainsKey(ThreadId) and
       (GMyTimingGen <> 0) and
       (FPendingTimingsOwners[ThreadId] = GMyTimingGen) and
       ThreadTimings.TryGetValue(AId, Entry) then
    begin
      if Entry.Metadata <> nil then
        Entry.Metadata.Free;
      ThreadTimings.Remove(AId);
      if FTimingStacks.TryGetValue(ThreadId, ThreadStack) then
      begin
        StackIdx := ThreadStack.IndexOf(AId);
        if StackIdx >= 0 then
          ThreadStack.Delete(StackIdx);
      end;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;
end;

procedure TExeWatch.CancelTiming;
var
  LastId: string;
  ThreadId: TThreadID;
  ThreadStack: TList<string>;
begin
  LastId := '';
  ThreadId := TThread.Current.ThreadID;

  FPendingTimingsLock.Enter;
  try
    if FTimingStacks.TryGetValue(ThreadId, ThreadStack) and
       FPendingTimingsOwners.ContainsKey(ThreadId) and
       (GMyTimingGen <> 0) and
       (FPendingTimingsOwners[ThreadId] = GMyTimingGen) and
       (ThreadStack.Count > 0) then
      LastId := ThreadStack[ThreadStack.Count - 1];
  finally
    FPendingTimingsLock.Leave;
  end;

  if LastId <> '' then
    CancelTiming(LastId);
end;

function TExeWatch.GetActiveTimings: TArray<TActiveTimingInfo>;
var
  I: Integer;
  Entry: TTimingEntry;
  Info: TActiveTimingInfo;
  Id: string;
  ThreadId: TThreadID;
  ThreadTimings: TDictionary<string, TTimingEntry>;
  ThreadStack: TList<string>;
begin
  SetLength(Result, 0);
  ThreadId := TThread.Current.ThreadID;
  FPendingTimingsLock.Enter;
  try
    if not (FPendingTimings.TryGetValue(ThreadId, ThreadTimings) and
            FTimingStacks.TryGetValue(ThreadId, ThreadStack) and
            FPendingTimingsOwners.ContainsKey(ThreadId) and
            (GMyTimingGen <> 0) and
            (FPendingTimingsOwners[ThreadId] = GMyTimingGen)) then
      Exit;

    SetLength(Result, ThreadStack.Count);
    for I := 0 to ThreadStack.Count - 1 do
    begin
      Id := ThreadStack[I];
      if ThreadTimings.TryGetValue(Id, Entry) then
      begin
        Info.Id := Id;
        Info.Tag := Entry.Tag;
        Info.ElapsedMs := (TStopwatch.GetTimeStamp - Entry.StartTicks) / TStopwatch.Frequency * 1000;
        Result[I] := Info;
      end;
    end;
  finally
    FPendingTimingsLock.Leave;
  end;
end;

// ============================================================
// User Identity
// ============================================================

procedure TExeWatch.SetUser(const AUser: TUserIdentity);
begin
  FCurrentUserLock.Enter;
  try
    FCurrentUser := AUser;
  finally
    FCurrentUserLock.Leave;
  end;
end;

procedure TExeWatch.SetUser(const AId, AEmail, AName: string);
begin
  SetUser(TUserIdentity.Create(AId, AEmail, AName));
end;

procedure TExeWatch.ClearUser;
begin
  FCurrentUserLock.Enter;
  try
    FCurrentUser := Default(TUserIdentity);
  finally
    FCurrentUserLock.Leave;
  end;
end;

function TExeWatch.GetUser: TUserIdentity;
begin
  FCurrentUserLock.Enter;
  try
    Result := FCurrentUser;
  finally
    FCurrentUserLock.Leave;
  end;
end;

// ============================================================
// Customer ID
// ============================================================

procedure TExeWatch.SetCustomerId(const ACustomerId: string);
var
  CustomerIdChanged: Boolean;
begin
  WriteInternalLog('SetCustomerId called | CustomerId=' + ACustomerId);

  // Check if customer_id actually changed (and wasn't empty before)
  CustomerIdChanged := (FConfig.CustomerId <> ACustomerId) and (FConfig.CustomerId <> '');
  FConfig.CustomerId := ACustomerId;
  // Events logged while it was empty could not be persisted: do it now
  FPersistEvent.SetEvent;

  // If customer_id changed, re-send device info with new customer_id
  // (new customer_id = new device record in backend, need complete info)
  if CustomerIdChanged then
  begin
    WriteInternalLog('Customer ID changed, re-sending device info');
    FDeviceInfoSent := False;  // Reset flag to allow re-sending
    QueueDeviceInfo;           // Queue complete device info with new customer_id
  end
  // If device info wasn't sent yet (because customer_id was empty at init), send it now
  else if not FDeviceInfoSent then
    QueueDeviceInfo;
end;

function TExeWatch.GetCustomerId: string;
begin
  Result := FConfig.CustomerId;
end;

// ============================================================
// Global Tags
// ============================================================

procedure TExeWatch.SetTags(const ATags: TArray<TPair<string, string>>);
var
  Pair: TPair<string, string>;
begin
  FGlobalTagsLock.Enter;
  try
    for Pair in ATags do
      FGlobalTags.AddOrSetValue(Pair.Key, Pair.Value);
  finally
    FGlobalTagsLock.Leave;
  end;
end;

procedure TExeWatch.SetTag(const AKey, AValue: string);
begin
  FGlobalTagsLock.Enter;
  try
    FGlobalTags.AddOrSetValue(AKey, AValue);
  finally
    FGlobalTagsLock.Leave;
  end;
end;

procedure TExeWatch.RemoveTag(const AKey: string);
begin
  FGlobalTagsLock.Enter;
  try
    FGlobalTags.Remove(AKey);
  finally
    FGlobalTagsLock.Leave;
  end;
end;

procedure TExeWatch.ClearTags;
begin
  FGlobalTagsLock.Enter;
  try
    FGlobalTags.Clear;
  finally
    FGlobalTagsLock.Leave;
  end;
end;

function TExeWatch.GetTags: TArray<TPair<string, string>>;
begin
  FGlobalTagsLock.Enter;
  try
    Result := FGlobalTags.ToArray;
  finally
    FGlobalTagsLock.Leave;
  end;
end;

// ============================================================
// Metrics (Counters & Gauges)
// ============================================================

procedure TExeWatch.IncrementCounter(const AName: string; AValue: Double; const ATag: string);
var
  Key: string;
  Acc: TMetricAccumulator;
begin
  Key := AName + '|' + ATag;
  FMetricAccumulatorsLock.Enter;
  try
    if FMetricAccumulators.TryGetValue(Key, Acc) then
    begin
      Acc.Value := Acc.Value + AValue;
      Acc.SampleCount := Acc.SampleCount + 1;
      FMetricAccumulators[Key] := Acc;
    end
    else
    begin
      Acc := TMetricAccumulator.CreateCounter(AName, ATag);
      Acc.Value := AValue;
      Acc.SampleCount := 1;
      FMetricAccumulators.Add(Key, Acc);
    end;
  finally
    FMetricAccumulatorsLock.Leave;
  end;
end;

procedure TExeWatch.RecordGauge(const AName: string; AValue: Double; const ATag: string);
var
  Key: string;
  Acc: TMetricAccumulator;
begin
  Key := AName + '|' + ATag;
  FMetricAccumulatorsLock.Enter;
  try
    if FMetricAccumulators.TryGetValue(Key, Acc) then
    begin
      Acc.Value := AValue;  // Gauge: last value
      if AValue < Acc.MinValue then Acc.MinValue := AValue;
      if AValue > Acc.MaxValue then Acc.MaxValue := AValue;
      Acc.SumValue := Acc.SumValue + AValue;
      Acc.SampleCount := Acc.SampleCount + 1;
      FMetricAccumulators[Key] := Acc;
    end
    else
    begin
      Acc := TMetricAccumulator.CreateGauge(AName, ATag, AValue);
      FMetricAccumulators.Add(Key, Acc);
    end;
  finally
    FMetricAccumulatorsLock.Leave;
  end;
end;

procedure TExeWatch.RegisterPeriodicGauge(const AName: string; ACallback: TGaugeCallback; const ATag: string);
var
  Reg: TGaugeRegistration;
begin
  FRegisteredGaugesLock.Enter;
  try
    if FRegisteredGauges.Count >= EXEWATCH_MAX_REGISTERED_GAUGES then
    begin
      WriteInternalLog('RegisterPeriodicGauge: max gauge limit reached (' +
        IntToStr(EXEWATCH_MAX_REGISTERED_GAUGES) + ')');
      Exit;
    end;
    // Remove if already registered (overwrite)
    UnregisterPeriodicGaugeInternal(AName);
    Reg.Name := AName;
    Reg.Tag := ATag;
    Reg.Callback := ACallback;
    FRegisteredGauges.Add(Reg);
    // Start sampler thread if not running
    if FSamplerThread = nil then
    begin
      FSamplerThread := TThread.CreateAnonymousThread(SamplerThreadExecute);
      FSamplerThread.FreeOnTerminate := False;
      FSamplerThread.Start;
    end;
  finally
    FRegisteredGaugesLock.Leave;
  end;
end;

procedure TExeWatch.UnregisterPeriodicGauge(const AName: string);
begin
  FRegisteredGaugesLock.Enter;
  try
    UnregisterPeriodicGaugeInternal(AName);
  finally
    FRegisteredGaugesLock.Leave;
  end;
end;

procedure TExeWatch.UnregisterPeriodicGaugeInternal(const AName: string);
var
  I: Integer;
begin
  // Must be called with FRegisteredGaugesLock held
  for I := FRegisteredGauges.Count - 1 downto 0 do
    if SameText(FRegisteredGauges[I].Name, AName) then
      FRegisteredGauges.Delete(I);
end;

procedure TExeWatch.SamplerThreadExecute;
var
  WaitMs: Integer;
  Gauges: TArray<TGaugeRegistration>;
  Reg: TGaugeRegistration;
  GaugeValue: Double;
  EffectiveInterval: Integer;
begin
  EffectiveInterval := FConfig.GaugeSamplingIntervalSec;
  if EffectiveInterval < EXEWATCH_MIN_GAUGE_SAMPLING_INTERVAL_SEC then
    EffectiveInterval := EXEWATCH_MIN_GAUGE_SAMPLING_INTERVAL_SEC;
  WaitMs := EffectiveInterval * 1000;

  while not FShutdown do
  begin
    FShutdownEvent.WaitFor(WaitMs);
    if FShutdown then Break;

    // Copy snapshot of registered gauges (brief lock)
    FRegisteredGaugesLock.Enter;
    try
      if FRegisteredGauges.Count = 0 then
        Continue;
      Gauges := FRegisteredGauges.ToArray;
    finally
      FRegisteredGaugesLock.Leave;
    end;

    // Sample all gauges
    for Reg in Gauges do
    begin
      if FShutdown then Break;
      try
        GaugeValue := Reg.Callback();
        RecordGauge(Reg.Name, GaugeValue, Reg.Tag);
      except
        on E: Exception do
          WriteInternalLog('Gauge callback error for "' + Reg.Name + '": ' + E.Message);
      end;
    end;
  end;
end;

function TExeWatch.GetNextMetricFileName: string;
begin
  Inc(FFileCounter);
  Result := TPath.Combine(FConfig.StoragePath,
    Format('%s_%d_%d%s', [
      FormatDateTime('yyyymmdd_hhnnsszzz', Now),
      FFileCounter,
      TThread.CurrentThread.ThreadID,
      EXEWATCH_METRIC_FILE_EXTENSION
    ]));
end;

procedure TExeWatch.PersistMetricBuffer;
var
  Accumulators: TArray<TPair<string, TMetricAccumulator>>;
  FileContent: TJSONObject;
  MetricsArray: TJSONArray;
  MetricObj: TJSONObject;
  Pair: TPair<string, TMetricAccumulator>;
  Acc: TMetricAccumulator;
  FileName: string;
  PeriodEnd: TDateTime;
begin
  if FConfig.CustomerId = '' then
    Exit;

  PeriodEnd := Now;

  FMetricAccumulatorsLock.Enter;
  try
    if FMetricAccumulators.Count = 0 then
      Exit;
    Accumulators := FMetricAccumulators.ToArray;
    FMetricAccumulators.Clear;
  finally
    FMetricAccumulatorsLock.Leave;
  end;

  // Build JSON file
  FileContent := TJSONObject.Create;
  try
    FileContent.AddPair('customer_id', FConfig.CustomerId);
    FileContent.AddPair('device', FConfig.DeviceInfo.ToJSON);
    FileContent.AddPair('session_id', FSessionId);

    MetricsArray := TJSONArray.Create;
    for Pair in Accumulators do
    begin
      Acc := Pair.Value;
      MetricObj := TJSONObject.Create;
      MetricObj.AddPair('name', Acc.Name);
      MetricObj.AddPair('type', Acc.MetricType);
      MetricObj.AddPair('value', TJSONNumber.Create(Acc.Value));
      if Acc.Tag <> '' then
        MetricObj.AddPair('tag', Acc.Tag);
      MetricObj.AddPair('count', TJSONNumber.Create(Acc.SampleCount));

      if Acc.MetricType = 'gauge' then
      begin
        MetricObj.AddPair('min', TJSONNumber.Create(Acc.MinValue));
        MetricObj.AddPair('max', TJSONNumber.Create(Acc.MaxValue));
        if Acc.SampleCount > 0 then
          MetricObj.AddPair('avg', TJSONNumber.Create(Acc.SumValue / Acc.SampleCount));
      end;

      MetricObj.AddPair('period_start', DateToISO8601(Acc.PeriodStart, False));
      MetricObj.AddPair('period_end', DateToISO8601(PeriodEnd, False));

      MetricsArray.AddElement(MetricObj);
    end;
    FileContent.AddPair('metrics', MetricsArray);

    FileName := GetNextMetricFileName;
    TFile.WriteAllText(FileName, FileContent.ToJSON, TEncoding.UTF8);
  finally
    FileContent.Free;
  end;
end;

// ============================================================
// Version
// ============================================================

function TExeWatch.GetAppVersion: string;
begin
  Result := FConfig.AppVersion;
end;

// ============================================================
// Stack Trace Support (Windows only)
// ============================================================

{$IFDEF MSWINDOWS}
{$STACKFRAMES ON}

const
  ST_MAX_FRAMES = 62;
  // The symbol table for a module is published only once it is complete. Two
  // threads used to pass the flag check together and both load, each freeing
  // and regrowing the arrays under the other.
  ST_INIT_IDLE = 0;
  ST_INIT_LOADING = 1;
  ST_INIT_READY = 2;
  // How far past the last entry of the map an address may still be attributed
  // to it. The bound used to be a flat $1000000, which silently refused to
  // resolve anything more than 16 MB past the module base - a real limit for a
  // large executable, and invisible when it bites.
  ST_ADDR_SLACK = $10000;
  // The .map is linked INTO the executable at build time; an external .map
  // file beside the module only backs it up during development. Two storage
  // forms are read, in this order: a dedicated .ewmap section appended by the
  // build-time injectors (deterministic PE surgery, works for any section
  // layout), then the RCDATA resource some tooling still produces.
  EW_MAP_SECTION_NAME = '.ewmap';
  // The section payload is a 32-byte header (TEWMapHeader), then the stored
  // map. The 14 magic bytes never change, so a reader can always tell "an
  // ExeWatch map" from "something else"; the rest says HOW the map was stored,
  // and a reader that does not know that says so instead of reporting an
  // absent map.
  EW_MAP_MAGIC: array[0..13] of AnsiChar = 'EXEWATCHMAPSIG';
  EW_MAP_FORMAT_VERSION = 1;
  EW_MAP_CODEC_RAW = 0;
  EW_MAP_CODEC_ZLIB = 1;
  // A map larger than this is not a map: refused before anything is allocated.
  EW_MAP_MAX_RAW = 256 * 1024 * 1024;
  // symbol_source values for a section that is there but cannot be used.
  EW_SRC_UNSUPPORTED = 'unsupported_map_format';
  EW_SRC_CORRUPT = 'corrupt_map';
  EW_MAP_RESOURCE_NAME = 'EXEWATCH_MAP';
  // GetModuleHandleEx is not part of Winapi.Windows: local import constants.
  EW_GMHE_UNCHANGED_REFCOUNT = $2;
  EW_GMHE_FROM_ADDRESS = $4;

type
  // The head of the .ewmap payload, little endian, 32 bytes. HeaderSize lets a
  // later version add fields at the tail that this reader skips; FormatVersion
  // changes only when the meaning of the existing fields does. Mirrors
  // TMapHeader in Core\EWMapInjectU.pas.
  TEWMapHeader = packed record
    Magic: array[0..13] of AnsiChar;
    FormatVersion: Word;
    HeaderSize: Word;     // bytes from the start of the payload to the stored map
    Codec: Byte;          // EW_MAP_CODEC_*
    Flags: Byte;          // reserved, 0
    RawSize: Cardinal;    // the map text, before compression
    StoredSize: Cardinal; // bytes right after the header
    Crc32: Cardinal;      // of the map text, before compression
  end;
  PEWMapHeader = ^TEWMapHeader;

  // What the section reader found: a map, no section, or a section this
  // reader cannot use - and which of the two reasons.
  TSTMapStatus = (msOk, msAbsent, msUnsupported, msCorrupt);

  TSTSymbol = record
    Address: NativeUInt;
    Name: string;
  end;

  TSTLineInfo = record
    Address: NativeUInt;
    Line: Integer;
    UnitName: string;
  end;

  // One symbol table per module: frames are attributed to the module that
  // contains them, so a frame inside a DLL never resolves against the host
  // map and vice versa. Immutable once built; entries keep living for the
  // whole process, so a lookup that got the pointer out of the cache can use
  // it without holding the lock.
  TSTModuleSymbols = class
  private
    FSymbolCount: Integer;
    FLineCount: Integer;
  public
    // True while the table is being built outside the lock: readers that hit
    // the placeholder give up their trace (Loaded=False) instead of waiting
    // on the raiser path.
    Building: Boolean;
    Module: THandle;
    Base: NativeUInt;
    SizeOfImage: Cardinal;
    // Where the symbol text came from: 'embedded', 'map_file' or 'none'.
    Source: string;
    ProgramName: string;
    SegOffsets: TArray<NativeUInt>;
    SegCount: Integer;
    Symbols: TArray<TSTSymbol>;
    Lines: TArray<TSTLineInfo>;
    Loaded: Boolean;
    procedure SetSegOffset(ASeg: Integer; AOffset: NativeUInt);
    function GetSegOffset(ASeg: Integer): NativeUInt;
    procedure AddSymbol(AAddress: NativeUInt; const AName: string);
    procedure AddLine(AAddress: NativeUInt; ALine: Integer; const AUnitName: string);
    procedure ShrinkAndSort;
    // The same, and where the symbol starts (module-relative).
    function FindSymbolAt(AAddress: NativeUInt; out AStart: NativeUInt): string;
    // ALineStart: where the line entry found starts (module-relative).
    procedure FindLine(AAddress: NativeUInt; out ALine: Integer; out AUnit: string;
      out ALineStart: NativeUInt);
  end;

type
  TRtlCaptureStackBackTrace = function(
    FramesToSkip, FramesToCapture: ULONG;
    BackTrace: Pointer; BackTraceHash: PULONG): USHORT; stdcall;

function GetModuleHandleExW(dWFlags: DWORD; lpModuleName: LPCWSTR;
  var phModule: HMODULE): BOOL; stdcall; external kernel32 name 'GetModuleHandleExW';

type
  // One entry per exported function, sorted by RVA for the nearest-below
  // binary search.
  TSTExportEntry = record
    RVA: NativeUInt;
    Name: string;
  end;
  TSTExportTable = array of TSTExportEntry;

  // Word/Cardinal arrays to walk the export directory in place (the RTL has
  // no typed aliases for these).
  TSTCardinalArray = array [0..(MaxInt - $F) div SizeOf(Cardinal) - 1] of Cardinal;
  PSTCardinalArray = ^TSTCardinalArray;
  TSTWordArray = array [0..(MaxInt - $F) div SizeOf(Word) - 1] of Word;
  PSTWordArray = ^TSTWordArray;

type
  // One cached export table of a module, for the stale check on reloaded
  // handles.
  TSTExportCache = class
  public
    Base: NativeUInt;
    SizeOfImage: Cardinal;
    Table: TSTExportTable;
  end;

var
  // One entry per module, negative results included (Loaded=False): a module
  // with no symbols at all must not re-attempt its build for every frame.
  GSTModuleSymbols: TDictionary<THandle, TSTModuleSymbols>;
  GSTModuleSymbolsLock: TCriticalSection;
  // Export tables keyed per module handle (validated against the mounted
  // image size at every lookup: handles are recycled), negative results
  // (empty tables) included: parse once, binary search thereafter.
  GSTExportTables: TDictionary<THandle, TSTExportCache>;
  GSTHostInfo: TSTModuleInfo;
  GSTInitState: Integer;  // ST_INIT_* - touched only through TInterlocked
{$IFDEF EXEWATCH_TESTING}
  // Counts threads inside a symbol-table build. More than one at a time IS
  // the defect, and is what the regression test asserts against.
  GSTLoadInFlight: Integer;
  GSTLoadInFlightMax: Integer;
  // Widens the window between reading the state and claiming it, so the race
  // is reproducible instead of depending on a two-instruction gap.
  GSTTestYieldBeforeClaim: Boolean;
{$ENDIF}

var
  GSTCapture: TRtlCaptureStackBackTrace = nil;

procedure TSTModuleSymbols.SetSegOffset(ASeg: Integer; AOffset: NativeUInt);
begin
  if ASeg < 1 then
    Exit;
  if ASeg > Length(SegOffsets) then
    SetLength(SegOffsets, ASeg);  // elements Delphi has not filled yet stay 0
  if ASeg > SegCount then
    SegCount := ASeg;
  SegOffsets[ASeg - 1] := AOffset;
end;

function TSTModuleSymbols.GetSegOffset(ASeg: Integer): NativeUInt;
begin
  if (ASeg >= 1) and (ASeg <= Length(SegOffsets)) then
    Result := SegOffsets[ASeg - 1]
  else
    Result := 0;
end;

procedure TSTModuleSymbols.AddSymbol(AAddress: NativeUInt; const AName: string);
begin
  if FSymbolCount >= Length(Symbols) then
  begin
    if Length(Symbols) = 0 then
      SetLength(Symbols, 1024)
    else
      SetLength(Symbols, Length(Symbols) * 2);
  end;
  Symbols[FSymbolCount].Address := AAddress;
  Symbols[FSymbolCount].Name := AName;
  Inc(FSymbolCount);
end;

procedure TSTModuleSymbols.AddLine(AAddress: NativeUInt; ALine: Integer; const AUnitName: string);
begin
  if FLineCount >= Length(Lines) then
  begin
    if Length(Lines) = 0 then
      SetLength(Lines, 4096)
    else
      SetLength(Lines, Length(Lines) * 2);
  end;
  Lines[FLineCount].Address := AAddress;
  Lines[FLineCount].Line := ALine;
  Lines[FLineCount].UnitName := AUnitName;
  Inc(FLineCount);
end;

procedure TSTModuleSymbols.ShrinkAndSort;
begin
  SetLength(Symbols, FSymbolCount);
  SetLength(Lines, FLineCount);
  if Length(Symbols) > 1 then
    TArray.Sort<TSTSymbol>(Symbols, TComparer<TSTSymbol>.Construct(
      function(const A, B: TSTSymbol): Integer
      begin
        if A.Address < B.Address then Result := -1
        else if A.Address > B.Address then Result := 1
        else Result := 0;
      end));
  if Length(Lines) > 1 then
    TArray.Sort<TSTLineInfo>(Lines, TComparer<TSTLineInfo>.Construct(
      function(const A, B: TSTLineInfo): Integer
      begin
        if A.Address < B.Address then Result := -1
        else if A.Address > B.Address then Result := 1
        else Result := 0;
      end));
end;

function TSTModuleSymbols.FindSymbolAt(AAddress: NativeUInt; out AStart: NativeUInt): string;
var
  Lo, Hi, Mid, Found: Integer;
  RelAddr: NativeUInt;
begin
  Result := '';
  AStart := 0;
  if (Length(Symbols) = 0) or (AAddress < Base) then Exit;
  RelAddr := AAddress - Base;
  // Bounded by what the map actually covers, not by a flat 16 MB.
  if RelAddr > Symbols[High(Symbols)].Address + ST_ADDR_SLACK then Exit;
  // Sorted ascending by ShrinkAndSort, so the last entry <= RelAddr is found
  // by halving instead of by walking. This runs for every frame of every
  // exception, and a large map holds ~10^6 entries.
  Lo := 0;
  Hi := High(Symbols);
  Found := -1;
  while Lo <= Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if Symbols[Mid].Address <= RelAddr then
    begin
      Found := Mid;
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
  if Found >= 0 then
  begin
    Result := Symbols[Found].Name;
    AStart := Symbols[Found].Address;
  end;
end;

procedure TSTModuleSymbols.FindLine(AAddress: NativeUInt; out ALine: Integer; out AUnit: string;
  out ALineStart: NativeUInt);
var
  Lo, Hi, Mid, Found: Integer;
  RelAddr: NativeUInt;
begin
  ALine := 0;
  AUnit := '';
  ALineStart := 0;
  if (Length(Lines) = 0) or (AAddress < Base) then Exit;
  RelAddr := AAddress - Base;
  if RelAddr > Lines[High(Lines)].Address + ST_ADDR_SLACK then Exit;
  Lo := 0;
  Hi := High(Lines);
  Found := -1;
  while Lo <= Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if Lines[Mid].Address <= RelAddr then
    begin
      Found := Mid;
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
  if Found >= 0 then
  begin
    ALine := Lines[Found].Line;
    AUnit := Lines[Found].UnitName;
    ALineStart := Lines[Found].Address;
  end;
end;

function STHexToNative(const S: string): NativeUInt;
var
  T: string;
begin
  T := Trim(S);
  if T = '' then
    Result := 0
  else
    Result := StrToInt64Def('$' + T, 0);
end;

procedure STParseAddr(const S: string; out SegNum: Integer; out Addr: NativeUInt);
var
  ColonPos: Integer;
begin
  ColonPos := Pos(':', S);
  if ColonPos > 0 then
  begin
    SegNum := StrToIntDef('$' + Copy(S, 1, ColonPos - 1), 0);
    Addr := STHexToNative(Copy(S, ColonPos + 1, Length(S)));
  end
  else
  begin
    SegNum := 0;
    Addr := 0;
  end;
end;

// Extract next whitespace-delimited token from S starting at Pos (1-based).
// Returns empty string if no more tokens. Updates Pos past the token.
function STNextToken(const S: string; var P: Integer): string;
var
  Start, Len: Integer;
begin
  Len := Length(S);
  // Skip whitespace
  while (P <= Len) and (S[P] = ' ') do Inc(P);
  if P > Len then begin Result := ''; Exit; end;
  Start := P;
  while (P <= Len) and (S[P] <> ' ') do Inc(P);
  Result := Copy(S, Start, P - Start);
end;

// Parses the Borland map text of ONE module into AOut: segments, publics by
// value and line numbers, all module-relative. The caller already has the
// text in memory (resource or file), so nothing here touches disk.
procedure STBuildSymbols(const AText: string; AOut: TSTModuleSymbols);
var
  SL: TStringList;
  I, K, P: Integer;
  Line, UnitName, Tok1, Tok2, Tok3, Tok4: string;
  EmptyCount, LineNum: Integer;
  BaseAddr, ImageBase: NativeUInt;
  VirtualAddr, PreferredBase: UInt64;
  SegNum: Integer;
  BaseKnown, NameIsFirstToken: Boolean;
begin
  ImageBase := 0;
  PreferredBase := 0;
  BaseKnown := False;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    I := 0;
    while I < SL.Count do
    begin
      Line := Trim(SL[I]);

      // Win64x maps say where the image is meant to load; their symbols carry a
      // full address (Rva+Base) to measure from it
      if Pos('Preferred load address is', Line) > 0 then
      begin
        PreferredBase := StrToInt64Def('$' + Trim(Copy(Line, Pos('address is', Line) + 10, MaxInt)), 0);
        Inc(I);
        Continue;
      end;

      // Main segments - capture offsets for ALL code segments
      if Line.StartsWith('Start') and (Pos('Length', Line) > 0) and (Pos('Name', Line) > 0) then
      begin
        Inc(I);
        while I < SL.Count do
        begin
          Line := Trim(SL[I]);
          if Line = '' then begin Inc(I); Break; end;
          P := 1;
          Tok1 := STNextToken(Line, P);
          Tok2 := STNextToken(Line, P);
          Tok3 := STNextToken(Line, P);
          Tok4 := STNextToken(Line, P);
          if (Tok1 <> '') and (Tok4 <> '') then
          begin
            STParseAddr(Tok1, SegNum, BaseAddr);
            if SegNum >= 1 then
            begin
              // The image base is the first segment's start rounded down to 1 MB;
              // every segment's offset is measured from it. shortcut: an image
              // linked at a base that is not a multiple of 1 MB ({$IMAGEBASE}
              // custom) is off by the remainder; read the PE header's base
              // instead if that ever matters. Masking each
              // segment on its own put a segment that starts 1 MB or more
              // above the base (the .itext of a large program, where the main
              // block lives) in the middle of the code.
              if not BaseKnown then
              begin
                ImageBase := BaseAddr and not NativeUInt($FFFFF);
                BaseKnown := True;
              end;
              // Every segment gets its offset, not only CODE/ICODE: publics
              // of data segments stored without it landed at tiny addresses
              // and made low addresses resolve to the wrong symbol.
              // a segment below the base (.tls is listed at 0) stays at 0, not
              // wrapped around to the top of the address space
              if BaseAddr >= ImageBase then
                AOut.SetSegOffset(SegNum, BaseAddr - ImageBase)
              else
                AOut.SetSegOffset(SegNum, 0);
            end;
          end;
          Inc(I);
        end;
        Continue;
      end;

      // Publics by Value - store module-relative addresses
      if Pos('Publics by Value', Line) > 0 then
      begin
        // The header of a Win64x map has more columns (Rva+Base, Lib:Object):
        // there the name is the first word after the address.
        NameIsFirstToken := Pos('Rva+Base', Line) > 0;
        Inc(I);
        EmptyCount := 0;
        while I < SL.Count do
        begin
          Line := Trim(SL[I]);
          if Line = '' then
          begin
            Inc(EmptyCount);
            Inc(I);
            if EmptyCount >= 2 then Break;
            Continue;
          end;
          EmptyCount := 0;
          if Line.StartsWith('Address') then begin Inc(I); Continue; end;
          if Line.StartsWith('Line numbers') then Break;
          P := 1;
          Tok1 := STNextToken(Line, P);
          // The name is the rest of the line, not one word: the C++ linker
          // writes '__fastcall TForm1::Button1Click(TObject *)', and a Delphi
          // name has no space to lose.
          if NameIsFirstToken then
          begin
            // Win64x: the segment table lists many .text$... sections that share
            // one segment number, each starting at its own offset, so segment
            // plus offset says nothing; the Rva+Base column is the address.
            Tok2 := STNextToken(Line, P);
            Tok3 := STNextToken(Line, P);
            VirtualAddr := StrToInt64Def('$' + Tok3, 0);
            if (Tok1 <> '') and (Tok2 <> '') and (PreferredBase > 0) and
               (VirtualAddr > PreferredBase) then
              AOut.AddSymbol(NativeUInt(VirtualAddr - PreferredBase), Tok2);
          end
          else
          begin
            Tok2 := Trim(Copy(Line, P, MaxInt));
            if (Tok1 <> '') and (Tok2 <> '') then
            begin
              STParseAddr(Tok1, SegNum, BaseAddr);
              if SegNum > 0 then
                AOut.AddSymbol(BaseAddr + AOut.GetSegOffset(SegNum), Tok2);
            end;
          end;
          Inc(I);
        end;
        Continue;
      end;

      // Line numbers - store module-relative addresses
      if Line.StartsWith('Line numbers for') then
      begin
        K := Pos('Line numbers for ', Line);
        if K > 0 then
        begin
          UnitName := Copy(Line, K + 17, Length(Line));
          K := Pos('(', UnitName);
          if K > 0 then
            UnitName := Copy(UnitName, 1, K - 1);
          UnitName := Trim(UnitName);
        end
        else
          UnitName := '';
        Inc(I);
        // Skip empty lines after header
        while (I < SL.Count) and (Trim(SL[I]) = '') do Inc(I);
        while I < SL.Count do
        begin
          Line := Trim(SL[I]);
          if (Line = '') or Line.StartsWith('Line numbers for') then Break;
          P := 1;
          while True do
          begin
            Tok1 := STNextToken(Line, P);
            Tok2 := STNextToken(Line, P);
            if (Tok1 = '') or (Tok2 = '') then Break;
            LineNum := StrToIntDef(Tok1, 0);
            if LineNum > 0 then
            begin
              STParseAddr(Tok2, SegNum, BaseAddr);
              if SegNum > 0 then
                AOut.AddLine(BaseAddr + AOut.GetSegOffset(SegNum), LineNum, UnitName);
            end;
          end;
          Inc(I);
        end;
        Continue;
      end;

      Inc(I);
    end;

    AOut.ShrinkAndSort;
    AOut.Loaded := True;
  finally
    SL.Free;
  end;
end;

// Which loaded module owns this address. GetModuleHandleEx is not declared in
// Winapi.Windows, so it is imported above; UNCHANGED_REFCOUNT keeps the
// lookup allocation-free and the handle valid for the process lifetime.
function STModuleInfoForAddress(AAddress: NativeUInt): TSTModuleInfo;
var
  H: HMODULE;
  FileName: string;
  DosHeader: PImageDosHeader;
  Nt32: PImageNtHeaders32;
  Nt64: PImageNtHeaders64;
const
  ST_MODULE_FLAGS = EW_GMHE_UNCHANGED_REFCOUNT or EW_GMHE_FROM_ADDRESS;
begin
  Result.Module := 0;
  Result.Base := 0;
  Result.SizeOfImage := 0;
  Result.ModuleName := '';
  if AAddress = 0 then
    Exit;
  if not GetModuleHandleExW(ST_MODULE_FLAGS, LPCWSTR(AAddress), H) then
    Exit;
  Result.Module := H;
  Result.Base := NativeUInt(H);
  FileName := GetModuleName(H);
  Result.ModuleName := ExtractFileName(FileName);
  DosHeader := PImageDosHeader(Result.Base);
  if DosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    Exit;
  Nt32 := PImageNtHeaders32(Result.Base + NativeUInt(DosHeader^._lfanew));
  if Nt32^.Signature <> IMAGE_NT_SIGNATURE then
    Exit;
  case Nt32^.OptionalHeader.Magic of
    IMAGE_NT_OPTIONAL_HDR32_MAGIC:
      begin
        Result.SizeOfImage := Nt32^.OptionalHeader.SizeOfImage;
        Exit;
      end;
    IMAGE_NT_OPTIONAL_HDR64_MAGIC:
      begin
        Nt64 := PImageNtHeaders64(Result.Base + NativeUInt(DosHeader^._lfanew));
        Result.SizeOfImage := Nt64^.OptionalHeader.SizeOfImage;
      end;
  end;
end;

// The map text of a .ewmap payload (header, then the stored map), decoded and
// checked. A pure function of the bytes: the section reader below and the test
// project both call it, so the format has one reader.
function STDecodeMapPayload(AData: PByte; ASize: Integer;
  out ABytes: TBytes): TSTMapStatus;
var
  Header: PEWMapHeader;
  Stored: PByte;
  Inflated: Pointer;
  InflatedSize: Integer;
begin
  ABytes := nil;
  if ASize < SizeOf(TEWMapHeader) then
    Exit(msCorrupt);
  Header := PEWMapHeader(AData);
  if not CompareMem(@Header^.Magic, @EW_MAP_MAGIC, SizeOf(EW_MAP_MAGIC)) then
    Exit(msCorrupt);
  // A version this reader does not know is not damage: the exe was linked by a
  // newer tool than this SDK, and the answer is "update the SDK".
  if Header^.FormatVersion > EW_MAP_FORMAT_VERSION then
    Exit(msUnsupported);
  if (Header^.FormatVersion < EW_MAP_FORMAT_VERSION) or
     (Header^.HeaderSize < SizeOf(TEWMapHeader)) or
     (Int64(Header^.HeaderSize) + Int64(Header^.StoredSize) > Int64(ASize)) or
     (Header^.RawSize = 0) or (Header^.RawSize > EW_MAP_MAX_RAW) then
    Exit(msCorrupt);
  Stored := PByte(NativeUInt(AData) + NativeUInt(Header^.HeaderSize));
  case Header^.Codec of
    EW_MAP_CODEC_RAW:
      begin
        if Header^.StoredSize <> Header^.RawSize then
          Exit(msCorrupt);
        SetLength(ABytes, Header^.RawSize);
        Move(Stored^, ABytes[0], Header^.RawSize);
      end;
    EW_MAP_CODEC_ZLIB:
      begin
        try
          ZDecompress(Stored, Integer(Header^.StoredSize), Inflated,
            InflatedSize, Integer(Header^.RawSize));
        except
          // A damaged stream: the RTL raises, and a failed read of the map has
          // to degrade to "no symbols", never to a crash in the error path.
          Exit(msCorrupt);
        end;
        try
          if Cardinal(InflatedSize) <> Header^.RawSize then
            Exit(msCorrupt);
          SetLength(ABytes, InflatedSize);
          Move(Inflated^, ABytes[0], InflatedSize);
        finally
          FreeMem(Inflated);
        end;
      end;
  else
    Exit(msUnsupported);
  end;
  if crc32(0, PByte(ABytes), Length(ABytes)) <> Header^.Crc32 then
  begin
    ABytes := nil;
    Exit(msCorrupt);
  end;
  Result := msOk;
end;

// Map text shipped inside a module image as the dedicated .ewmap section,
// appended by the build-time injectors: a header, then the stored map.
// Pure memory walk of the in-place PE header, no resource APIs, both image
// formats, and the payload counts as found only when it sits inside the
// mounted image. AStatus tells "no section" from "a section this reader cannot
// use", so the caller can say which one it is.
function STSectionMapTextEx(AModule: THandle; out AStatus: TSTMapStatus): string;
var
  ImageSize: NativeUInt;
  DosHeader: PImageDosHeader;
  Nt32: PImageNtHeaders32;
  Nt64: PImageNtHeaders64;
  SecCount, OptSize, I: Integer;
  Sections: PImageSectionHeader;
  Sec: PImageSectionHeader;
  Match: Boolean;
  K, DataSize, HeaderLen: Integer;
  Data: PByte;
  Bytes: TBytes;
begin
  Result := '';
  AStatus := msAbsent;
  if AModule = 0 then
    Exit;
  DosHeader := PImageDosHeader(NativeUInt(AModule));
  if DosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    Exit;
  Nt32 := PImageNtHeaders32(NativeUInt(AModule) + NativeUInt(DosHeader^._lfanew));
  if Nt32^.Signature <> IMAGE_NT_SIGNATURE then
    Exit;
  case Nt32^.OptionalHeader.Magic of
    IMAGE_NT_OPTIONAL_HDR32_MAGIC:
      ImageSize := Nt32^.OptionalHeader.SizeOfImage;
    IMAGE_NT_OPTIONAL_HDR64_MAGIC:
      begin
        Nt64 := PImageNtHeaders64(NativeUInt(AModule) + NativeUInt(DosHeader^._lfanew));
        ImageSize := Nt64^.OptionalHeader.SizeOfImage;
      end;
  else
    Exit;
  end;
  SecCount := Nt32^.FileHeader.NumberOfSections;
  OptSize := Nt32^.FileHeader.SizeOfOptionalHeader;
  if (SecCount < 1) or (SecCount > 96) or (OptSize = 0) then
    Exit;
  Sections := PImageSectionHeader(NativeUInt(@(Nt32^.OptionalHeader)) +
    NativeUInt(OptSize));
  HeaderLen := SizeOf(TEWMapHeader);
  for I := 0 to SecCount - 1 do
  begin
    Sec := PImageSectionHeader(NativeUInt(Sections) +
      NativeUInt(I) * NativeUInt(SizeOf(TImageSectionHeader)));
    // Exact 8-byte field compare: '.ewmap' followed by zero padding. The
    // shipped Name field is a Byte array, so compare through Ord.
    Match := True;
    for K := 0 to 7 do
    begin
      if K < Length(EW_MAP_SECTION_NAME) then
      begin
        if Sec.Name[K] <> Ord(EW_MAP_SECTION_NAME[K + 1]) then
        begin
          Match := False;
          Break;
        end;
      end
      else if Sec.Name[K] <> 0 then
      begin
        Match := False;
        Break;
      end;
    end;
    if not Match then
      Continue;
    // From here the section exists: whatever stops us is "cannot use it".
    AStatus := msCorrupt;
    // The payload must sit inside the mounted image, or not at all.
    if (Sec.SizeOfRawData <= NativeUInt(HeaderLen)) or
       ((ImageSize > 0) and
        (NativeUInt(Sec.VirtualAddress) + Sec.SizeOfRawData > ImageSize)) then
      Exit;
    // VirtualSize is exactly header + stored map: the length written back.
    DataSize := Integer(Sec.Misc.VirtualSize);
    if (DataSize <= HeaderLen) or (DataSize > Integer(Sec.SizeOfRawData)) then
      Exit;
    Data := PByte(NativeUInt(AModule) + NativeUInt(Sec.VirtualAddress));
    AStatus := STDecodeMapPayload(Data, DataSize, Bytes);
    if AStatus = msOk then
      Result := TEncoding.Default.GetString(Bytes);
    Exit;
  end;
end;

function STSectionMapText(AModule: THandle): string;
var
  Status: TSTMapStatus;
begin
  Result := STSectionMapTextEx(AModule, Status);
end;

// Symbol text a module carries with it: the embedded map first - the .ewmap
// section the injectors append, then the RCDATA resource older tooling still
// links - then the plain .map file beside the module (development builds).
function STSymbolTextForModule(AModule: THandle; out ASource: string): string;
var
  ResInfo: HRSRC;
  ResLoad: HGLOBAL;
  ResPtr: Pointer;
  ResSize: Integer;
  MapFile: string;
  Bytes: TBytes;
  SecStatus: TSTMapStatus;
begin
  Result := '';
  ASource := 'none';
  if AModule = 0 then
    Exit;
  // Form 1: the .ewmap section the build-time injectors append.
  Result := STSectionMapTextEx(AModule, SecStatus);
  if Result <> '' then
  begin
    ASource := 'embedded';
    Exit;
  end;
  // Form 2: the RCDATA resource, for maps linked by other tooling.
  ResInfo := FindResource(AModule, EW_MAP_RESOURCE_NAME, RT_RCDATA);
  if ResInfo <> 0 then
  begin
    ResLoad := LoadResource(AModule, ResInfo);
    ResSize := SizeOfResource(AModule, ResInfo);
    if (ResLoad <> 0) and (ResSize > 0) then
    begin
      ResPtr := LockResource(ResLoad);
      if ResPtr <> nil then
      begin
        SetLength(Bytes, ResSize);
        Move(ResPtr^, Bytes[0], ResSize);
        Result := TEncoding.Default.GetString(Bytes);
      end;
    end;
  end;
  if Result <> '' then
  begin
    ASource := 'embedded';
    Exit;
  end;
  MapFile := ChangeFileExt(GetModuleName(AModule), '.map');
  if FileExists(MapFile) then
  begin
    try
      // A plain file read: this is the only disk access in the whole
      // resolution path, and it happens once per module, at first use.
      Result := TFile.ReadAllText(MapFile);
    except
      // An unreadable map must not turn a missing trace into a crash.
      Result := '';
    end;
    if Result <> '' then
      ASource := 'map_file';
  end;
  // A section that is there but unreadable is not "no map": say which, so a
  // trace without symbols is explained by its own event.
  if (Result = '') and (ASource = 'none') then
    case SecStatus of
      msUnsupported: ASource := EW_SRC_UNSUPPORTED;
      msCorrupt: ASource := EW_SRC_CORRUPT;
    end;
end;

// A cached entry answers for the module mounted at that address NOW: module
// handles are load addresses and get recycled after a FreeLibrary, so a hit
// whose image size no longer matches the mounted image is stale and gets
// rebuilt. A SizeOfImage of 0 (seeded tables) accepts anything.
function STEntryUsable(AEntry: TSTModuleSymbols; const AInfo: TSTModuleInfo): Boolean;
begin
  Result := (AEntry <> nil) and (not AEntry.Building) and
    ((AEntry.SizeOfImage = 0) or (AInfo.SizeOfImage = 0) or
     (AEntry.SizeOfImage = AInfo.SizeOfImage));
end;

// Loads (or takes from cache) the symbol table for a module. The BUILD runs
// outside every lock: it is once-per-module work of up to seconds (12 MB of
// map text is split and sorted), and the callers sit inside the raise path -
// one thread must never park other threads' exceptions behind it. A
// placeholder entry claims the build per module; a thread that hits the
// placeholder gives up its trace this once, exactly like the init path
// always has.
function STSymbolsForModule(const AInfo: TSTModuleInfo): TSTModuleSymbols;
var
  Text: string;
{$IFDEF EXEWATCH_TESTING}
  CountThisBuild: Boolean;
{$ENDIF}
begin
  Result := nil;
  if (AInfo.Module = 0) or (GSTModuleSymbols = nil) then
    Exit;
  GSTModuleSymbolsLock.Acquire;
  try
    if GSTModuleSymbols.TryGetValue(AInfo.Module, Result) then
    begin
      if Result.Building then
        Exit;  // a build is in flight: give up, fall back to exports/offset
      if STEntryUsable(Result, AInfo) then
        Exit;
      // Stale: leave the old object to whoever is already holding a pointer
      // to it and replace the cache entry with a fresh build.
      Result := nil;
    end;
    Result := TSTModuleSymbols.Create;
    Result.Module := AInfo.Module;
    Result.Base := AInfo.Base;
    Result.SizeOfImage := AInfo.SizeOfImage;
    Result.Building := True;
    GSTModuleSymbols.AddOrSetValue(AInfo.Module, Result);
  finally
    GSTModuleSymbolsLock.Release;
  end;
{$IFDEF EXEWATCH_TESTING}
  // Only the host module counts: every thread's stack also holds frames of
  // ntdll and kernel32, and two threads building DIFFERENT modules at once is
  // fine. The claim above is per module, so what must never happen is two
  // builds of the same one - and every test thread resolves the host.
  CountThisBuild := AInfo.Module = GSTHostInfo.Module;
  if CountThisBuild and (TInterlocked.Increment(GSTLoadInFlight) > GSTLoadInFlightMax) then
    GSTLoadInFlightMax := GSTLoadInFlight;
  try
{$ENDIF}
  // The build itself: no locks held.
  Text := STSymbolTextForModule(AInfo.Module, Result.Source);
  if Text <> '' then
  begin
    Result.ProgramName := ChangeFileExt(ExtractFileName(AInfo.ModuleName), '');
    try
      STBuildSymbols(Text, Result);
    except
      // A map this parser cannot read must not leave the entry "building" for
      // ever: the module answers from its exports instead, and says so.
      Result.Loaded := False;
      Result.Source := 'none';
    end;
  end;
  Result.Building := False;
  GSTModuleSymbolsLock.Acquire;
  try
    GSTModuleSymbols.AddOrSetValue(AInfo.Module, Result);
  finally
    GSTModuleSymbolsLock.Release;
  end;
{$IFDEF EXEWATCH_TESTING}
  finally
    if CountThisBuild then
      TInterlocked.Decrement(GSTLoadInFlight);
  end;
{$ENDIF}
end;

// Parses the export directory of a module straight out of its mapped image:
// no file access, only header math. Every structure is checked for extent
// (start + span within the image) before any element is read, and export
// names are copied with a scan bounded at the image end - a module the
// loader never imports from can carry a malformed directory and nothing here
// is allowed to fault into the raise path.
function STBuildExportTable(const AInfo: TSTModuleInfo): TSTExportTable;
var
  DosHeader: PImageDosHeader;
  Nt32: PImageNtHeaders32;
  Nt64: PImageNtHeaders64;
  ExpRVA: DWORD;
  Dir: PImageExportDirectory;
  Names: PSTCardinalArray;
  Ordinals: PSTWordArray;
  Functions: PSTCardinalArray;
  I, Count: Integer;
  NameRVA, FuncRVA: DWORD;
  InImage: PByte;
  NulFound: Boolean;
begin
  SetLength(Result, 0);
  if (AInfo.Module = 0) or (AInfo.Base = 0) or (AInfo.SizeOfImage = 0) then
    Exit;
  DosHeader := PImageDosHeader(AInfo.Base);
  if DosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    Exit;
  Nt32 := PImageNtHeaders32(AInfo.Base + NativeUInt(DosHeader^._lfanew));
  if Nt32^.Signature <> IMAGE_NT_SIGNATURE then
    Exit;
  case Nt32^.OptionalHeader.Magic of
    IMAGE_NT_OPTIONAL_HDR32_MAGIC:
      ExpRVA := Nt32^.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
    IMAGE_NT_OPTIONAL_HDR64_MAGIC:
      begin
        Nt64 := PImageNtHeaders64(AInfo.Base + NativeUInt(DosHeader^._lfanew));
        ExpRVA := Nt64^.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
      end;
  else
    Exit;
  end;
  // The whole directory, not just its start address, has to sit in image.
  if ExpRVA + SizeOf(TImageExportDirectory) > AInfo.SizeOfImage then
    Exit;
  Dir := PImageExportDirectory(AInfo.Base + ExpRVA);
  if (Dir^.NumberOfNames = 0) then
    Exit;
  // Span checks: array start + per-element span within the image, and the
  // functions array bounded by its own declared size.
  if (Dir^.AddressOfNames + 4 * Dir^.NumberOfNames >= AInfo.SizeOfImage) or
     (Dir^.AddressOfNameOrdinals + 2 * Dir^.NumberOfNames >= AInfo.SizeOfImage) or
     (Dir^.NumberOfFunctions > AInfo.SizeOfImage div 4) or
     (Dir^.AddressOfFunctions + 4 * Dir^.NumberOfFunctions >= AInfo.SizeOfImage) then
    Exit;
  Names := Pointer(AInfo.Base + Dir^.AddressOfNames);
  Ordinals := Pointer(AInfo.Base + Dir^.AddressOfNameOrdinals);
  Functions := Pointer(AInfo.Base + Dir^.AddressOfFunctions);
  SetLength(Result, Dir^.NumberOfNames);
  Count := 0;
  for I := 0 to Dir^.NumberOfNames - 1 do
  begin
    NameRVA := Names^[I];
    if NameRVA >= AInfo.SizeOfImage then
      Continue;
    if Cardinal(Ordinals^[I]) >= Dir^.NumberOfFunctions then
      Continue;
    FuncRVA := Functions^[Ordinals^[I]];
    if FuncRVA >= AInfo.SizeOfImage then
      Continue;
    // Name strings are copied with a bounded scan: a name without a NUL
    // terminator before the image end is skipped, not chased into memory
    // outside the module.
    NulFound := False;
    InImage := Pointer(AInfo.Base + NameRVA);
    while NativeUInt(InImage) < AInfo.Base + AInfo.SizeOfImage do
    begin
      if InImage^ = 0 then
      begin
        NulFound := True;
        Break;
      end;
      Inc(InImage);
    end;
    if not NulFound then
      Continue;
    Result[Count].RVA := FuncRVA;
    Result[Count].Name := string(PAnsiChar(AInfo.Base + NameRVA));
    Inc(Count);
  end;
  SetLength(Result, Count);
  if Length(Result) > 1 then
    TArray.Sort<TSTExportEntry>(Result, TComparer<TSTExportEntry>.Construct(
      function(const A, B: TSTExportEntry): Integer
      begin
        if A.RVA < B.RVA then Result := -1
        else if A.RVA > B.RVA then Result := 1
        else Result := 0;
      end));
end;

// Format 'module.dll!Name' (or with +0xOffset) for the exported function the
// address falls in or after. Empty when the module has no usable exports.
function STExportNameForAddress(const AInfo: TSTModuleInfo; AAddress: NativeUInt): string;
var
  Cache: TSTExportCache;
  Table: TSTExportTable;
  Lo, Hi, Mid, Found: Integer;
  RelAddr: NativeUInt;
begin
  Result := '';
  if (AInfo.Module = 0) or (GSTExportTables = nil) then
    Exit;
  GSTModuleSymbolsLock.Acquire;
  try
    Cache := nil;
    if GSTExportTables.TryGetValue(AInfo.Module, Cache) then
    begin
      // Handles are recycled: a cached table must still describe the image
      // mounted now (same trick as the symbol tables).
      if (Cache.Base <> AInfo.Base) or
         ((AInfo.SizeOfImage <> 0) and (Cache.SizeOfImage <> AInfo.SizeOfImage)) then
      begin
        Cache := nil;
        GSTExportTables.Remove(AInfo.Module);
      end;
    end;
    if Cache = nil then
    begin
      Cache := TSTExportCache.Create;
      Cache.Base := AInfo.Base;
      Cache.SizeOfImage := AInfo.SizeOfImage;
      Cache.Table := STBuildExportTable(AInfo);
      GSTExportTables.AddOrSetValue(AInfo.Module, Cache);
    end;
    Table := Cache.Table;
  finally
    GSTModuleSymbolsLock.Release;
  end;
  if (Length(Table) = 0) or (AAddress < AInfo.Base) or
     (AAddress - AInfo.Base >= AInfo.SizeOfImage) then
    Exit;
  RelAddr := AAddress - AInfo.Base;
  Lo := 0;
  Hi := High(Table);
  Found := -1;
  while Lo <= Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if Table[Mid].RVA <= RelAddr then
    begin
      Found := Mid;
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
  if Found < 0 then
    Exit;
  if Table[Found].RVA = RelAddr then
    Result := Format('%s!%s', [AInfo.ModuleName, Table[Found].Name])
  else
    Result := Format('%s!%s+0x%x', [AInfo.ModuleName, Table[Found].Name, RelAddr - Table[Found].RVA]);
end;

{$IFDEF CPUX86}
// Inspects the bytes before a return address and returns the size of the
// CALL that produced it (0 = nothing that looks like a call): the classic
// x86 call encodings only, which is what the frame walk runs on. x64 is
// intentionally left out: the REX prefix heuristics are a different game and
// nothing here is verified for it.
function STCallSiteSize(AReturnAddress: NativeUInt): Cardinal;
var
  CodeDWORD4, CodeDWORD8: DWORD;
  RM1, RM2, RM5: Byte;
begin
  Result := 0;
  if AReturnAddress <= 8 then
    Exit;
  CodeDWORD8 := PDWORD(AReturnAddress - 8)^;
  CodeDWORD4 := PDWORD(AReturnAddress - 4)^;
  // CodeDWORD8 = bytes (ReturnAddr-8..ReturnAddr-5), CodeDWORD4 = (ReturnAddr-4..ReturnAddr-1)
  RM1 := (CodeDWORD4 shr 24) and $7;
  RM2 := (CodeDWORD4 shr 16) and $7;
  RM5 := (CodeDWORD8 shr 24) and $7;
  // The most common CALL variants first
  if ((CodeDWORD8 and $FF000000) = $E8000000) then
    // 5 bytes, "CALL NEAR REL32" (E8 cd)
    Result := 5
  else if ((CodeDWORD4 and $F8FF0000) = $10FF0000) and not (RM1 in [4, 5]) then
    // 2 bytes, "CALL NEAR [EAX]" (FF /2) - R/M neither SIB nor disp32
    Result := 2
  else if ((CodeDWORD4 and $F8FF0000) = $D0FF0000) then
    // 2 bytes, "CALL NEAR EAX" (FF /2, Mod=11)
    Result := 2
  else if ((CodeDWORD4 and $00FFFF00) = $0014FF00) then
    // 3 bytes, "CALL NEAR [EAX+EAX*i]" (FF /2, Mod=00, RM=100, SIB not validated)
    Result := 3
  else if ((CodeDWORD4 and $00F8FF00) = $0050FF00) and (RM2 <> 4) then
    // 3 bytes, "CALL NEAR [EAX+$12]" (FF /2, Mod=01, R/M not SIB)
    Result := 3
  else if ((CodeDWORD4 and $0000FFFF) = $000054FF) then
    // 4 bytes, "CALL NEAR [EAX+EAX+$12]" (FF /2, Mod=01, RM=100)
    Result := 4
  else if ((CodeDWORD8 and $FFFF0000) = $15FF0000) then
    // 6 bytes, "CALL NEAR [imm32]" (FF /2, Mod=00, RM=101)
    Result := 6
  else if ((CodeDWORD8 and $F8FF0000) = $90FF0000) and (RM5 <> 4) then
    // 6 bytes, "CALL NEAR [EAX+imm32]" (FF /2, Mod=10, R/M not SIB)
    Result := 6
  else if ((CodeDWORD8 and $00FFFF00) = $0094FF00) then
    // 7 bytes, "CALL NEAR [EAX+EAX*i+imm32]" (FF /2, Mod=10, RM=100)
    Result := 7
  else if ((CodeDWORD8 and $0000FF00) = $00009A00) then
    // 7 bytes, "CALL FAR $1234:$12345678" (9A ptr16:32) - valid only on x86
    Result := 7
  else
    Result := 0;
end;
{$ENDIF CPUX86}

// Any resolution failure is contained here: the raise path and the direct
// Log calls below must receive a line, never an exception of their own.
function STResolveAddrInner(Address: NativeUInt): string; forward;

// The name (and line) the map gives an address; '' = the map says nothing.
// A line entry only speaks for the function it starts in: the last unit's
// line table ends where its code ends, and code after it (units built without
// line info) is within the lookup's slack. Taking the nearest earlier line
// would put those frames on the last line of the program, with no name.
function STDescribeAddress(Syms: TSTModuleSymbols; Address: NativeUInt): string;
var
  SymName, LineUnit, FuncName: string;
  LineNum: Integer;
  SymStart, LineStart: NativeUInt;
begin
  Result := '';
  SymName := Syms.FindSymbolAt(Address, SymStart);
  Syms.FindLine(Address, LineNum, LineUnit, LineStart);
  if (LineNum > 0) and (SymName <> '') and (LineStart < SymStart) then
  begin
    LineNum := 0;
    LineUnit := '';
  end;
  if (LineUnit <> '') and (SymName <> '') and SymName.StartsWith(LineUnit + '.') then
  begin
    FuncName := Copy(SymName, Length(LineUnit) + 2, MaxInt);
    // Win32 Finalization fix
    if (Syms.ProgramName <> '') and
       SameText(LineUnit, Syms.ProgramName) and
       SameText(FuncName, 'Finalization') then
      FuncName := Syms.ProgramName;
    if LineNum > 0 then
      Result := Format('%s.%s (line %d)', [LineUnit, FuncName, LineNum])
    else
      Result := Format('%s.%s', [LineUnit, FuncName]);
  end
  else if (LineUnit <> '') and (LineNum > 0) then
    Result := Format('%s (line %d)', [LineUnit, LineNum])
  else if SymName <> '' then
    Result := SymName;
end;

function STResolveAddr(Address: NativeUInt): string;
var
  Info: TSTModuleInfo;
begin
  try
    Result := STResolveAddrInner(Address);
  except
    Info := STModuleInfoForAddress(Address);
    if Info.Module = 0 then
      Result := Format('[%p]', [Pointer(Address)])
    else
      Result := Format('%s+0x%x', [Info.ModuleName, Address - Info.Base]);
  end;
end;

// Does the real work of STResolveAddr; the wrapper above is the containment.
function STResolveAddrInner(Address: NativeUInt): string;
var
  Info: TSTModuleInfo;
  Syms: TSTModuleSymbols;
begin
  Info := STModuleInfoForAddress(Address);
  if Info.Module = 0 then
    Result := Format('[%p]', [Pointer(Address)])
  else
  begin
    Syms := STSymbolsForModule(Info);
    if Syms = nil then
      Exit(Format('[%p]', [Pointer(Address)]));
    Result := '';
    if Syms.Loaded and (Address >= Syms.Base) and
       ((Syms.SizeOfImage = 0) or (Address - Syms.Base < Syms.SizeOfImage)) then
      Result := STDescribeAddress(Syms, Address);
    if Result = '' then
    begin
      // No map symbols for this module: the PE export table is the next best
      // hint, and after that a plain module-relative offset.
      Result := STExportNameForAddress(Info, Address);
      if Result = '' then
        Result := Format('%s+0x%x', [Info.ModuleName, Address - Info.Base]);
    end;
  end;
end;

procedure STInitCapture;
var
  H: THandle;
begin
  H := GetModuleHandle('kernel32.dll');
  if H <> 0 then
    @GSTCapture := GetProcAddress(H, 'RtlCaptureStackBackTrace');
end;

{$IFDEF CPUX86}
type
  // The classic FPO-free stack frame: saved EBP, then return address.
  TSTStackFrame = record
    CallerFrame: NativeUInt;
    CallerAddr: NativeUInt;
  end;
  PSTStackFrame = ^TSTStackFrame;

function STCaptureFrames(AFrames: PPointerArray; AMax: Integer): Integer; forward;

// No stack frames are generated for a pure asm routine, so EBP read here is
// the frame of the function that called us - the chain head of the walk.
{$STACKFRAMES OFF}
function STGetFramePointer: Pointer;
asm
  MOV EAX, EBP
end;

// Thread stack bounds from the TIB: StackBase at FS:[4], StackLimit at FS:[8].
function STGetStackBase: Pointer;
asm
  MOV EAX, FS:[4]
end;

function STGetStackLimit: Pointer;
asm
  MOV EAX, FS:[8]
end;
{$STACKFRAMES ON}

// Walks the EBP chain ascending: on Win32 RtlCaptureStackBackTrace has no
// unwind tables to lean on at raise time, so the frame chain is walked by
// hand. Every recorded return address must sit inside a loaded module;
// frames that fail are skipped while the walk continues. A caller frame
// outside the thread stack or not strictly ascending stops the walk: a
// shorter trace beats a made-up one.
function STCaptureFrames(AFrames: PPointerArray; AMax: Integer): Integer;
var
  Frame: PSTStackFrame;
  StackBase, StackLimit, PrevFrame, CallerFrame, CallerAddr: NativeUInt;
begin
  Result := 0;
  if (AFrames = nil) or (AMax <= 0) then
    Exit;
  StackBase := NativeUInt(STGetStackBase);
  StackLimit := NativeUInt(STGetStackLimit);
  if StackBase <= StackLimit then
    Exit;
  Frame := PSTStackFrame(STGetFramePointer);
  PrevFrame := NativeUInt(Frame);
  while Result < AMax do
  begin
    // Frame inside the thread stack, with room for both fields, before any
    // dereference.
    if (NativeUInt(Frame) < StackLimit) or
       (NativeUInt(Frame) + SizeOf(TSTStackFrame) > StackBase) then
      Break;
    CallerFrame := Frame^.CallerFrame;
    // Ascending chain, still inside the stack.
    if (CallerFrame <= PrevFrame) or
       (CallerFrame < StackLimit) or
       (CallerFrame + SizeOf(TSTStackFrame) > StackBase) then
      Break;
    CallerAddr := Frame^.CallerAddr;
    // Module membership FIRST: the call-site probe reads eight bytes before
    // the address, and only a mapped module guarantees mapped memory there.
    if STModuleInfoForAddress(CallerAddr).Module <> 0 then
    begin
      // Points the address at the CALL, not at the instruction after it, so
      // the line numbers land on the caller's call line.
      if STCallSiteSize(CallerAddr) > 0 then
        Dec(CallerAddr, STCallSiteSize(CallerAddr));
      AFrames[Result] := Pointer(CallerAddr);
      Inc(Result);
    end;
    PrevFrame := CallerFrame;
    Frame := PSTStackFrame(CallerFrame);
  end;
end;
{$ENDIF CPUX86}

// One thread builds the state; any other thread arriving while it is being
// built gives up its trace rather than read a half-initialized structure: a
// missing trace beats a torn read. Returns True once the state is complete
// and safe to consult.
function STEnsureInit: Boolean;
begin
  Result := GSTInitState = ST_INIT_READY;
  if Result then
    Exit;
{$IFDEF EXEWATCH_TESTING}
  if GSTTestYieldBeforeClaim then
    Sleep(1);
{$ENDIF}
  // Whoever wins this claims the init; everyone else leaves empty-handed.
  if TInterlocked.CompareExchange(GSTInitState, ST_INIT_LOADING, ST_INIT_IDLE) <> ST_INIT_IDLE then
    Exit;
  try
    STInitCapture;
    GSTModuleSymbolsLock := TCriticalSection.Create;
    GSTModuleSymbols := TDictionary<THandle, TSTModuleSymbols>.Create;
    GSTExportTables := TDictionary<THandle, TSTExportCache>.Create;
    // A C++Builder executable does not set HInstance (it stays 0): the host
    // is then the process's own image.
    if HInstance <> 0 then
      GSTHostInfo := STModuleInfoForAddress(NativeUInt(HInstance))
    else
      GSTHostInfo := STModuleInfoForAddress(NativeUInt(GetModuleHandle(nil)));
    // Published last: a thread that sees ST_INIT_READY sees complete state.
    GSTInitState := ST_INIT_READY;
  finally
    // A half-built init must not be published as ready and must not stick
    // as loading either: the next raise retries.
    if GSTInitState <> ST_INIT_READY then
      TInterlocked.Exchange(GSTInitState, ST_INIT_IDLE);
  end;
  Result := True;
end;

function IsRTLInternalFrame(const ALine: string): Boolean;
begin
  Result :=
    // RTL / OS internals
    (Pos('$unwind$', ALine) > 0) or
    (Pos('$pdata$', ALine) > 0) or
    (Pos('_RaiseExcept', ALine) > 0) or
    (Pos('.RaiseExcept', ALine) > 0) or
    (Pos('RaisingException', ALine) > 0) or
    (Pos('RtlRaiseException', ALine) > 0) or
    (Pos('RtlDispatchException', ALine) > 0) or
    (Pos('NtRaiseException', ALine) > 0) or
    (Pos('KiUserException', ALine) > 0) or
    (Pos('RaiseException', ALine) > 0) or
    (Pos('NotifyExceptFinally', ALine) > 0) or
    (Pos('@RaiseExcept', ALine) > 0) or
    (Pos('RaiseAtExcept', ALine) > 0) or
    (Pos('InternalRaiseAtExcept', ALine) > 0) or
    (Pos('@HandleFinally', ALine) > 0) or
    (Pos('@HandleAnyException', ALine) > 0) or
    (Pos('@HandleOnException', ALine) > 0) or
    // ExeWatch SDK internals. The unit-name prefix filters EVERY frame the
    // SDK itself raised through: hook procs sit next to the walk machinery
    // and a source edit shifts their addresses, so a hand-list of proc names
    // drifts out of date with each change (an SDK frame resolved to a
    // neighbour hook and surfaced in user traces). User code can never
    // legitimately resolve into this unit: the SDK lives only inside it.
    (Pos('ExeWatchSDKv1.', ALine) > 0) or
    (Pos('ExeWatchGetExceptionStackInfo', ALine) > 0) or
    (Pos('ScanStackForTrace', ALine) > 0) or
    (Pos('GetStackTraceStr', ALine) > 0) or
    (Pos('GetExceptionTraceStr', ALine) > 0) or
    (Pos('GetLastExceptionStackTrace', ALine) > 0) or
    (Pos('STEnsureInit', ALine) > 0) or
    (Pos('STResolveAddr', ALine) > 0);
end;

function GetStackTraceStr(FramesToSkip: Integer = 0): string;
var
  Frames: array[0..ST_MAX_FRAMES - 1] of Pointer;
  Count, I, Start: Integer;
  SB: TStringBuilder;
  S: string;
begin
  Result := '';
  // Not ready means another thread is still building the table; reading it now
  // is a torn read, so this frame simply goes without a trace.
  if not STEnsureInit then
    Exit;
  FillChar(Frames, SizeOf(Frames), 0);
{$IFDEF CPUX64}
  if not Assigned(GSTCapture) then Exit;
  Count := GSTCapture(FramesToSkip + 1, ST_MAX_FRAMES, @Frames[0], nil);
  Start := 0;
{$ENDIF}
{$IFDEF CPUX86}
  // x86 has no unwind tables: capture the whole chain with the frame walk
  // and apply here the same first-kept offset the Win64 API gives us.
  Count := STCaptureFrames(@Frames[0], ST_MAX_FRAMES);
  Start := FramesToSkip + 1;
{$ENDIF}
  if (Count = 0) or (Start >= Count) then
    Exit;
  SB := TStringBuilder.Create;
  try
    for I := Start to Count - 1 do
    begin
      if Frames[I] = nil then Continue;
      S := STResolveAddr(NativeUInt(Frames[I]));
      if IsRTLInternalFrame(S) then Continue;
      if SB.Length > 0 then SB.AppendLine;
      SB.Append(S);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// The reason answers for the HOST module - not for the last frame the trace
// happened to resolve: an error whose deepest frame sits in kernel32 must
// not be reported as "no symbols". A trace only reaches the reason field
// when it came out empty, so reason 3 means "the capture produced nothing";
// reason 2 now means "the host module carries no symbols at all" (resource
// and .map file both), reason 1 stays the unavailable capture mechanism.
// Body per architecture: this section lives under neither ifdef.
{$IFDEF CPUX86}
function GetNoStackTraceReason: Integer;
begin
  if (GSTHostInfo.Module = 0) or
     not STEntryUsable(STSymbolsForModule(GSTHostInfo), GSTHostInfo) or
     not STSymbolsForModule(GSTHostInfo).Loaded then
    Result := 2  // the host module has no usable symbol table
  else
    Result := 3; // capture returned 0 frames
end;
{$ENDIF CPUX86}
{$IFDEF CPUX64}
function GetNoStackTraceReason: Integer;
begin
  if not Assigned(GSTCapture) then
    Result := 1  // RtlCaptureStackBackTrace not available
  else if (GSTHostInfo.Module = 0) or
          not STEntryUsable(STSymbolsForModule(GSTHostInfo), GSTHostInfo) or
          not STSymbolsForModule(GSTHostInfo).Loaded then
    Result := 2  // the host module has no usable symbol table
  else
    Result := 3; // capture returned 0 frames
end;
{$ENDIF CPUX64}

// Like the reason above, it answers for the HOST module: that is the one
// whose symbols decide whether a trace reads on another machine.
function GetSymbolSource: string;
var
  Symbols: TSTModuleSymbols;
begin
  Result := 'none';
  if GSTHostInfo.Module = 0 then
    Exit;
  Symbols := STSymbolsForModule(GSTHostInfo);
  if Symbols = nil then
    Exit;
  if Symbols.Loaded and (Symbols.Source <> '') then
    Result := Symbols.Source
  // No usable symbols, but the exe does carry a map: say why, not just 'none'.
  else if (Symbols.Source = EW_SRC_UNSUPPORTED) or
          (Symbols.Source = EW_SRC_CORRUPT) then
    Result := Symbols.Source;
end;

{$ELSE}

// Non-Windows stubs
function GetStackTraceStr(FramesToSkip: Integer = 0): string;
begin
  Result := '';
end;

function GetSymbolSource: string;
begin
  Result := '';
end;

function GetNoStackTraceReason: Integer;
begin
  Result := 4; // Platform not supported (non-Windows)
end;

{$ENDIF}

procedure AttachSymbolSource(AExtraData: TJSONObject);
var
  Trace: TJSONValue;
  Source: string;
begin
  if AExtraData = nil then
    Exit;
  Trace := AExtraData.GetValue('stack_trace');
  if (Trace = nil) or (Trace.Value = '') or
     (AExtraData.GetValue('symbol_source') <> nil) then
    Exit;
  Source := GetSymbolSource;
  if Source <> '' then
    AExtraData.AddPair('symbol_source', Source);
end;

function GetLastExceptionStackTrace(E: Exception): string;
{$IFDEF MSWINDOWS}
var
  Ours: PEWStackInfo;
{$ENDIF}
begin
  Result := '';
{$IFDEF MSWINDOWS}
  if E = nil then
    Exit;
  Ours := EWStackInfoOf(E.StackInfo);
  if Ours <> nil then
    Result := Ours^.Trace;
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
// Trace for the exception hook. On Win32 the frame chain jumps from the
// exception machinery straight past the raising function - the raiser's own
// frame is consumed on the RTL raise path - so the raiser's address, taken
// from the exception record (the raise statement), is prepended first. On
// Win64 the API capture already starts at the raise, so the ordinary capture
// is reused unchanged.
{$IFDEF CPUX86}
function GetExceptionTraceStr(AExceptAddr: Pointer): string;
var
  Frames: array[0..ST_MAX_FRAMES - 1] of Pointer;
  Count, I: Integer;
  SB: TStringBuilder;
  S: string;
begin
  Result := '';
  if not STEnsureInit then
    Exit;
  FillChar(Frames, SizeOf(Frames), 0);
  // The raiser enters first, taken from the exception record itself.
  Frames[0] := AExceptAddr;
  if AExceptAddr = nil then
    Count := STCaptureFrames(@Frames[0], ST_MAX_FRAMES)
  else
    Count := 1 + STCaptureFrames(@Frames[1], ST_MAX_FRAMES - 1);
  if Count = 0 then
    Exit;
  SB := TStringBuilder.Create;
  try
    for I := 0 to Count - 1 do
    begin
      if Frames[I] = nil then Continue;
      S := STResolveAddr(NativeUInt(Frames[I]));
      if IsRTLInternalFrame(S) then Continue;
      if SB.Length > 0 then SB.AppendLine;
      SB.Append(S);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDIF CPUX86}
{$IFDEF CPUX64}
function GetExceptionTraceStr(AExceptAddr: Pointer): string;
begin
  Result := GetStackTraceStr(0);
end;
{$ENDIF CPUX64}
{$ENDIF MSWINDOWS}

// Gives the RTL hooks back only if they are still ours. Units finalize in
// reverse initialization order, so anything listed before ExeWatch in the .dpr
// finalizes AFTER it: an unconditional restore tears out a handler that another
// unit installed on top of us, and does it exactly while a crash reporter should
// still be working.
//
// Extracted from the finalization so the suite can drive it. The finalization
// itself runs at process exit, after the last test has reported, so the only way
// to test this line is to have it somewhere else.
procedure ExeWatchRestoreRtlHooks;
begin
  if System.ExceptProc = @ExeWatchExceptProc then
    System.ExceptProc := @GOldExceptProc;
{$IFDEF MSWINDOWS}
  if @Exception.GetExceptionStackInfoProc = @ExeWatchGetExceptionStackInfo then
    Exception.GetExceptionStackInfoProc := GOldGetExceptionStackInfoProc;
  if @Exception.GetStackInfoStringProc = @ExeWatchGetStackInfoString then
    Exception.GetStackInfoStringProc := GOldGetStackInfoStringProc;
  if @Exception.CleanUpStackInfoProc = @ExeWatchCleanUpStackInfo then
    Exception.CleanUpStackInfoProc := GOldCleanUpStackInfoProc;
{$ENDIF}
end;

{$IFDEF EXEWATCH_TESTING}
function EWGetStackTraceStr(FramesToSkip: Integer = 0): string;
begin
  Result := GetStackTraceStr(FramesToSkip);
end;

{$IFDEF MSWINDOWS}
// Puts the symbol state back to never-initialized so a test can drive the
// very first initialisation, which is the only moment the race exists.
procedure EWTestResetStackTraceInit(AYieldBeforeClaim: Boolean);
var
  Pair: TPair<THandle, TSTModuleSymbols>;
begin
  GSTTestYieldBeforeClaim := AYieldBeforeClaim;
  GSTLoadInFlight := 0;
  GSTLoadInFlightMax := 0;
  // Tests reset only where no resolver is running (the suite resets
  // sequentially): freeing the entries while a resolver holds a pointer
  // would be a use-after-free. The dictionary shells go too, so state is
  // genuinely back to never-initialized and init recreates them.
  if GSTModuleSymbolsLock <> nil then
  begin
    GSTModuleSymbolsLock.Acquire;
    try
      if GSTModuleSymbols <> nil then
        for Pair in GSTModuleSymbols do
          Pair.Value.Free;
      FreeAndNil(GSTExportTables);
    finally
      GSTModuleSymbolsLock.Release;
    end;
  end;
  FreeAndNil(GSTModuleSymbols);
  FreeAndNil(GSTModuleSymbolsLock);
  GSTInitState := ST_INIT_IDLE;
end;

// Highest number of threads ever inside a symbol-table build at once. Above
// 1 means two threads were rebuilding the same module's table.
function EWTestMaxConcurrentMapLoads: Integer;
begin
  Result := GSTLoadInFlightMax;
end;

// Replaces the host module's symbol table with ACount synthetic entries at
// AStep intervals, so a test can probe resolution without needing a real
// executable of that size. Leaves the state published, as a completed init
// would.
procedure EWTestSeedSymbols(ACount: Integer; AStep: NativeUInt; ACodeBase: NativeUInt);
var
  I: Integer;
  Entry, Old: TSTModuleSymbols;
begin
  // A reset before the seed frees the lock and the dictionaries; recreate.
  if GSTModuleSymbolsLock = nil then
    GSTModuleSymbolsLock := TCriticalSection.Create;
  if GSTModuleSymbols = nil then
    GSTModuleSymbols := TDictionary<THandle, TSTModuleSymbols>.Create;
  if GSTExportTables = nil then
    GSTExportTables := TDictionary<THandle, TSTExportCache>.Create;
  Entry := TSTModuleSymbols.Create;
  Entry.Module := HInstance;
  Entry.Base := ACodeBase;
  Entry.Loaded := True;
  for I := 0 to ACount - 1 do
    Entry.AddSymbol(NativeUInt(I) * AStep, 'Seeded.Sym' + IntToStr(I));
  Entry.ShrinkAndSort;
  GSTHostInfo.Module := HInstance;
  GSTHostInfo.Base := ACodeBase;
  GSTModuleSymbolsLock.Acquire;
  try
    if GSTModuleSymbols.TryGetValue(HInstance, Old) then
      Old.Free;
    GSTModuleSymbols.AddOrSetValue(HInstance, Entry);
  finally
    GSTModuleSymbolsLock.Release;
  end;
  GSTInitState := ST_INIT_READY;
end;

function EWTestFindSymbol(AAddress: NativeUInt): string;
var
  Entry: TSTModuleSymbols;
  Start: NativeUInt;
begin
  Result := '';
  GSTModuleSymbolsLock.Acquire;
  try
    if not GSTModuleSymbols.TryGetValue(HInstance, Entry) then
      Exit;
    Result := Entry.FindSymbolAt(AAddress, Start);
  finally
    GSTModuleSymbolsLock.Release;
  end;
end;

function EWTestModuleInfoForAddress(AAddress: NativeUInt): TSTModuleInfo;
begin
  Result := STModuleInfoForAddress(AAddress);
end;

function EWTestResolveAddress(AAddress: NativeUInt): string;
begin
  STEnsureInit;
  Result := STResolveAddr(AAddress);
end;

function EWTestSectionMapText(AModule: THandle): string;
begin
  Result := STSectionMapText(AModule);
end;

function EWTestDecodeMapPayload(AData: PByte; ASize: Integer;
  out ABytes: TBytes): Integer;
begin
  Result := Ord(STDecodeMapPayload(AData, ASize, ABytes));
end;

function EWTestModuleText(AModule: THandle): string;
var
  Source: string;
begin
  STEnsureInit;
  Result := STSymbolTextForModule(AModule, Source);
end;

function EWTestModuleSource(AModule: THandle): string;
begin
  STEnsureInit;
  STSymbolTextForModule(AModule, Result);
end;

function EWTestHostSymbolSource: string;
begin
  STEnsureInit;
  Result := GetSymbolSource;
end;

function EWTestDescribeFromMapText(const AMapText: string; AOffset: NativeUInt): string;
var
  Table: TSTModuleSymbols;
begin
  Table := TSTModuleSymbols.Create;
  try
    STBuildSymbols(AMapText, Table);
    Result := STDescribeAddress(Table, AOffset);
  finally
    Table.Free;
  end;
end;

function EWTestIsConsoleSubsystem(AModule: THandle): Boolean;
begin
  Result := STIsConsoleSubsystem(AModule);
end;

{$IFDEF CPUX86}
function EWTestCallSiteSize(AReturnAddress: NativeUInt): Cardinal;
begin
  Result := STCallSiteSize(AReturnAddress);
end;
{$ENDIF CPUX86}

function STCountMapSymbols(const AText: string): Integer;
var
  SL: TStringList;
  I: Integer;
  BlankCount: Integer;
  InSection: Boolean;
begin
  Result := 0;
  if AText = '' then
    Exit;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    InSection := False;
    BlankCount := 0;
    for I := 0 to SL.Count - 1 do
    begin
      if not InSection then
      begin
        if Pos('Publics by Value', SL[I]) > 0 then
          InSection := True;
        Continue;
      end;
      if Trim(SL[I]) = '' then
      begin
        Inc(BlankCount);
        if BlankCount >= 2 then
          Break;
        Continue;
      end;
      BlankCount := 0;
      // One entry per map row: segment:offset then the symbol name.
      if (SL[I].StartsWith(' ')) and (Pos(':', SL[I]) > 0) and
         (not SL[I].StartsWith('Address')) then
        Inc(Result);
    end;
  finally
    SL.Free;
  end;
end;

function EWTestCountEmbeddedMapSymbols(AModule: THandle): Integer;
var
  ResInfo: HRSRC;
  ResLoad: HGLOBAL;
  ResPtr: Pointer;
  ResSize: Integer;
  Bytes: TBytes;
begin
  Result := 0;
  if AModule = 0 then
    Exit;
  // The .ewmap section first: that is what this project's injectors produce.
  Result := STCountMapSymbols(STSectionMapText(AModule));
  if Result > 0 then
    Exit;
  ResInfo := FindResource(AModule, EW_MAP_RESOURCE_NAME, RT_RCDATA);
  if ResInfo = 0 then
    Exit;
  ResLoad := LoadResource(AModule, ResInfo);
  ResSize := SizeOfResource(AModule, ResInfo);
  if (ResLoad = 0) or (ResSize <= 0) then
    Exit;
  ResPtr := LockResource(ResLoad);
  if ResPtr = nil then
    Exit;
  SetLength(Bytes, ResSize);
  Move(ResPtr^, Bytes[0], ResSize);
  Result := STCountMapSymbols(TEncoding.Default.GetString(Bytes));
end;

// Two stand-ins for the round trip below. Neither is ever called.
procedure EWTestProbeOldExceptProc(ExceptObject: TObject; ExceptAddr: Pointer);
begin
end;

procedure EWTestProbeOtherExceptProc(ExceptObject: TObject; ExceptAddr: Pointer);
begin
end;

function EWTestRtlHookRestoreCheck: string;
var
  RealOld: procedure(ExceptObject: TObject; ExceptAddr: Pointer);
  RealCurrent: Pointer;
  RealGetInfo: function(P: System.PExceptionRecord): Pointer;
  RealGetString: function(Info: Pointer): string;
  RealCleanUp: procedure(Info: Pointer);
begin
  Result := '';
  RealOld := GOldExceptProc;
  RealCurrent := System.ExceptProc;
  // ExeWatchRestoreRtlHooks gives back ALL FOUR hooks, so driving it here
  // unhooks the stack-trace capture that later tests depend on. Everything it
  // can touch is saved, not just the one this check is about.
  RealGetInfo := Exception.GetExceptionStackInfoProc;
  RealGetString := Exception.GetStackInfoStringProc;
  RealCleanUp := Exception.CleanUpStackInfoProc;
  try
    // 1) the hook is still ours, so it must go back to what we found.
    //    If the restore ever became `@@GOldExceptProc`, System.ExceptProc would
    //    hold the ADDRESS OF THE VARIABLE and this comparison would fail - which
    //    is exactly the change a reader of the 2026-08-22 customer report might
    //    make in good faith.
    GOldExceptProc := EWTestProbeOldExceptProc;
    System.ExceptProc := @ExeWatchExceptProc;
    ExeWatchRestoreRtlHooks;
    if System.ExceptProc <> @EWTestProbeOldExceptProc then
      Result := 'the saved handler did not come back; the hook now points elsewhere';

    // 2) somebody installed their own handler after us: leave it alone.
    if Result = '' then
    begin
      System.ExceptProc := @EWTestProbeOtherExceptProc;
      ExeWatchRestoreRtlHooks;
      if System.ExceptProc <> @EWTestProbeOtherExceptProc then
        Result := 'a handler installed after ours was torn out by the restore';
    end;
  finally
    GOldExceptProc := RealOld;
    System.ExceptProc := RealCurrent;
    Exception.GetExceptionStackInfoProc := RealGetInfo;
    Exception.GetStackInfoStringProc := RealGetString;
    Exception.CleanUpStackInfoProc := RealCleanUp;
  end;
end;
{$ENDIF}
{$IFDEF LINUX}
function EWTestReadSysInt(const APath: string; out AValue: Int64): Boolean;
begin
  Result := EWReadSysInt(APath, AValue);
end;
{$ENDIF}
{$ENDIF}

{$IFDEF MSWINDOWS}
// Frees the whole per-module symbol state. Runs from the finalization; no
// trace is expected after that, so the published entries are simply dropped.
procedure STFinalizeState;
var
  Pair: TPair<THandle, TSTModuleSymbols>;
begin
  if GSTModuleSymbolsLock <> nil then
    GSTModuleSymbolsLock.Acquire;
  try
    if GSTModuleSymbols <> nil then
      for Pair in GSTModuleSymbols do
        Pair.Value.Free;
    GSTModuleSymbols.Free;
    GSTModuleSymbols := nil;
    FreeAndNil(GSTExportTables);
  finally
    if GSTModuleSymbolsLock <> nil then
      GSTModuleSymbolsLock.Release;
  end;
  FreeAndNil(GSTModuleSymbolsLock);
end;
{$ENDIF}

initialization
  GExeWatchLock := TCriticalSection.Create;
  GEWVolatileDeviceKey := EWNewVolatileDeviceKey;
  // Install exception handler
  GOldExceptProc := System.ExceptProc;
  System.ExceptProc := @ExeWatchExceptProc;
  // Capture stack at raise time (Win64: table-based unwinding works; Win32
  // walk lands with the per-architecture capture work)
  {$IFDEF MSWINDOWS}
  GOldGetExceptionStackInfoProc := Exception.GetExceptionStackInfoProc;
  GOldGetStackInfoStringProc := Exception.GetStackInfoStringProc;
  GOldCleanUpStackInfoProc := Exception.CleanUpStackInfoProc;
  Exception.GetExceptionStackInfoProc := @ExeWatchGetExceptionStackInfo;
  Exception.GetStackInfoStringProc := @ExeWatchGetStackInfoString;
  Exception.CleanUpStackInfoProc := @ExeWatchCleanUpStackInfo;
  {$ENDIF}

finalization
  ExeWatchRestoreRtlHooks;
  FinalizeExeWatch;
  {$IFDEF MSWINDOWS}
  STFinalizeState;
  {$ENDIF}
  FreeAndNil(GExeWatchLock);

end.
