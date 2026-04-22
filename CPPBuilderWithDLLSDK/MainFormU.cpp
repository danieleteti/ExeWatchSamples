//---------------------------------------------------------------------------
// ExeWatch DLL SDK Sample - C++Builder VCL Application
//
// This demo shows how to use the ExeWatch SDK via DLL from C++Builder.
// Each button maps to one SDK capability.
//
// The DLL is loaded at runtime via LoadLibrary + GetProcAddress so there
// is NO import library required: no .lib or .a file needs to be present
// at link time, and the app survives gracefully if the DLL is missing.
// This is the recommended pattern across every C/C++ compiler (bcc64x,
// MSVC, MinGW, Clang) because each compiler expects a differently
// formatted import library, while LoadLibrary works identically for all.
//
// Quick start:
//   1. Replace EXEWATCH_API_KEY below with your own key
//   2. Make sure ExeWatchSDKv1DLL_x64.dll (or ExeWatchSDKv1DLL.dll on
//      32-bit) is next to the executable
//   3. Build and run (F9)
//   4. Click buttons and watch events in the ExeWatch dashboard
//
// Full docs: https://exewatch.com/ui/docs
//---------------------------------------------------------------------------

#include <vcl.h>
#pragma hdrstop

#include "MainFormU.h"
#include <Winapi.PsAPI.hpp>
#include <math.h>

//---------------------------------------------------------------------------
// ExeWatch DLL — dynamic loading layer.
//
// We do NOT include ExeWatchSDKv1.h here because its function
// declarations would collide with our function-pointer globals of the
// same name. The small set of constants we need is inlined below.
// If you want the full header for reference, open
// ExeWatchSDKv1.h in the same folder.
//---------------------------------------------------------------------------

// Mirrored from ExeWatchSDKv1.h — the only constants we use in this sample:
#define EW_OK             0
#define EW_BT_CLICK       0
#define EW_BT_NAVIGATION  1
#define EW_BT_USER        8

// stdcall function-pointer types (match the DLL's C ABI exactly):
typedef int (__stdcall *TEW_Initialize)(const wchar_t*, const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_Shutdown)(void);
typedef int (__stdcall *TEW_GetVersion)(wchar_t*, int);
typedef int (__stdcall *TEW_GetLastError)(wchar_t*, int);
typedef int (__stdcall *TEW_Log)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_Crumb)(int, const wchar_t*, const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_StartTiming)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_EndTiming)(const wchar_t*, double*);
typedef int (__stdcall *TEW_SetUser)(const wchar_t*, const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_Void)(void);
typedef int (__stdcall *TEW_Pair)(const wchar_t*, const wchar_t*);
typedef int (__stdcall *TEW_Counter)(const wchar_t*, double, const wchar_t*);
typedef int (__stdcall *TEW_ErrWithStack)(const wchar_t*, const wchar_t*, const wchar_t*, const wchar_t*);

// Function pointer globals resolved once at startup by LoadExeWatchDll().
// We reuse the real ew_* names so call sites below read naturally.
static HMODULE           FEwDll                 = NULL;
static TEW_Initialize    ew_Initialize          = NULL;
static TEW_Shutdown      ew_Shutdown            = NULL;
static TEW_GetVersion    ew_GetVersion          = NULL;
static TEW_GetLastError  ew_GetLastError        = NULL;
static TEW_Log           ew_Debug               = NULL;
static TEW_Log           ew_Info                = NULL;
static TEW_Log           ew_Warning             = NULL;
static TEW_Log           ew_Error               = NULL;
static TEW_Log           ew_Fatal               = NULL;
static TEW_Crumb         ew_AddBreadcrumb       = NULL;
static TEW_StartTiming   ew_StartTiming         = NULL;
static TEW_EndTiming     ew_EndTiming           = NULL;
static TEW_SetUser       ew_SetUser             = NULL;
static TEW_Void          ew_ClearUser           = NULL;
static TEW_Pair          ew_SetTag              = NULL;
static TEW_Void          ew_ClearTags           = NULL;
static TEW_Counter       ew_IncrementCounter    = NULL;
static TEW_Counter       ew_RecordGauge         = NULL;
static TEW_Pair          ew_SetCustomDeviceInfo = NULL;
static TEW_Void          ew_SendCustomDeviceInfo = NULL;
static TEW_ErrWithStack  ew_ErrorWithStackTrace = NULL;

static bool LoadExeWatchDll()
{
#ifdef _WIN64
	FEwDll = LoadLibraryW(L"ExeWatchSDKv1DLL_x64.dll");
#else
	FEwDll = LoadLibraryW(L"ExeWatchSDKv1DLL.dll");
#endif
	if (!FEwDll)
		return false;

	// Resolve each pointer. decltype lets us reuse the typedef without repeating it.
	#define EW_BIND(fn) fn = (decltype(fn))GetProcAddress(FEwDll, #fn)
	EW_BIND(ew_Initialize);
	EW_BIND(ew_Shutdown);
	EW_BIND(ew_GetVersion);
	EW_BIND(ew_GetLastError);
	EW_BIND(ew_Debug);
	EW_BIND(ew_Info);
	EW_BIND(ew_Warning);
	EW_BIND(ew_Error);
	EW_BIND(ew_Fatal);
	EW_BIND(ew_AddBreadcrumb);
	EW_BIND(ew_StartTiming);
	EW_BIND(ew_EndTiming);
	EW_BIND(ew_SetUser);
	EW_BIND(ew_ClearUser);
	EW_BIND(ew_SetTag);
	EW_BIND(ew_ClearTags);
	EW_BIND(ew_IncrementCounter);
	EW_BIND(ew_RecordGauge);
	EW_BIND(ew_SetCustomDeviceInfo);
	EW_BIND(ew_SendCustomDeviceInfo);
	EW_BIND(ew_ErrorWithStackTrace);
	#undef EW_BIND

	// If critical entry points are missing, treat it as a load failure.
	return ew_Initialize && ew_Shutdown;
}

static void UnloadExeWatchDll()
{
	if (FEwDll) {
		FreeLibrary(FEwDll);
		FEwDll = NULL;
	}
}

//---------------------------------------------------------------------------
#pragma package(smart_init)
#pragma resource "*.dfm"
TMainForm *MainForm;

// Replace with your actual API key from the ExeWatch dashboard
static const wchar_t* EXEWATCH_API_KEY = L"ew_win_xxxxxx_USE_YOUR_OWN_KEY";

//---------------------------------------------------------------------------
// Helper: get current process working set in MB
static double GetWorkingSetMB()
{
	PROCESS_MEMORY_COUNTERS pmc;
	pmc.cb = sizeof(pmc);
	if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
		return (double)pmc.WorkingSetSize / (1024.0 * 1024.0);
	return 0.0;
}

// Helper: get free disk space on C: in GB
static double GetDiskFreeGB()
{
	__int64 freeBytes = DiskFree(3);  // 3 = C:
	if (freeBytes >= 0)
		return (double)freeBytes / (1024.0 * 1024.0 * 1024.0);
	return 0.0;
}

//---------------------------------------------------------------------------
__fastcall TMainForm::TMainForm(TComponent* Owner) : TForm(Owner)
{
}

//---------------------------------------------------------------------------
// INITIALIZATION
//---------------------------------------------------------------------------
void __fastcall TMainForm::FormCreate(TObject *Sender)
{
	Randomize();
	Constraints->MaxWidth = Width;
	Memo1->Clear();

	// Check API key
	if (wcscmp(EXEWATCH_API_KEY, L"ew_win_xxxxxx_USE_YOUR_OWN_KEY") == 0)
	{
		ShowMessage(
			"API Key Not Configured\r\n\r\n"
			"You must set your API key before running this sample.\r\n"
			"Open MainFormU.cpp, find the EXEWATCH_API_KEY constant and replace\r\n"
			"\"ew_win_xxxxxx_USE_YOUR_OWN_KEY\" with your actual API key.\r\n\r\n"
			"Get your API key from: https://exewatch.com");
		Application->Terminate();
		return;
	}

	// Load the DLL dynamically. No import library is required — the
	// DLL just needs to sit next to the executable at run time.
	if (!LoadExeWatchDll())
	{
		ShowMessage(
			"Failed to load ExeWatch DLL.\r\n\r\n"
#ifdef _WIN64
			"Make sure ExeWatchSDKv1DLL_x64.dll is in the same folder\r\n"
#else
			"Make sure ExeWatchSDKv1DLL.dll is in the same folder\r\n"
#endif
			"as the executable and try again.");
		Application->Terminate();
		return;
	}

	// Initialize SDK
	int result = ew_Initialize(EXEWATCH_API_KEY, L"Sample C++ Customer", L"");
	if (result != EW_OK)
	{
		wchar_t errBuf[1024];
		ew_GetLastError(errBuf, 1024);
		ShowMessage(String("ExeWatch initialization failed: ") + errBuf);
		Application->Terminate();
		return;
	}

	// Show SDK version in caption
	wchar_t verBuf[64];
	if (ew_GetVersion(verBuf, 64) == EW_OK)
		Caption = Caption + " - ExeWatch SDK " + String(verBuf);

	// Custom device info
	ew_SetCustomDeviceInfo(L"env", L"staging");
	ew_SetCustomDeviceInfo(L"sample", L"CPPBuilderVCL_DLL");
	ew_SendCustomDeviceInfo();

	// Periodic gauge timer (replaces RegisterPeriodicGauge)
	tmrPeriodicGauge->Interval = 30000;
	tmrPeriodicGauge->Enabled = true;

	// VCL exception handler
	Application->OnException = OnAppException;

	Log("ExeWatch initialized via DLL (C++Builder VCL)");
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::FormDestroy(TObject *Sender)
{
	tmrPeriodicGauge->Enabled = false;
	if (ew_Shutdown) ew_Shutdown();
	UnloadExeWatchDll();
}

//---------------------------------------------------------------------------
void TMainForm::Log(const String &AMessage)
{
	Memo1->Lines->Add(FormatDateTime("hh:nn:ss", Now()) + "  " + AMessage);
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::OnAppException(TObject *Sender, Exception *E)
{
	String msg = String(E->ClassName()) + ": " + E->Message;
	ew_ErrorWithStackTrace(msg.c_str(), L"exception", NULL, E->ClassName().c_str());
	Application->ShowException(E);
}

//---------------------------------------------------------------------------
// PERIODIC GAUGE TIMER
//---------------------------------------------------------------------------
void __fastcall TMainForm::tmrPeriodicGaugeTimer(TObject *Sender)
{
	ew_RecordGauge(L"memory_mb", GetWorkingSetMB(), L"system");
	ew_RecordGauge(L"disk_free_gb", GetDiskFreeGB(), L"system");
}

//---------------------------------------------------------------------------
// LOGGING
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnDebugClick(TObject *Sender)
{
	ew_Debug(L"This is a DEBUG message", L"sample");
	Log("[DEBUG] Sent debug log");
}

void __fastcall TMainForm::btnInfoClick(TObject *Sender)
{
	ew_Info(L"This is an INFO message", L"sample");
	Log("[INFO] Sent info log");
}

void __fastcall TMainForm::btnWarningClick(TObject *Sender)
{
	ew_Warning(L"This is a WARNING message", L"sample");
	Log("[WARNING] Sent warning log");
}

void __fastcall TMainForm::btnErrorClick(TObject *Sender)
{
	ew_Error(L"This is an ERROR message", L"sample");
	Log("[ERROR] Sent error log");
}

void __fastcall TMainForm::btnFatalClick(TObject *Sender)
{
	ew_Fatal(L"This is a FATAL message", L"sample");
	Log("[FATAL] Sent fatal log");
}

//---------------------------------------------------------------------------
// TIMING
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnTimingClick(TObject *Sender)
{
	static const wchar_t* Operations[] = {
		L"Customers Query", L"Invoices Aggregate", L"Create Reports"
	};

	int count = 4 + Random(4);
	for (int i = 0; i < count; i++)
	{
		int duration = 100 + Random(1500);
		const wchar_t* timingId = Operations[Random(3)];

		Log(String("Timing started: ") + timingId +
			" - simulating " + IntToStr(duration) + " ms...");

		ew_StartTiming(timingId, L"sample");
		try
		{
			Sleep(duration);
			if (Random(10) > 7)
				throw Exception("Some Error Occurred");

			double elapsed;
			ew_EndTiming(timingId, &elapsed);
			Log("Success");
		}
		catch (Exception &E)
		{
			double elapsed;
			ew_EndTiming(timingId, &elapsed);
			Log("Failed");
		}
	}
}

void __fastcall TMainForm::btnSingleTimingClick(TObject *Sender)
{
	int duration = 100 + Random(1500);
	Log("Timing started: [Billing] simulating " +
		IntToStr(duration) + " ms...");

	ew_StartTiming(L"Billing", L"billing");
	try
	{
		Sleep(duration);
		double elapsed;
		ew_EndTiming(L"Billing", &elapsed);
		Log("Success");
	}
	catch (Exception &E)
	{
		double elapsed;
		ew_EndTiming(L"Billing", &elapsed);
		Log("Failed");
		throw;
	}
}

//---------------------------------------------------------------------------
// BREADCRUMBS + ERROR
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnBreadcrumbsErrorClick(TObject *Sender)
{
	ew_AddBreadcrumb(EW_BT_NAVIGATION, L"navigation",
					 L"User opened customer details", NULL);
	Log("Breadcrumb: User opened customer details");

	ew_AddBreadcrumb(EW_BT_USER, L"user",
					 L"Edited billing address", NULL);
	Log("Breadcrumb: Edited billing address");

	ew_AddBreadcrumb(EW_BT_CLICK, L"ui",
					 L"Clicked Save", NULL);
	Log("Breadcrumb: Clicked Save");

	// Simulate an exception
	throw Exception("Save failed: invalid postal code");
}

//---------------------------------------------------------------------------
// USER IDENTITY
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnSetUserClick(TObject *Sender)
{
	ew_SetUser(L"user-42", L"jane@example.com", L"Jane Doe");
	ew_Info(L"User identity configured", L"sample");
	Log("User set - id: user-42, email: jane@example.com, name: Jane Doe");
}

void __fastcall TMainForm::btnClearUserClick(TObject *Sender)
{
	ew_ClearUser();
	ew_Info(L"User identity cleared", L"sample");
	Log("User cleared");
}

//---------------------------------------------------------------------------
// TAGS
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnSetTagsClick(TObject *Sender)
{
	ew_SetTag(L"environment", L"staging");
	ew_SetTag(L"feature_flag", L"new_checkout");
	ew_Info(L"Tags configured", L"sample");
	Log("Tags set - environment=staging, feature_flag=new_checkout");
}

void __fastcall TMainForm::btnClearTagsClick(TObject *Sender)
{
	ew_ClearTags();
	ew_Info(L"Tags cleared", L"sample");
	Log("Tags cleared");
}

//---------------------------------------------------------------------------
// METRICS
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnIncrementCounter1Click(TObject *Sender)
{
	ew_IncrementCounter(L"orders.new", 1.0, L"warehouse");
	Log("Counter incremented");
}

void __fastcall TMainForm::btnIncrementCounter2Click(TObject *Sender)
{
	ew_IncrementCounter(L"orders.shipped", 1.0, L"sample");
	Log("Counter incremented");
}

void __fastcall TMainForm::btnCounter3Click(TObject *Sender)
{
	ew_IncrementCounter(L"orders.billed", 1.0, L"warehouse");
	Log("Counter incremented");
}

void __fastcall TMainForm::btnRecordGaugeClick(TObject *Sender)
{
	int items = 1 + Random(10);
	ew_RecordGauge(L"cart_items", (double)items, L"sample");
	Log("Gauge recorded - cart_items = " + IntToStr(items));
}

//---------------------------------------------------------------------------
// CLEAR LOG
//---------------------------------------------------------------------------
void __fastcall TMainForm::btnClearLogClick(TObject *Sender)
{
	Memo1->Clear();
}
//---------------------------------------------------------------------------
