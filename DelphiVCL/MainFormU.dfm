object MainForm: TMainForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'ExeWatch :: VCL Sample'
  ClientHeight = 644
  ClientWidth = 704
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  DesignSize = (
    704
    644)
  TextHeight = 15
  object lblLog: TLabel
    Left = 8
    Top = 455
    Width = 63
    Height = 15
    Caption = 'Activity Log'
  end
  object grpLogging: TGroupBox
    Left = 8
    Top = 66
    Width = 688
    Height = 70
    Caption = ' Logging '
    TabOrder = 0
    object btnDebug: TButton
      Left = 16
      Top = 26
      Width = 120
      Height = 33
      Caption = 'Debug'
      TabOrder = 0
      OnClick = btnDebugClick
    end
    object btnInfo: TButton
      Left = 148
      Top = 26
      Width = 120
      Height = 33
      Caption = 'Info'
      TabOrder = 1
      OnClick = btnInfoClick
    end
    object btnWarning: TButton
      Left = 280
      Top = 26
      Width = 120
      Height = 33
      Caption = 'Warning'
      TabOrder = 2
      OnClick = btnWarningClick
    end
    object btnError: TButton
      Left = 412
      Top = 26
      Width = 120
      Height = 33
      Caption = 'Error'
      TabOrder = 3
      OnClick = btnErrorClick
    end
    object btnFatal: TButton
      Left = 544
      Top = 26
      Width = 120
      Height = 33
      Caption = 'Fatal'
      TabOrder = 4
      OnClick = btnFatalClick
    end
  end
  object grpTiming: TGroupBox
    Left = 8
    Top = 142
    Width = 336
    Height = 70
    Caption = ' Timing '
    TabOrder = 1
    object btnTiming: TButton
      Left = 173
      Top = 26
      Width = 145
      Height = 33
      Caption = 'Measure Operation'
      TabOrder = 0
      OnClick = btnTimingClick
    end
    object btnSingleTiming: TButton
      Left = 16
      Top = 26
      Width = 145
      Height = 32
      Caption = 'Single Operation'
      TabOrder = 1
      OnClick = btnSingleTimingClick
    end
  end
  object grpBreadcrumbs: TGroupBox
    Left = 360
    Top = 142
    Width = 336
    Height = 70
    Caption = ' Breadcrumbs + Error '
    TabOrder = 2
    object btnBreadcrumbsError: TButton
      Left = 16
      Top = 26
      Width = 260
      Height = 33
      Caption = 'Trigger Error with Breadcrumbs'
      TabOrder = 0
      OnClick = btnBreadcrumbsErrorClick
    end
  end
  object grpUser: TGroupBox
    Left = 8
    Top = 218
    Width = 336
    Height = 70
    Caption = ' User Identity '
    TabOrder = 3
    object btnSetUser: TButton
      Left = 16
      Top = 26
      Width = 145
      Height = 33
      Caption = 'Set User'
      TabOrder = 0
      OnClick = btnSetUserClick
    end
    object btnClearUser: TButton
      Left = 173
      Top = 26
      Width = 145
      Height = 33
      Caption = 'Clear User'
      TabOrder = 1
      OnClick = btnClearUserClick
    end
  end
  object grpTags: TGroupBox
    Left = 360
    Top = 218
    Width = 336
    Height = 70
    Caption = ' Additional Tags '
    TabOrder = 4
    object btnSetTags: TButton
      Left = 16
      Top = 26
      Width = 145
      Height = 33
      Caption = 'Set Tags'
      TabOrder = 0
      OnClick = btnSetTagsClick
    end
    object btnClearTags: TButton
      Left = 173
      Top = 26
      Width = 145
      Height = 33
      Caption = 'Clear Tags'
      TabOrder = 1
      OnClick = btnClearTagsClick
    end
  end
  object grpMetrics: TGroupBox
    Left = 8
    Top = 294
    Width = 688
    Height = 70
    Caption = ' Metrics '
    TabOrder = 5
    object btnIncrementCounter1: TButton
      Left = 16
      Top = 26
      Width = 161
      Height = 33
      Caption = '+1 Counter (orders.new)'
      TabOrder = 0
      OnClick = btnIncrementCounter1Click
    end
    object btnRecordGauge: TButton
      Left = 568
      Top = 26
      Width = 102
      Height = 33
      Caption = 'Record Gauge'
      TabOrder = 1
      OnClick = btnRecordGaugeClick
    end
    object btnIncrementCounter2: TButton
      Left = 183
      Top = 26
      Width = 161
      Height = 33
      Caption = '+1 Counter (orders.shipped)'
      TabOrder = 2
      OnClick = btnIncrementCounter2Click
    end
    object btnCounter3: TButton
      Left = 350
      Top = 26
      Width = 161
      Height = 33
      Caption = '+1 Counter (orders.billed)'
      TabOrder = 3
      OnClick = btnCounter3Click
    end
  end
  object grpThreadSafety: TGroupBox
    Left = 8
    Top = 370
    Width = 688
    Height = 70
    Caption = ' Thread Safety '
    TabOrder = 9
    object btnConcurrentTimings: TButton
      Left = 16
      Top = 26
      Width = 320
      Height = 33
      Caption = 'Concurrent Timings (8 threads, same id)'
      TabOrder = 0
      OnClick = btnConcurrentTimingsClick
    end
  end
  object btnClearLog: TButton
    Left = 632
    Top = 445
    Width = 64
    Height = 25
    Caption = 'Clear'
    TabOrder = 6
    OnClick = btnClearLogClick
  end
  object Memo1: TMemo
    Left = 8
    Top = 476
    Width = 688
    Height = 160
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 7
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 704
    Height = 49
    Align = alTop
    BevelOuter = bvNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI Light'
    Font.Style = []
    ParentFont = False
    TabOrder = 8
    object Shape1: TShape
      Left = 0
      Top = 0
      Width = 704
      Height = 49
      Align = alClient
      Brush.Color = 9070355
      Pen.Color = 15901513
      Pen.Style = psClear
      ExplicitLeft = 320
      ExplicitTop = -16
      ExplicitWidth = 65
      ExplicitHeight = 65
    end
    object Label1: TLabel
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 698
      Height = 43
      Align = alClient
      Alignment = taCenter
      Caption = 'ExeWatch | DelphiVCL Sample'
      Color = clBlack
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -21
      Font.Name = 'Segoe UI Light'
      Font.Style = []
      ParentColor = False
      ParentFont = False
      Layout = tlCenter
      ExplicitWidth = 263
      ExplicitHeight = 30
    end
  end
end
