namespace ExeWatchWindowsForms;

partial class MainForm
{
    private System.ComponentModel.IContainer components = null;

    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
            components.Dispose();
        base.Dispose(disposing);
    }

    #region Windows Form Designer generated code

    private void InitializeComponent()
    {
        // Top Panel - Connection
        pnlTop = new Panel();
        lblStep1 = new Label();
        lblApiKey = new Label();
        edtApiKey = new TextBox();
        lblCustomerId = new Label();
        edtCustomerId = new TextBox();
        btnUse = new Button();
        btnDisconnect = new Button();
        lblStatus = new Label();

        // Center - TabControl
        pnlCenter = new Panel();
        tcFeatures = new TabControl();

        // Tab: Logging
        tabLogging = new TabPage();
        lblLoggingDesc = new Label();
        grpManualLog = new GroupBox();
        lblMessage = new Label();
        edtMessage = new TextBox();
        lblTag = new Label();
        edtTag = new TextBox();
        btnDebug = new Button();
        btnInfo = new Button();
        btnWarning = new Button();
        btnError = new Button();
        btnFatal = new Button();
        grpQuickTests = new GroupBox();
        btnGenerateLogs = new Button();
        btnTestException = new Button();
        grpBreadcrumbs = new GroupBox();
        lblBreadcrumbsDesc = new Label();

        // Tab: Timing
        tabTiming = new TabPage();
        lblTimingDesc = new Label();
        grpTimingBasic = new GroupBox();
        btnTimingNested = new Button();
        btnTimingParallel = new Button();
        btnTimingLIFO = new Button();
        btnTimingFormat = new Button();
        btnTimingAll = new Button();
        grpTimingAdvanced = new GroupBox();
        btnTimingWithMeta = new Button();
        btnTimingCancel = new Button();
        btnTimingActive = new Button();

        // Tab: Device Info
        tabDeviceInfo = new TabPage();
        lblDeviceInfoDesc = new Label();
        grpCustomInfo = new GroupBox();
        lblCustomKey = new Label();
        edtCustomKey = new TextBox();
        lblCustomValue = new Label();
        edtCustomValue = new TextBox();
        btnSetCustomInfo = new Button();
        btnSendCustomInfo = new Button();
        grpAutoInfo = new GroupBox();
        lblAutoInfoList = new Label();

        // Tab: User/Tags
        tabUserTags = new TabPage();
        lblUserDesc = new Label();
        grpUserCode = new GroupBox();
        lblUserCode = new Label();
        grpTagsCode = new GroupBox();
        lblTagsCode = new Label();

        // Tab: Metrics
        tabMetrics = new TabPage();
        lblMetricsDesc = new Label();
        grpCounters = new GroupBox();
        btnCounterIncrement = new Button();
        btnCounterBatch = new Button();
        btnCounterWithTag = new Button();
        grpGauges = new GroupBox();
        btnGaugeRecord = new Button();
        btnGaugeMultiple = new Button();
        btnGaugeWithTag = new Button();
        grpPeriodicGauges = new GroupBox();
        btnRegisterGauge = new Button();
        btnUnregisterGauge = new Button();
        btnMetricsAll = new Button();

        // Tab: Updates
        tabUpdates = new TabPage();
        lblUpdatesDesc = new Label();
        grpSimulate = new GroupBox();
        lblCurrentVersion = new Label();
        btnSimulateUpgrade = new Button();
        btnSimulateDowngrade = new Button();
        btnPopulateDevices = new Button();
        grpHowItWorks = new GroupBox();
        lblHowItWorks = new Label();

        // Bottom Panel - Log Output
        pnlBottom = new Panel();
        lblLogOutput = new Label();
        txtLog = new TextBox();

        SuspendLayout();

        // ============ TOP PANEL ============
        pnlTop.SuspendLayout();
        pnlTop.Dock = DockStyle.Top;
        pnlTop.Height = 75;
        pnlTop.Padding = new Padding(8, 4, 8, 4);

        lblStep1.Text = "Step 1: Connect to ExeWatch";
        lblStep1.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        lblStep1.Location = new Point(12, 6);
        lblStep1.AutoSize = true;

        lblApiKey.Text = "API Key:";
        lblApiKey.Location = new Point(12, 30);
        lblApiKey.AutoSize = true;

        edtApiKey.Location = new Point(72, 27);
        edtApiKey.Size = new Size(300, 23);

        lblCustomerId.Text = "Customer ID:";
        lblCustomerId.Location = new Point(380, 30);
        lblCustomerId.AutoSize = true;

        edtCustomerId.Location = new Point(465, 27);
        edtCustomerId.Size = new Size(150, 23);

        btnUse.Text = "Initialize";
        btnUse.Location = new Point(625, 25);
        btnUse.Size = new Size(80, 28);
        btnUse.Click += BtnUse_Click;

        btnDisconnect.Text = "Finalize";
        btnDisconnect.Location = new Point(710, 25);
        btnDisconnect.Size = new Size(75, 28);
        btnDisconnect.Click += BtnDisconnect_Click;

        lblStatus.Text = "Status: Disconnected";
        lblStatus.ForeColor = Color.Gray;
        lblStatus.Location = new Point(12, 55);
        lblStatus.AutoSize = true;

        pnlTop.Controls.Add(lblStep1);
        pnlTop.Controls.Add(lblApiKey);
        pnlTop.Controls.Add(edtApiKey);
        pnlTop.Controls.Add(lblCustomerId);
        pnlTop.Controls.Add(edtCustomerId);
        pnlTop.Controls.Add(btnUse);
        pnlTop.Controls.Add(btnDisconnect);
        pnlTop.Controls.Add(lblStatus);
        pnlTop.ResumeLayout(false);

        // ============ BOTTOM PANEL ============
        pnlBottom.SuspendLayout();
        pnlBottom.Dock = DockStyle.Bottom;
        pnlBottom.Height = 160;

        lblLogOutput.Text = "Log Output:";
        lblLogOutput.Location = new Point(12, 4);
        lblLogOutput.AutoSize = true;
        lblLogOutput.Font = new Font("Segoe UI", 9F, FontStyle.Bold);

        txtLog.Multiline = true;
        txtLog.ReadOnly = true;
        txtLog.ScrollBars = ScrollBars.Vertical;
        txtLog.Font = new Font("Consolas", 8.5F);
        txtLog.BackColor = Color.White;
        txtLog.Location = new Point(12, 22);
        txtLog.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        txtLog.Size = new Size(876, 130);

        pnlBottom.Controls.Add(lblLogOutput);
        pnlBottom.Controls.Add(txtLog);
        pnlBottom.ResumeLayout(false);

        // ============ CENTER PANEL ============
        pnlCenter.Dock = DockStyle.Fill;
        pnlCenter.Padding = new Padding(8, 4, 8, 4);

        tcFeatures.Dock = DockStyle.Fill;
        tcFeatures.TabPages.Add(tabLogging);
        tcFeatures.TabPages.Add(tabTiming);
        tcFeatures.TabPages.Add(tabDeviceInfo);
        tcFeatures.TabPages.Add(tabUserTags);
        tcFeatures.TabPages.Add(tabMetrics);
        tcFeatures.TabPages.Add(tabUpdates);
        pnlCenter.Controls.Add(tcFeatures);

        // ============ TAB: LOGGING ============
        tabLogging.Text = "Logging";
        tabLogging.Padding = new Padding(8);
        tabLogging.AutoScroll = true;

        lblLoggingDesc.Text = "Step 2: Send logs to ExeWatch. Choose a level and click to send.";
        lblLoggingDesc.Location = new Point(12, 8);
        lblLoggingDesc.AutoSize = true;

        // Manual Log Group
        grpManualLog.Text = "Manual Log";
        grpManualLog.Location = new Point(12, 30);
        grpManualLog.Size = new Size(860, 90);

        lblMessage.Text = "Message:";
        lblMessage.Location = new Point(10, 25);
        lblMessage.AutoSize = true;
        edtMessage.Location = new Point(70, 22);
        edtMessage.Size = new Size(300, 23);

        lblTag.Text = "Tag:";
        lblTag.Location = new Point(380, 25);
        lblTag.AutoSize = true;
        edtTag.Location = new Point(410, 22);
        edtTag.Size = new Size(100, 23);

        btnDebug.Text = "Debug";
        btnDebug.Location = new Point(10, 55);
        btnDebug.Size = new Size(75, 28);
        btnDebug.BackColor = Color.FromArgb(220, 220, 220);
        btnDebug.Click += BtnDebug_Click;

        btnInfo.Text = "Info";
        btnInfo.Location = new Point(90, 55);
        btnInfo.Size = new Size(75, 28);
        btnInfo.BackColor = Color.FromArgb(200, 230, 255);
        btnInfo.Click += BtnInfo_Click;

        btnWarning.Text = "Warning";
        btnWarning.Location = new Point(170, 55);
        btnWarning.Size = new Size(75, 28);
        btnWarning.BackColor = Color.FromArgb(255, 240, 200);
        btnWarning.Click += BtnWarning_Click;

        btnError.Text = "Error";
        btnError.Location = new Point(250, 55);
        btnError.Size = new Size(75, 28);
        btnError.BackColor = Color.FromArgb(255, 210, 210);
        btnError.Click += BtnError_Click;

        btnFatal.Text = "Fatal";
        btnFatal.Location = new Point(330, 55);
        btnFatal.Size = new Size(75, 28);
        btnFatal.BackColor = Color.FromArgb(255, 150, 150);
        btnFatal.Click += BtnFatal_Click;

        grpManualLog.Controls.Add(lblMessage);
        grpManualLog.Controls.Add(edtMessage);
        grpManualLog.Controls.Add(lblTag);
        grpManualLog.Controls.Add(edtTag);
        grpManualLog.Controls.Add(btnDebug);
        grpManualLog.Controls.Add(btnInfo);
        grpManualLog.Controls.Add(btnWarning);
        grpManualLog.Controls.Add(btnError);
        grpManualLog.Controls.Add(btnFatal);

        // Quick Tests Group
        grpQuickTests.Text = "Quick Tests";
        grpQuickTests.Location = new Point(12, 125);
        grpQuickTests.Size = new Size(420, 65);

        btnGenerateLogs.Text = "Generate Sample Logs";
        btnGenerateLogs.Location = new Point(10, 25);
        btnGenerateLogs.Size = new Size(150, 28);
        btnGenerateLogs.Click += BtnGenerateLogs_Click;

        btnTestException.Text = "Test Exception";
        btnTestException.Location = new Point(170, 25);
        btnTestException.Size = new Size(120, 28);
        btnTestException.Click += BtnTestException_Click;

        grpQuickTests.Controls.Add(btnGenerateLogs);
        grpQuickTests.Controls.Add(btnTestException);

        // Breadcrumbs Group
        grpBreadcrumbs.Text = "Breadcrumbs";
        grpBreadcrumbs.Location = new Point(440, 125);
        grpBreadcrumbs.Size = new Size(432, 65);

        lblBreadcrumbsDesc.Text = "Breadcrumbs are auto-captured and attached to Error/Fatal logs.\nUse EW.AddBreadcrumb(\"message\", \"category\") to add manually.";
        lblBreadcrumbsDesc.Location = new Point(10, 22);
        lblBreadcrumbsDesc.AutoSize = true;

        grpBreadcrumbs.Controls.Add(lblBreadcrumbsDesc);

        tabLogging.Controls.Add(lblLoggingDesc);
        tabLogging.Controls.Add(grpManualLog);
        tabLogging.Controls.Add(grpQuickTests);
        tabLogging.Controls.Add(grpBreadcrumbs);

        // ============ TAB: TIMING ============
        tabTiming.Text = "Timing";
        tabTiming.Padding = new Padding(8);

        lblTimingDesc.Text = "Timing/Profiling: Measure operation durations with high precision.";
        lblTimingDesc.Location = new Point(12, 8);
        lblTimingDesc.AutoSize = true;

        grpTimingBasic.Text = "Basic Timing Tests";
        grpTimingBasic.Location = new Point(12, 30);
        grpTimingBasic.Size = new Size(860, 65);

        btnTimingNested.Text = "Nested";
        btnTimingNested.Location = new Point(10, 25);
        btnTimingNested.Size = new Size(80, 28);
        btnTimingNested.Click += BtnTimingNested_Click;

        btnTimingParallel.Text = "Parallel";
        btnTimingParallel.Location = new Point(95, 25);
        btnTimingParallel.Size = new Size(80, 28);
        btnTimingParallel.Click += BtnTimingParallel_Click;

        btnTimingLIFO.Text = "LIFO";
        btnTimingLIFO.Location = new Point(180, 25);
        btnTimingLIFO.Size = new Size(80, 28);
        btnTimingLIFO.Click += BtnTimingLIFO_Click;

        btnTimingFormat.Text = "Format ID";
        btnTimingFormat.Location = new Point(265, 25);
        btnTimingFormat.Size = new Size(80, 28);
        btnTimingFormat.Click += BtnTimingFormat_Click;

        btnTimingAll.Text = "Run All";
        btnTimingAll.Location = new Point(500, 25);
        btnTimingAll.Size = new Size(80, 28);
        btnTimingAll.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        btnTimingAll.Click += BtnTimingAll_Click;

        grpTimingBasic.Controls.Add(btnTimingNested);
        grpTimingBasic.Controls.Add(btnTimingParallel);
        grpTimingBasic.Controls.Add(btnTimingLIFO);
        grpTimingBasic.Controls.Add(btnTimingFormat);
        grpTimingBasic.Controls.Add(btnTimingAll);

        grpTimingAdvanced.Text = "Advanced";
        grpTimingAdvanced.Location = new Point(12, 100);
        grpTimingAdvanced.Size = new Size(860, 65);

        btnTimingWithMeta.Text = "With Metadata";
        btnTimingWithMeta.Location = new Point(10, 25);
        btnTimingWithMeta.Size = new Size(110, 28);
        btnTimingWithMeta.Click += BtnTimingWithMeta_Click;

        btnTimingCancel.Text = "Cancel";
        btnTimingCancel.Location = new Point(125, 25);
        btnTimingCancel.Size = new Size(80, 28);
        btnTimingCancel.Click += BtnTimingCancel_Click;

        btnTimingActive.Text = "Active Timings";
        btnTimingActive.Location = new Point(210, 25);
        btnTimingActive.Size = new Size(110, 28);
        btnTimingActive.Click += BtnTimingActive_Click;

        grpTimingAdvanced.Controls.Add(btnTimingWithMeta);
        grpTimingAdvanced.Controls.Add(btnTimingCancel);
        grpTimingAdvanced.Controls.Add(btnTimingActive);

        tabTiming.Controls.Add(lblTimingDesc);
        tabTiming.Controls.Add(grpTimingBasic);
        tabTiming.Controls.Add(grpTimingAdvanced);

        // ============ TAB: DEVICE INFO ============
        tabDeviceInfo.Text = "Device Info";
        tabDeviceInfo.Padding = new Padding(8);

        lblDeviceInfoDesc.Text = "Device info is automatically collected and sent on SDK initialization.";
        lblDeviceInfoDesc.Location = new Point(12, 8);
        lblDeviceInfoDesc.AutoSize = true;

        grpCustomInfo.Text = "Custom Device Info";
        grpCustomInfo.Location = new Point(12, 30);
        grpCustomInfo.Size = new Size(860, 65);

        lblCustomKey.Text = "Key:";
        lblCustomKey.Location = new Point(10, 28);
        lblCustomKey.AutoSize = true;
        edtCustomKey.Location = new Point(40, 25);
        edtCustomKey.Size = new Size(150, 23);

        lblCustomValue.Text = "Value:";
        lblCustomValue.Location = new Point(200, 28);
        lblCustomValue.AutoSize = true;
        edtCustomValue.Location = new Point(240, 25);
        edtCustomValue.Size = new Size(150, 23);

        btnSetCustomInfo.Text = "Set";
        btnSetCustomInfo.Location = new Point(400, 23);
        btnSetCustomInfo.Size = new Size(60, 28);
        btnSetCustomInfo.Click += BtnSetCustomInfo_Click;

        btnSendCustomInfo.Text = "Send";
        btnSendCustomInfo.Location = new Point(465, 23);
        btnSendCustomInfo.Size = new Size(60, 28);
        btnSendCustomInfo.Click += BtnSendCustomInfo_Click;

        grpCustomInfo.Controls.Add(lblCustomKey);
        grpCustomInfo.Controls.Add(edtCustomKey);
        grpCustomInfo.Controls.Add(lblCustomValue);
        grpCustomInfo.Controls.Add(edtCustomValue);
        grpCustomInfo.Controls.Add(btnSetCustomInfo);
        grpCustomInfo.Controls.Add(btnSendCustomInfo);

        grpAutoInfo.Text = "Auto-Collected Info";
        grpAutoInfo.Location = new Point(12, 100);
        grpAutoInfo.Size = new Size(860, 90);

        lblAutoInfoList.Text = "CPU, RAM, Disks, Monitors, OS version, IP addresses, Timezone,\nApp binary version, Runtime version (.NET), Hostname, Username";
        lblAutoInfoList.Location = new Point(10, 22);
        lblAutoInfoList.AutoSize = true;

        grpAutoInfo.Controls.Add(lblAutoInfoList);

        tabDeviceInfo.Controls.Add(lblDeviceInfoDesc);
        tabDeviceInfo.Controls.Add(grpCustomInfo);
        tabDeviceInfo.Controls.Add(grpAutoInfo);

        // ============ TAB: USER/TAGS ============
        tabUserTags.Text = "User / Tags";
        tabUserTags.Padding = new Padding(8);

        lblUserDesc.Text = "User Identity and Global Tags are included in every log event.";
        lblUserDesc.Location = new Point(12, 8);
        lblUserDesc.AutoSize = true;

        grpUserCode.Text = "User Identity - Code Example";
        grpUserCode.Location = new Point(12, 30);
        grpUserCode.Size = new Size(860, 70);

        lblUserCode.Text = "EW.SetUser(\"user_123\", \"john@acme.com\", \"John Doe\");\nEW.ClearUser();  // Remove user identity";
        lblUserCode.Location = new Point(10, 22);
        lblUserCode.AutoSize = true;
        lblUserCode.Font = new Font("Consolas", 9F);

        grpUserCode.Controls.Add(lblUserCode);

        grpTagsCode.Text = "Global Tags - Code Example";
        grpTagsCode.Location = new Point(12, 108);
        grpTagsCode.Size = new Size(860, 85);

        lblTagsCode.Text = "EW.SetTag(\"environment\", \"production\");\nEW.SetTag(\"region\", \"us-east\");\nEW.RemoveTag(\"region\");\nEW.ClearTags();  // Remove all tags";
        lblTagsCode.Location = new Point(10, 22);
        lblTagsCode.AutoSize = true;
        lblTagsCode.Font = new Font("Consolas", 9F);

        grpTagsCode.Controls.Add(lblTagsCode);

        tabUserTags.Controls.Add(lblUserDesc);
        tabUserTags.Controls.Add(grpUserCode);
        tabUserTags.Controls.Add(grpTagsCode);

        // ============ TAB: METRICS ============
        tabMetrics.Text = "Metrics";
        tabMetrics.Padding = new Padding(8);
        tabMetrics.AutoScroll = true;

        lblMetricsDesc.Text = "Pre-aggregated metrics: Counters (cumulative sums) and Gauges (point-in-time values).";
        lblMetricsDesc.Location = new Point(12, 8);
        lblMetricsDesc.AutoSize = true;

        grpCounters.Text = "Counters";
        grpCounters.Location = new Point(12, 30);
        grpCounters.Size = new Size(420, 65);

        btnCounterIncrement.Text = "+1";
        btnCounterIncrement.Location = new Point(10, 25);
        btnCounterIncrement.Size = new Size(60, 28);
        btnCounterIncrement.Click += BtnCounterIncrement_Click;

        btnCounterBatch.Text = "+4096/+8192";
        btnCounterBatch.Location = new Point(75, 25);
        btnCounterBatch.Size = new Size(100, 28);
        btnCounterBatch.Click += BtnCounterBatch_Click;

        btnCounterWithTag.Text = "With Tag";
        btnCounterWithTag.Location = new Point(180, 25);
        btnCounterWithTag.Size = new Size(80, 28);
        btnCounterWithTag.Click += BtnCounterWithTag_Click;

        grpCounters.Controls.Add(btnCounterIncrement);
        grpCounters.Controls.Add(btnCounterBatch);
        grpCounters.Controls.Add(btnCounterWithTag);

        grpGauges.Text = "Gauges";
        grpGauges.Location = new Point(440, 30);
        grpGauges.Size = new Size(432, 65);

        btnGaugeRecord.Text = "Record";
        btnGaugeRecord.Location = new Point(10, 25);
        btnGaugeRecord.Size = new Size(70, 28);
        btnGaugeRecord.Click += BtnGaugeRecord_Click;

        btnGaugeMultiple.Text = "Multiple";
        btnGaugeMultiple.Location = new Point(85, 25);
        btnGaugeMultiple.Size = new Size(75, 28);
        btnGaugeMultiple.Click += BtnGaugeMultiple_Click;

        btnGaugeWithTag.Text = "With Tag";
        btnGaugeWithTag.Location = new Point(165, 25);
        btnGaugeWithTag.Size = new Size(80, 28);
        btnGaugeWithTag.Click += BtnGaugeWithTag_Click;

        grpGauges.Controls.Add(btnGaugeRecord);
        grpGauges.Controls.Add(btnGaugeMultiple);
        grpGauges.Controls.Add(btnGaugeWithTag);

        grpPeriodicGauges.Text = "Periodic Gauges";
        grpPeriodicGauges.Location = new Point(12, 100);
        grpPeriodicGauges.Size = new Size(420, 65);

        btnRegisterGauge.Text = "Register";
        btnRegisterGauge.Location = new Point(10, 25);
        btnRegisterGauge.Size = new Size(80, 28);
        btnRegisterGauge.Click += BtnRegisterGauge_Click;

        btnUnregisterGauge.Text = "Unregister";
        btnUnregisterGauge.Location = new Point(95, 25);
        btnUnregisterGauge.Size = new Size(85, 28);
        btnUnregisterGauge.Click += BtnUnregisterGauge_Click;

        grpPeriodicGauges.Controls.Add(btnRegisterGauge);
        grpPeriodicGauges.Controls.Add(btnUnregisterGauge);

        btnMetricsAll.Text = "Run All Metrics Tests";
        btnMetricsAll.Location = new Point(440, 125);
        btnMetricsAll.Size = new Size(170, 28);
        btnMetricsAll.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        btnMetricsAll.Click += BtnMetricsAll_Click;

        tabMetrics.Controls.Add(lblMetricsDesc);
        tabMetrics.Controls.Add(grpCounters);
        tabMetrics.Controls.Add(grpGauges);
        tabMetrics.Controls.Add(grpPeriodicGauges);
        tabMetrics.Controls.Add(btnMetricsAll);

        // ============ TAB: UPDATES ============
        tabUpdates.Text = "Updates";
        tabUpdates.Padding = new Padding(8);

        lblUpdatesDesc.Text = "Simulate version upgrades/downgrades to test version tracking.";
        lblUpdatesDesc.Location = new Point(12, 8);
        lblUpdatesDesc.AutoSize = true;

        grpSimulate.Text = "Simulate Version Change";
        grpSimulate.Location = new Point(12, 30);
        grpSimulate.Size = new Size(860, 100);

        lblCurrentVersion.Text = "Current simulated version: 1.0.0-demo_oxygen";
        lblCurrentVersion.Location = new Point(10, 25);
        lblCurrentVersion.AutoSize = true;

        btnSimulateUpgrade.Text = "Simulate Upgrade";
        btnSimulateUpgrade.Location = new Point(10, 55);
        btnSimulateUpgrade.Size = new Size(130, 28);
        btnSimulateUpgrade.Click += BtnSimulateUpgrade_Click;

        btnSimulateDowngrade.Text = "Simulate Downgrade";
        btnSimulateDowngrade.Location = new Point(150, 55);
        btnSimulateDowngrade.Size = new Size(140, 28);
        btnSimulateDowngrade.Click += BtnSimulateDowngrade_Click;

        btnPopulateDevices.Text = "Populate 20 Devices";
        btnPopulateDevices.Location = new Point(300, 55);
        btnPopulateDevices.Size = new Size(140, 28);
        btnPopulateDevices.Click += BtnPopulateDevices_Click;

        grpSimulate.Controls.Add(lblCurrentVersion);
        grpSimulate.Controls.Add(btnSimulateUpgrade);
        grpSimulate.Controls.Add(btnSimulateDowngrade);
        grpSimulate.Controls.Add(btnPopulateDevices);

        grpHowItWorks.Text = "How It Works";
        grpHowItWorks.Location = new Point(12, 135);
        grpHowItWorks.Size = new Size(860, 60);

        lblHowItWorks.Text = "Version tracking is automatic: SDK detects AppBinaryVersion from the executable.\nWhen a new version starts, the backend records the change in device_version_history.";
        lblHowItWorks.Location = new Point(10, 22);
        lblHowItWorks.AutoSize = true;

        grpHowItWorks.Controls.Add(lblHowItWorks);

        tabUpdates.Controls.Add(lblUpdatesDesc);
        tabUpdates.Controls.Add(grpSimulate);
        tabUpdates.Controls.Add(grpHowItWorks);

        // ============ FORM ============
        Controls.Add(pnlCenter);
        Controls.Add(pnlBottom);
        Controls.Add(pnlTop);

        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(900, 520);
        MinimumSize = new Size(700, 450);
        Name = "MainForm";
        Text = "ExeWatch .NET SDK Demo";
        StartPosition = FormStartPosition.CenterScreen;
        Load += MainForm_Load;
        FormClosing += MainForm_FormClosing;

        ResumeLayout(false);
    }

    #endregion

    // Top Panel
    private Panel pnlTop;
    private Label lblStep1;
    private Label lblApiKey;
    private TextBox edtApiKey;
    private Label lblCustomerId;
    private TextBox edtCustomerId;
    private Button btnUse;
    private Button btnDisconnect;
    private Label lblStatus;

    // Center
    private Panel pnlCenter;
    private TabControl tcFeatures;

    // Tab: Logging
    private TabPage tabLogging;
    private Label lblLoggingDesc;
    private GroupBox grpManualLog;
    private Label lblMessage;
    private TextBox edtMessage;
    private Label lblTag;
    private TextBox edtTag;
    private Button btnDebug;
    private Button btnInfo;
    private Button btnWarning;
    private Button btnError;
    private Button btnFatal;
    private GroupBox grpQuickTests;
    private Button btnGenerateLogs;
    private Button btnTestException;
    private GroupBox grpBreadcrumbs;
    private Label lblBreadcrumbsDesc;

    // Tab: Timing
    private TabPage tabTiming;
    private Label lblTimingDesc;
    private GroupBox grpTimingBasic;
    private Button btnTimingNested;
    private Button btnTimingParallel;
    private Button btnTimingLIFO;
    private Button btnTimingFormat;
    private Button btnTimingAll;
    private GroupBox grpTimingAdvanced;
    private Button btnTimingWithMeta;
    private Button btnTimingCancel;
    private Button btnTimingActive;

    // Tab: Device Info
    private TabPage tabDeviceInfo;
    private Label lblDeviceInfoDesc;
    private GroupBox grpCustomInfo;
    private Label lblCustomKey;
    private TextBox edtCustomKey;
    private Label lblCustomValue;
    private TextBox edtCustomValue;
    private Button btnSetCustomInfo;
    private Button btnSendCustomInfo;
    private GroupBox grpAutoInfo;
    private Label lblAutoInfoList;

    // Tab: User/Tags
    private TabPage tabUserTags;
    private Label lblUserDesc;
    private GroupBox grpUserCode;
    private Label lblUserCode;
    private GroupBox grpTagsCode;
    private Label lblTagsCode;

    // Tab: Metrics
    private TabPage tabMetrics;
    private Label lblMetricsDesc;
    private GroupBox grpCounters;
    private Button btnCounterIncrement;
    private Button btnCounterBatch;
    private Button btnCounterWithTag;
    private GroupBox grpGauges;
    private Button btnGaugeRecord;
    private Button btnGaugeMultiple;
    private Button btnGaugeWithTag;
    private GroupBox grpPeriodicGauges;
    private Button btnRegisterGauge;
    private Button btnUnregisterGauge;
    private Button btnMetricsAll;

    // Tab: Updates
    private TabPage tabUpdates;
    private Label lblUpdatesDesc;
    private GroupBox grpSimulate;
    private Label lblCurrentVersion;
    private Button btnSimulateUpgrade;
    private Button btnSimulateDowngrade;
    private Button btnPopulateDevices;
    private GroupBox grpHowItWorks;
    private Label lblHowItWorks;

    // Bottom Panel
    private Panel pnlBottom;
    private Label lblLogOutput;
    private TextBox txtLog;
}
