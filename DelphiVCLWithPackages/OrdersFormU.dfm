object OrdersForm: TOrdersForm
  Left = 0
  Top = 0
  Caption = 'Orders Module (loaded from BPL)'
  ClientHeight = 400
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 520
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    Color = clTeal
    ParentBackground = False
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 10
      Width = 220
      Height = 20
      Caption = 'Orders Module (from BPL)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -15
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object pnlClient: TPanel
    Left = 0
    Top = 41
    Width = 520
    Height = 359
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      520
      359)
    object lstOrders: TListBox
      Left = 16
      Top = 8
      Width = 355
      Height = 340
      Anchors = [akLeft, akTop, akRight, akBottom]
      ItemHeight = 15
      TabOrder = 0
    end
    object pnlButtons: TPanel
      Left = 384
      Top = 8
      Width = 125
      Height = 340
      Anchors = [akTop, akRight, akBottom]
      BevelOuter = bvNone
      TabOrder = 1
      object btnCreateOrder: TButton
        Left = 0
        Top = 0
        Width = 125
        Height = 33
        Caption = 'Create Order'
        TabOrder = 0
        OnClick = btnCreateOrderClick
      end
      object btnProcessOrder: TButton
        Left = 0
        Top = 40
        Width = 125
        Height = 33
        Caption = 'Process Order'
        TabOrder = 1
        OnClick = btnProcessOrderClick
      end
      object btnCancelOrder: TButton
        Left = 0
        Top = 80
        Width = 125
        Height = 33
        Caption = 'Cancel Order'
        TabOrder = 2
        OnClick = btnCancelOrderClick
      end
      object btnSimulateSlowQuery: TButton
        Left = 0
        Top = 140
        Width = 125
        Height = 33
        Caption = 'Slow Query'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clPurple
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
        TabOrder = 3
        OnClick = btnSimulateSlowQueryClick
      end
    end
  end
end
