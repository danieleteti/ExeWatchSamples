object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'ExeWatch - Breadcrumbs usage sample'
  ClientHeight = 460
  ClientWidth = 760
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  DesignSize = (
    760
    460)
  TextHeight = 15
  object lblInfo: TLabel
    Left = 16
    Top = 12
    Width = 728
    Height = 30
    AutoSize = False
    Caption = 
      'Click the buttons in order. Breadcrumbs accumulate per-thread; a' +
      'ttached only to Error/Fatal logs.'
    WordWrap = True
  end
  object btnOpenSettings: TButton
    Left = 16
    Top = 56
    Width = 175
    Height = 33
    Caption = '1. Open Settings (navigation)'
    TabOrder = 0
    OnClick = btnOpenSettingsClick
  end
  object btnSaveCaught: TButton
    Left = 200
    Top = 56
    Width = 175
    Height = 33
    Caption = '2. Save - caught exception'
    TabOrder = 1
    OnClick = btnSaveCaughtClick
  end
  object btnSimulateCrash: TButton
    Left = 384
    Top = 56
    Width = 175
    Height = 33
    Caption = '3. Crash - unhandled exception'
    TabOrder = 2
    OnClick = btnSimulateCrashClick
  end
  object btnLogInfo: TButton
    Left = 568
    Top = 56
    Width = 175
    Height = 33
    Caption = '4. Info log (no breadcrumbs)'
    TabOrder = 3
    OnClick = btnLogInfoClick
  end
  object Memo1: TMemo
    Left = 16
    Top = 104
    Width = 728
    Height = 340
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 4
  end
end
