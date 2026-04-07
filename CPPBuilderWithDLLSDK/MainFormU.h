//---------------------------------------------------------------------------
// ExeWatch DLL SDK Sample - C++Builder VCL
//---------------------------------------------------------------------------

#ifndef MainFormUH
#define MainFormUH
//---------------------------------------------------------------------------
#include <System.Classes.hpp>
#include <Vcl.Controls.hpp>
#include <Vcl.StdCtrls.hpp>
#include <Vcl.Forms.hpp>
#include <Vcl.ExtCtrls.hpp>
//---------------------------------------------------------------------------
class TMainForm : public TForm
{
__published:
	TPanel *Panel1;
	TShape *Shape1;
	TLabel *Label1;
	TGroupBox *grpLogging;
	TButton *btnDebug;
	TButton *btnInfo;
	TButton *btnWarning;
	TButton *btnError;
	TButton *btnFatal;
	TGroupBox *grpTiming;
	TButton *btnSingleTiming;
	TButton *btnTiming;
	TGroupBox *grpBreadcrumbs;
	TButton *btnBreadcrumbsError;
	TGroupBox *grpUser;
	TButton *btnSetUser;
	TButton *btnClearUser;
	TGroupBox *grpTags;
	TButton *btnSetTags;
	TButton *btnClearTags;
	TGroupBox *grpMetrics;
	TButton *btnIncrementCounter1;
	TButton *btnIncrementCounter2;
	TButton *btnCounter3;
	TButton *btnRecordGauge;
	TLabel *lblLog;
	TButton *btnClearLog;
	TMemo *Memo1;
	TTimer *tmrPeriodicGauge;

	void __fastcall FormCreate(TObject *Sender);
	void __fastcall FormDestroy(TObject *Sender);
	void __fastcall btnDebugClick(TObject *Sender);
	void __fastcall btnInfoClick(TObject *Sender);
	void __fastcall btnWarningClick(TObject *Sender);
	void __fastcall btnErrorClick(TObject *Sender);
	void __fastcall btnFatalClick(TObject *Sender);
	void __fastcall btnTimingClick(TObject *Sender);
	void __fastcall btnSingleTimingClick(TObject *Sender);
	void __fastcall btnBreadcrumbsErrorClick(TObject *Sender);
	void __fastcall btnSetUserClick(TObject *Sender);
	void __fastcall btnClearUserClick(TObject *Sender);
	void __fastcall btnSetTagsClick(TObject *Sender);
	void __fastcall btnClearTagsClick(TObject *Sender);
	void __fastcall btnIncrementCounter1Click(TObject *Sender);
	void __fastcall btnIncrementCounter2Click(TObject *Sender);
	void __fastcall btnCounter3Click(TObject *Sender);
	void __fastcall btnRecordGaugeClick(TObject *Sender);
	void __fastcall btnClearLogClick(TObject *Sender);
	void __fastcall tmrPeriodicGaugeTimer(TObject *Sender);

private:
	void Log(const String &AMessage);
	void __fastcall OnAppException(TObject *Sender, Exception *E);

public:
	__fastcall TMainForm(TComponent* Owner);
};
//---------------------------------------------------------------------------
extern PACKAGE TMainForm *MainForm;
//---------------------------------------------------------------------------
#endif
