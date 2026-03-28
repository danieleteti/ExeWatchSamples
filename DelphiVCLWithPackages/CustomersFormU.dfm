object CustomersForm: TCustomersForm
  Left = 0
  Top = 0
  Caption = 'Customers Module (loaded from BPL)'
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
    Color = clNavy
    ParentBackground = False
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 10
      Width = 250
      Height = 20
      Caption = 'Customers Module (from BPL)'
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
    object lstCustomers: TListBox
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
      object btnAddCustomer: TButton
        Left = 0
        Top = 0
        Width = 125
        Height = 33
        Caption = 'Add Customer'
        TabOrder = 0
        OnClick = btnAddCustomerClick
      end
      object btnRemoveCustomer: TButton
        Left = 0
        Top = 40
        Width = 125
        Height = 33
        Caption = 'Remove'
        TabOrder = 1
        OnClick = btnRemoveCustomerClick
      end
      object btnSearchCustomer: TButton
        Left = 0
        Top = 80
        Width = 125
        Height = 33
        Caption = 'Search'
        TabOrder = 2
        OnClick = btnSearchCustomerClick
      end
      object btnSimulateError: TButton
        Left = 0
        Top = 140
        Width = 125
        Height = 33
        Caption = 'Simulate Error'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clRed
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
        TabOrder = 3
        OnClick = btnSimulateErrorClick
      end
    end
  end
end
