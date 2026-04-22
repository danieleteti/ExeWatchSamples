//---------------------------------------------------------------------------
// ExeWatch DLL SDK Sample - C++Builder VCL Application
//
// The ExeWatch DLL is loaded dynamically at startup via LoadLibrary +
// GetProcAddress (see ExeWatchSDKv1.dynload.c, added as a project unit).
// This means:
//   * no import library (.lib/.a) to match against a specific toolchain
//     -- identical source compiles under bcc32, bcc64x, MSVC, MinGW, Clang
//   * the app stays running and shows a clear message if the DLL is
//     missing, instead of failing to start
//   * the loader is reusable: drop ExeWatchSDKv1.h + ExeWatchSDKv1.dynload.c
//     into any Windows C/C++ project to get the same behaviour.
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

// Tell ExeWatchSDKv1.h to declare every ew_* as a function-pointer
// variable and expose the ew_LoadSDK() / ew_UnloadSDK() loader API.
// ExeWatchSDKv1.dynload.c provides the corresponding definitions.
#define EW_DYNAMIC_LOAD
#include "ExeWatchSDKv1.h"

#include <Winapi.PsAPI.hpp>
#include <math.h>

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

	// Load the DLL dynamically. No import library is required --
	// the DLL just needs to sit next to the executable at run time.
	int loadRc = ew_LoadSDK();
	if (loadRc != EW_OK)
	{
		ShowMessage(String(
			"Failed to load ExeWatch DLL (rc=") + loadRc + ")\r\n\r\n"
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
	if (ew_IsSDKLoaded())
	{
		ew_Shutdown();
		ew_UnloadSDK();
	}
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
