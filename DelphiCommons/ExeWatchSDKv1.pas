{ *******************************************************************************
  ExeWatch SDK for Delphi

  A lightweight SDK to send logs from Delphi applications to ExeWatch.

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
  EXEWATCH_SDK_VERSION = '0.21.0';
  EXEWATCH_API_VERSION = 'v1';  // API version this SDK targets
  {$IF NOT DEFINED(LOCAL_EXEWATCH)}
  EXEWATCH_ENDPOINT = 'https://exewatch.com';
  {$ELSE}
  EXEWATCH_ENDPOINT = 'http://192.168.1.110:8000';
  {$ENDIF}
  EXEWATCH_DEFAULT_BUFFER_SIZE = 100;
  EXEWATCH_DEFAULT_FLUSH_INTERVAL_MS = 5000;
  EXEWATCH_DEFAULT_RETRY_INTERVAL_MS = 30000;
  EXEWATCH_DEFAULT_SAMPLE_RATE = 1.0;  // 1.0 = 100%, 0.5 = 50%
  EXEWATCH_MAX_BREADCRUMBS = 20;
  EXEWATCH_MAX_PENDING_TIMINGS = 100;
  EXEWATCH_LOG_FILE_EXTENSION = '.ewlog';
  EXEWATCH_DEVICE_FILE_EXTENSION = '.ewdevice';
  EXEWATCH_METRIC_FILE_EXTENSION = '.ewmetric';
  EXEWATCH_SENDING_EXTENSION = '.sending';
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

  THardwareInfo = record
    // Memory
    TotalPhysicalMemory: Int64;
    AvailablePhysicalMemory: Int64;
    // CPU
    CPUName: string;
    CPUCores: Integer;
    CPULogicalProcessors: Integer;
    CPUArchitecture: string;
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
    /// When True, the username portion of DeviceId is replaced with its SHA-1 hash.
    /// e.g., "mario.rossi@PC01" becomes "a1b2c3d4...@PC01".
    /// Useful for GDPR compliance in Active Directory environments.
    /// Requires Delphi 10.2 Tokyo+; ignored on older versions.
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
    procedure DoError(const AMessage: string);
    procedure DoLogsSent(AAccepted, ARejected: Integer);
    procedure DoDeviceInfoSent(ASuccess: Boolean; const AErrorMessage: string);
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
    class function AnonymizeUsername(const AUsername: string): string;
    class function GetDefaultStoragePath: string;
    class function GetTimezoneOffset: string;  // Returns offset like "+01:00" or "-05:00"
    class function GetAppVersionInfo: TAppVersionInfo;  // Auto-reads from current exe
    class function GetCurrentProcessId: Cardinal;
  end;

function ExeWatch: TExeWatch;
function EW: TExeWatch; inline;  // Short alias for ExeWatch
function ExeWatchIsInitialized: Boolean;
function _ExeWatch: TExeWatch; inline;  // Alias to avoid name conflict with unit name
procedure InitializeExeWatch(const AApiKey, ACustomerId: string; AAppVersion: String = ''; AAnonymizeDeviceId: Boolean = False); overload;
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
function GetLastExceptionStackTrace(E: Exception = nil): string;

{$IFDEF EXEWATCH_TESTING}
function EWGetStackTraceStr(FramesToSkip: Integer = 0): string;
{$ENDIF}

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.ShlObj,
  Winapi.WinSock,
  System.Win.Registry,
{$ENDIF}
{$IFDEF LINUX}
  Posix.Base,
  Posix.Unistd,
  Posix.Pwd,
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
  System.StrUtils,
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
  GLastExceptionStackTrace: string; // stack trace captured at raise time (for VCL/FMX hook)
  GExceptionHookNesting: Integer; // prevent re-entry during stack capture


{$IFDEF MSWINDOWS}
var
  GOldGetExceptionStackInfoProc: function(P: System.PExceptionRecord): Pointer = nil;

function ExeWatchGetExceptionStackInfo(P: System.PExceptionRecord): Pointer;
begin
  if Assigned(GOldGetExceptionStackInfoProc) then
    Result := GOldGetExceptionStackInfoProc(P)
  else
    Result := nil;

  // Capture stack at raise time — called BEFORE SEH unwinding.
  // Only capture if not already set — the first raise (user's) is the one we want.
  // GetLastExceptionStackTrace clears it after consumption, allowing next capture.
  if GLastExceptionStackTrace = '' then
    GLastExceptionStackTrace := GetStackTraceStr(0);
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
  InitializeExeWatch(Config);
  GExeWatch.SendDeviceInfo;
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
          GExeWatch.Log(llFatal, 'Unhandled exception: ' + E.Message, 'exception', ExtraData);
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
  if ExeWatchIsInitialized and ExeWatchIsGUIApplication and (not GFrameworkHookInstalled) then
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
  Result.AddPair('primary', TJSONBool.Create(Primary));
end;

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

  // Disks
  SetLength(Result.Disks, 0);
  DriveBits := GetLogicalDrives;
  for DriveChar := 'A' to 'Z' do
  begin
    if (DriveBits and 1) = 1 then
    begin
      DriveRoot := DriveChar + ':\';
      DriveTypeVal := GetDriveType(PChar(DriveRoot));

      // Only include fixed and removable drives
      if DriveTypeVal in [DRIVE_REMOVABLE, DRIVE_FIXED, DRIVE_REMOTE, DRIVE_RAMDISK] then
      begin
        DiskInfoRec.Drive := DriveChar + ':';

        // Get volume info
        FillChar(VolumeNameBuf, SizeOf(VolumeNameBuf), 0);
        FillChar(FileSystemBuf, SizeOf(FileSystemBuf), 0);
        VolSerial := 0;
        MaxCompLen := 0;
        FSFlags := 0;
        if GetVolumeInformation(PChar(DriveRoot), VolumeNameBuf, MAX_PATH,
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

        SetLength(Result.Disks, Length(Result.Disks) + 1);
        Result.Disks[High(Result.Disks)] := DiskInfoRec;
      end;
    end;
    DriveBits := DriveBits shr 1;
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
    TickCount64Val := GetTickCount64;
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

  // CPU - minimal info (reading /proc causes issues)
  Result.CPUName := '';
  Result.CPUCores := 0;
  Result.CPULogicalProcessors := 0;

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
  {$ENDIF}

  SetLength(Result.Disks, 0);
  SetLength(Result.Monitors, 0);

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

{ TExeWatchConfig }

class function TExeWatchConfig.Create(const AApiKey, ACustomerId: string): TExeWatchConfig;
begin
  Result.ApiKey := AApiKey;
  Result.CustomerId := ACustomerId;
  Result.BufferSize := EXEWATCH_DEFAULT_BUFFER_SIZE;
  Result.FlushIntervalMs := EXEWATCH_DEFAULT_FLUSH_INTERVAL_MS;
  Result.RetryIntervalMs := EXEWATCH_DEFAULT_RETRY_INTERVAL_MS;
  Result.StoragePath := TExeWatchHelper.GetDefaultStoragePath;
  Result.DeviceInfo := TDeviceInfo.CreateFromSystem;
  Result.SampleRate := EXEWATCH_DEFAULT_SAMPLE_RATE;
  Result.AppBinaryVersion := '';  // Empty = auto-detect (already done in CreateFromSystem)
  Result.AppVersion := '';        // User-defined version, empty by default
  Result.GaugeSamplingIntervalSec := EXEWATCH_DEFAULT_GAUGE_SAMPLING_INTERVAL_SEC;
  Result.MaxPendingAgeDays := EXEWATCH_DEFAULT_MAX_PENDING_AGE_DAYS;
  Result.AnonymizeDeviceId := False;
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

class function TExeWatchHelper.AnonymizeUsername(const AUsername: string): string;
var
  Bytes: TBytes;
  Hash: Cardinal;
  I: Integer;
begin
  if AUsername = '' then
    Exit('anonymous');
  // FNV-1a hash — fast, non-reversible, zero dependencies
  // Overflow is intentional (modular arithmetic), so disable overflow checking
  Bytes := TEncoding.UTF8.GetBytes(AUsername);
  {$IFOPT Q+}{$DEFINE EW_RESTORE_Q}{$Q-}{$ENDIF}
  Hash := 2166136261;
  for I := 0 to Length(Bytes) - 1 do
  begin
    Hash := Hash xor Bytes[I];
    Hash := Hash * 16777619;
  end;
  {$IFDEF EW_RESTORE_Q}{$Q+}{$UNDEF EW_RESTORE_Q}{$ENDIF}
  Result := IntToHex(Hash, 8).ToLower;
end;

class function TExeWatchHelper.GetDefaultStoragePath: string;
{$IFDEF MSWINDOWS}
var
  Path: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_LOCAL_APPDATA, 0, SHGFP_TYPE_CURRENT, Path) = S_OK then
    Result := IncludeTrailingPathDelimiter(Path) + 'ExeWatch' + PathDelim + 'pending'
  else
    Result := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'ExeWatch' + PathDelim + 'pending';
end;
{$ELSE}
{$IFDEF ANDROID}
begin
  // Use app's internal files directory (sandboxed, no permissions needed)
  Result := IncludeTrailingPathDelimiter(
    JStringToString(TAndroidHelper.Context.getFilesDir.getAbsolutePath))
    + 'ExeWatch' + PathDelim + 'pending';
end;
{$ELSE}
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'ExeWatch' + PathDelim + 'pending';
end;
{$ENDIF}
{$ENDIF}

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
  SendingFiles: TArray<string>;
  SendingFile: string;
  OriginalName: string;
  StartupData: TJSONObject;
  StartupMsg: string;
  Pair: TPair<string, string>;
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
    FConfig.DeviceInfo.Username := TExeWatchHelper.AnonymizeUsername(FConfig.DeviceInfo.Username);
    FConfig.DeviceInfo.DeviceId := FConfig.DeviceInfo.Username + '@' + FConfig.DeviceInfo.Hostname;
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
  FEnabled := True;
  {$IFDEF MSWINDOWS}
  FFileCounter := GetTickCount64;
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
end;

destructor TExeWatch.Destroy;
var
  I: Integer;
  TimingPair: TPair<string, TTimingEntry>;
  ThreadTimingsPair: TPair<TThreadID, TDictionary<string, TTimingEntry>>;
  ThreadStackPair: TPair<TThreadID, TList<string>>;
begin
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
    for var Pair in FBreadcrumbs do
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
  inherited;
end;

procedure TExeWatch.EnsureStoragePath;
begin
  if not TDirectory.Exists(FConfig.StoragePath) then
    TDirectory.CreateDirectory(FConfig.StoragePath);
end;

procedure TExeWatch.PurgeExpiredFiles;
var
  AllFiles: TArray<string>;
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
              FilePath.EndsWith(EXEWATCH_METRIC_FILE_EXTENSION)) then
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

procedure TExeWatch.CheckAPITraceRotation;
var
  FileSize: Int64;
begin
  // Called from within FAPITraceLock - no need to lock again
  try
    if not TFile.Exists(FAPITraceFile) then
      Exit;

    FileSize := TFile.GetSize(FAPITraceFile);
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
  LogFiles, DeviceFiles, MetricFiles: TArray<string>;
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
  FileName: string;
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

    // Write to file atomically (write to temp, then rename)
    FileName := GetNextFileName;
    TFile.WriteAllText(FileName, FileContent.ToJSON, TEncoding.UTF8);
  finally
    FileContent.Free;
  end;

  // Free ExtraData TJSONObjects from the copied events
  for I := 0 to Length(Events) - 1 do
    if Events[I].ExtraData <> nil then
      Events[I].ExtraData.Free;
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
      HttpClient.ConnectionTimeout := 10000;
      HttpClient.ResponseTimeout := 30000;

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
            lJValue := ResponseJson.FindValue('config');
            if Assigned(lJValue) and (not lJValue.Null) then
            begin
              ApplyServerConfig(lJValue as TJSONObject);
            end;

            if IsDeviceInfoFile then
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

procedure TExeWatch.QueueDeviceInfo;
var
  FileContent: TJSONObject;
  HardwareInfo: THardwareInfo;
  CustomInfoJSON: TJSONObject;
  Pair: TPair<string, string>;
  FileName: string;
  MergedInfo: TDictionary<string, string>;
begin
  // Skip if customer_id is not set yet (will be sent when SetCustomerId is called)
  if FConfig.CustomerId = '' then
    Exit;

  // Skip if already sent
  if FDeviceInfoSent then
    Exit;

  EnsureStoragePath;

  // Collect hardware info
  HardwareInfo := THardwareInfo.Collect;

  FileContent := TJSONObject.Create;
  try
    // Build the file content
    FileContent.AddPair('customer_id', FConfig.CustomerId);
    FileContent.AddPair('device', FConfig.DeviceInfo.ToJSON);
    FileContent.AddPair('hardware_info', HardwareInfo.ToJSON);

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
      FileContent.AddPair('custom_device_info', CustomInfoJSON);
    finally
      MergedInfo.Free;
    end;

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

  // Apply min_level filtering from server (errors and fatal always bypass)
  if not IsErrorLevel and (Ord(ALevel) < Ord(GetEffectiveMinLevel)) then
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
    if AExtraData.FindValue('stack_trace') = nil then
    begin
      StackTrace := GetStackTraceStr(3);
      if StackTrace <> '' then
        AExtraData.AddPair('stack_trace', StackTrace)
      else
        AExtraData.AddPair('no_stacktrace_reason', TJSONNumber.Create(GetNoStackTraceReason));
    end;
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
  finally
    FBufferLock.Leave;
  end;

  if ShouldPersist then
    PersistBuffer;
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
  ExtraData.AddPair('exception_class', E.ClassName);
  ExtraData.AddPair('exception_message', E.Message);
  {$IFDEF MSWINDOWS}
  // Capture stack trace — skip ErrorWithException itself
  StackTrace := GetStackTraceStr(1);
  ExtraData.AddPair('stack_trace', StackTrace);
  {$ENDIF}

  if AAdditionalMessage <> '' then
    Msg := AAdditionalMessage + ': ' + E.Message
  else
    Msg := E.Message;

  Log(llError, Msg, ATag, ExtraData);
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

  if FShipperThread <> nil then
  begin
    FShipperThread.WaitFor;
    FreeAndNil(FShipperThread);
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
    AutoCloseExtraData.AddPair('success', TJSONBool.Create(False));
    AutoCloseExtraData.AddPair('auto_closed', TJSONBool.Create(True));
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
    AutoCloseExtraData.AddPair('success', TJSONBool.Create(False));
    AutoCloseExtraData.AddPair('auto_closed', TJSONBool.Create(True));
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
  ExtraData.AddPair('success', TJSONBool.Create(ASuccess));

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

type
  TSTSymbol = record
    Address: NativeUInt;
    Name: string;
  end;

  TSTLineInfo = record
    Address: NativeUInt;
    Line: Integer;
    UnitName: string;
  end;

var
  GSTSymbols: array of TSTSymbol;
  GSTLines: array of TSTLineInfo;
  GSTCodeBase: NativeUInt;
  GSTSegOffsets: array[1..8] of NativeUInt;
  GSTSegCount: Integer;
  GSTLoaded: Boolean;
  GSTInitialized: Boolean;
  GSTProgramName: string;

type
  TRtlCaptureStackBackTrace = function(
    FramesToSkip, FramesToCapture: ULONG;
    BackTrace: Pointer; BackTraceHash: PULONG): USHORT; stdcall;

var
  GSTCapture: TRtlCaptureStackBackTrace = nil;

procedure STSortSymbols;
begin
  if Length(GSTSymbols) > 1 then
    TArray.Sort<TSTSymbol>(GSTSymbols, TComparer<TSTSymbol>.Construct(
      function(const A, B: TSTSymbol): Integer
      begin
        if A.Address < B.Address then Result := -1
        else if A.Address > B.Address then Result := 1
        else Result := 0;
      end));
end;

procedure STSortLines;
begin
  if Length(GSTLines) > 1 then
    TArray.Sort<TSTLineInfo>(GSTLines, TComparer<TSTLineInfo>.Construct(
      function(const A, B: TSTLineInfo): Integer
      begin
        if A.Address < B.Address then Result := -1
        else if A.Address > B.Address then Result := 1
        else Result := 0;
      end));
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

function STSegOffset(SegNum: Integer): NativeUInt;
begin
  if (SegNum >= 1) and (SegNum <= GSTSegCount) then
    Result := GSTSegOffsets[SegNum]
  else
    Result := 0;
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

procedure STGrowSymbols(var ACount: Integer);
var
  NewCap: Integer;
begin
  if ACount >= Length(GSTSymbols) then
  begin
    NewCap := Length(GSTSymbols);
    if NewCap = 0 then NewCap := 1024
    else NewCap := NewCap * 2;
    SetLength(GSTSymbols, NewCap);
  end;
end;

procedure STGrowLines(var ACount: Integer);
var
  NewCap: Integer;
begin
  if ACount >= Length(GSTLines) then
  begin
    NewCap := Length(GSTLines);
    if NewCap = 0 then NewCap := 4096
    else NewCap := NewCap * 2;
    SetLength(GSTLines, NewCap);
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

procedure STLoadMap(const FileName: string);
var
  SL: TStringList;
  I, K, P: Integer;
  Line, UnitName, Tok1, Tok2, Tok3, Tok4: string;
  EmptyCount, LineNum: Integer;
  BaseAddr: NativeUInt;
  SegNum: Integer;
  SymCount, LineCount: Integer;
begin
  GSTLoaded := False;
  SetLength(GSTSymbols, 0);
  SetLength(GSTLines, 0);
  FillChar(GSTSegOffsets, SizeOf(GSTSegOffsets), 0);
  GSTSegCount := 0;
  GSTProgramName := ChangeFileExt(ExtractFileName(FileName), '');

  if not FileExists(FileName) then
    Exit;

  SymCount := 0;
  LineCount := 0;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    I := 0;
    while I < SL.Count do
    begin
      Line := Trim(SL[I]);

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
          if (Tok4 = 'CODE') or (Tok4 = 'ICODE') then
          begin
            STParseAddr(Tok1, SegNum, BaseAddr);
            if (SegNum >= 1) and (SegNum <= High(GSTSegOffsets)) then
            begin
              GSTSegOffsets[SegNum] := BaseAddr and $FFFFF;
              if SegNum > GSTSegCount then
                GSTSegCount := SegNum;
            end;
          end;
          Inc(I);
        end;
        Continue;
      end;

      // Publics by Value - store module-relative addresses
      if Pos('Publics by Value', Line) > 0 then
      begin
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
          Tok2 := STNextToken(Line, P);
          if (Tok1 <> '') and (Tok2 <> '') then
          begin
            STParseAddr(Tok1, SegNum, BaseAddr);
            if SegNum > 0 then
            begin
              STGrowSymbols(SymCount);
              GSTSymbols[SymCount].Address := BaseAddr + STSegOffset(SegNum);
              GSTSymbols[SymCount].Name := Tok2;
              Inc(SymCount);
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
              begin
                STGrowLines(LineCount);
                GSTLines[LineCount].Address := BaseAddr + STSegOffset(SegNum);
                GSTLines[LineCount].Line := LineNum;
                GSTLines[LineCount].UnitName := UnitName;
                Inc(LineCount);
              end;
            end;
          end;
          Inc(I);
        end;
        Continue;
      end;

      Inc(I);
    end;

    // Trim to actual size
    SetLength(GSTSymbols, SymCount);
    SetLength(GSTLines, LineCount);

    STSortSymbols;
    STSortLines;
    GSTLoaded := True;
  finally
    SL.Free;
  end;
end;

function STFindSymbol(Address: NativeUInt): string;
var
  I: Integer;
  RelAddr: NativeUInt;
begin
  Result := '';
  if (Length(GSTSymbols) = 0) or (Address < GSTCodeBase) then Exit;
  RelAddr := Address - GSTCodeBase;
  if RelAddr > $1000000 then Exit;
  for I := High(GSTSymbols) downto 0 do
  begin
    if GSTSymbols[I].Address <= RelAddr then
      Exit(GSTSymbols[I].Name);
  end;
end;

procedure STFindLine(Address: NativeUInt; out ALine: Integer; out AUnit: string);
var
  I: Integer;
  RelAddr: NativeUInt;
begin
  ALine := 0;
  AUnit := '';
  if (Length(GSTLines) = 0) or (Address < GSTCodeBase) then Exit;
  RelAddr := Address - GSTCodeBase;
  if RelAddr > $1000000 then Exit;
  for I := High(GSTLines) downto 0 do
  begin
    if GSTLines[I].Address <= RelAddr then
    begin
      ALine := GSTLines[I].Line;
      AUnit := GSTLines[I].UnitName;
      Exit;
    end;
  end;
end;

function STResolveAddr(Address: NativeUInt): string;
var
  SymName, LineUnit, FuncName: string;
  LineNum: Integer;
begin
  SymName := STFindSymbol(Address);
  STFindLine(Address, LineNum, LineUnit);

  if (LineUnit <> '') and (SymName <> '') and SymName.StartsWith(LineUnit + '.') then
  begin
    FuncName := Copy(SymName, Length(LineUnit) + 2, MaxInt);
    // Win32 Finalization fix
    if (GSTProgramName <> '') and
       SameText(LineUnit, GSTProgramName) and
       SameText(FuncName, 'Finalization') then
      FuncName := GSTProgramName;
    if LineNum > 0 then
      Result := Format('%s.%s (line %d)', [LineUnit, FuncName, LineNum])
    else
      Result := Format('%s.%s', [LineUnit, FuncName]);
  end
  else if (LineUnit <> '') and (LineNum > 0) then
    Result := Format('%s (line %d)', [LineUnit, LineNum])
  else
    Result := Format('[%p]', [Pointer(Address)]);
end;

procedure STInitCapture;
var
  H: THandle;
begin
  H := GetModuleHandle('kernel32.dll');
  if H <> 0 then
    @GSTCapture := GetProcAddress(H, 'RtlCaptureStackBackTrace');
end;

procedure STEnsureInit;
var
  MapFile: string;
begin
  if GSTInitialized then Exit;
  GSTInitialized := True;
  STInitCapture;
  GSTCodeBase := NativeUInt(HInstance);
  MapFile := ChangeFileExt(GetModuleName(HInstance), '.map');
  STLoadMap(MapFile);
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
    (Pos('@HandleFinally', ALine) > 0) or
    (Pos('@HandleAnyException', ALine) > 0) or
    (Pos('@HandleOnException', ALine) > 0) or
    // ExeWatch SDK internals
    (Pos('ExeWatchGetExceptionStackInfo', ALine) > 0) or
    (Pos('ScanStackForTrace', ALine) > 0) or
    (Pos('GetStackTraceStr', ALine) > 0) or
    (Pos('GetLastExceptionStackTrace', ALine) > 0) or
    (Pos('STEnsureInit', ALine) > 0) or
    (Pos('STResolveAddr', ALine) > 0) or
    (Pos('STFindSymbol', ALine) > 0) or
    (Pos('STFindLine', ALine) > 0);
end;

function GetStackTraceStr(FramesToSkip: Integer = 0): string;
var
  Frames: array[0..ST_MAX_FRAMES - 1] of Pointer;
  Count, I: Integer;
  SB: TStringBuilder;
  S: string;
begin
  Result := '';
  STEnsureInit;
  if not Assigned(GSTCapture) then Exit;

  FillChar(Frames, SizeOf(Frames), 0);
  Count := GSTCapture(FramesToSkip + 1, ST_MAX_FRAMES, @Frames[0], nil);

  if Count = 0 then Exit;

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

function GetNoStackTraceReason: Integer;
begin
  if not Assigned(GSTCapture) then
    Result := 1  // RtlCaptureStackBackTrace not available
  else if not GSTLoaded then
    Result := 2  // Map file not found
  else
    Result := 3; // Stack capture returned 0 frames
end;

{$ELSE}

// Non-Windows stubs
function GetStackTraceStr(FramesToSkip: Integer = 0): string;
begin
  Result := '';
end;

function GetNoStackTraceReason: Integer;
begin
  Result := 4; // Platform not supported (non-Windows)
end;

{$ENDIF}

function GetLastExceptionStackTrace(E: Exception): string;
begin
  Result := GLastExceptionStackTrace;
  GLastExceptionStackTrace := ''; // consume it
end;

{$IFDEF EXEWATCH_TESTING}
function EWGetStackTraceStr(FramesToSkip: Integer = 0): string;
begin
  Result := GetStackTraceStr(FramesToSkip);
end;
{$ENDIF}

initialization
  GExeWatchLock := TCriticalSection.Create;
  // Install exception handler
  GOldExceptProc := System.ExceptProc;
  System.ExceptProc := @ExeWatchExceptProc;
  // Capture stack at raise time (Win64 only — table-based unwinding works)
  {$IFDEF MSWINDOWS}
  GOldGetExceptionStackInfoProc := Exception.GetExceptionStackInfoProc;
  Exception.GetExceptionStackInfoProc := @ExeWatchGetExceptionStackInfo;
  {$ENDIF}

finalization
  // Restore old handlers
  System.ExceptProc := @GOldExceptProc;
  {$IFDEF MSWINDOWS}
  Exception.GetExceptionStackInfoProc := GOldGetExceptionStackInfoProc;
  {$ENDIF}
  FinalizeExeWatch;
  FreeAndNil(GExeWatchLock);

end.
