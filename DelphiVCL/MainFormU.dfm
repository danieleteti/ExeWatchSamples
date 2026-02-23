object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'ExeWatch :: VCL Sample'
  ClientHeight = 685
  ClientWidth = 720
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  DesignSize = (
    720
    685)
  TextHeight = 15
  object lblLog: TLabel
    Left = 16
    Top = 327
    Width = 63
    Height = 15
    Caption = 'Activity Log'
  end
  object grpLogging: TGroupBox
    Left = 16
    Top = 8
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
    Left = 16
    Top = 86
    Width = 336
    Height = 70
    Caption = ' Timing '
    TabOrder = 1
    object btnTiming: TButton
      Left = 16
      Top = 26
      Width = 200
      Height = 33
      Caption = 'Measure Operation'
      TabOrder = 0
      OnClick = btnTimingClick
    end
  end
  object grpBreadcrumbs: TGroupBox
    Left = 368
    Top = 86
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
    Left = 16
    Top = 164
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
    Left = 368
    Top = 164
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
    Left = 16
    Top = 242
    Width = 688
    Height = 70
    Caption = ' Metrics '
    TabOrder = 5
    object btnIncrementCounter: TButton
      Left = 16
      Top = 26
      Width = 160
      Height = 33
      Caption = 'Increment Counter'
      TabOrder = 0
      OnClick = btnIncrementCounterClick
    end
    object btnRecordGauge: TButton
      Left = 188
      Top = 26
      Width = 160
      Height = 33
      Caption = 'Record Gauge'
      TabOrder = 1
      OnClick = btnRecordGaugeClick
    end
  end
  object btnClearLog: TButton
    Left = 640
    Top = 322
    Width = 64
    Height = 25
    Caption = 'Clear'
    TabOrder = 6
    OnClick = btnClearLogClick
  end
  object Memo1: TMemo
    Left = 16
    Top = 348
    Width = 688
    Height = 325
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
    ExplicitHeight = 320
  end
  object Button1: TButton
    Left = 360
    Top = 322
    Width = 75
    Height = 25
    Caption = 'Button1'
    TabOrder = 8
  end
end
