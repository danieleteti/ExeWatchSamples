object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'ExeWatch - InitialCustomDeviceInfo Sample'
  ClientHeight = 320
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object lblInfo: TLabel
    AlignWithMargins = True
    Left = 8
    Top = 8
    Width = 504
    Height = 30
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 4
    Align = alTop
    Caption = 
      'This sample shows how to use Config.InitialCustomDeviceInfo to s' +
      'end environment metadata (session type, screen resolution, etc.)' +
      ' with the very first device-info payload at startup.'
    WordWrap = True
    ExplicitWidth = 498
  end
  object Memo1: TMemo
    AlignWithMargins = True
    Left = 8
    Top = 50
    Width = 504
    Height = 262
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 8
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
end
