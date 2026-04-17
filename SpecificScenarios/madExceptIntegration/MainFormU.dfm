object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'ExeWatch + madExcept integration sample'
  ClientHeight = 420
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
    420)
  TextHeight = 15
  object lblInfo: TLabel
    Left = 16
    Top = 12
    Width = 688
    Height = 30
    AutoSize = False
    Caption = 
      'Click a button to generate an event. madExcept resolves the stac' +
      'k, ExeWatch receives and stores it.'
    WordWrap = True
  end
  object btnRaiseException: TButton
    Left = 16
    Top = 56
    Width = 160
    Height = 33
    Caption = 'Raise Exception'
    TabOrder = 0
    OnClick = btnRaiseExceptionClick
  end
  object btnRaiseAV: TButton
    Left = 184
    Top = 56
    Width = 160
    Height = 33
    Caption = 'Raise Access Violation'
    TabOrder = 1
    OnClick = btnRaiseAVClick
  end
  object btnLogInfo: TButton
    Left = 352
    Top = 56
    Width = 160
    Height = 33
    Caption = 'Log Info (baseline)'
    TabOrder = 2
    OnClick = btnLogInfoClick
  end
  object Memo1: TMemo
    Left = 16
    Top = 104
    Width = 688
    Height = 300
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 3
  end
end
