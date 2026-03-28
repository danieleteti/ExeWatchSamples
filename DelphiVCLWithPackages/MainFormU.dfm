object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'ExeWatch - Runtime Packages Demo'
  ClientHeight = 660
  ClientWidth = 700
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
    Width = 700
    Height = 90
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    DesignSize = (
      700
      90)
    object pnlConnection: TPanel
      Left = 8
      Top = 8
      Width = 684
      Height = 74
      Anchors = [akLeft, akTop, akRight]
      BevelOuter = bvLowered
      TabOrder = 0
      DesignSize = (
        684
        74)
      object lblStep1: TLabel
        Left = 16
        Top = 8
        Width = 165
        Height = 17
        Caption = #9654' ExeWatch Configuration'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clNavy
        Font.Height = -13
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object lblApiKey: TLabel
        Left = 16
        Top = 36
        Width = 43
        Height = 15
        Caption = 'API Key:'
      end
      object lblApiKeyValue: TLabel
        Left = 72
        Top = 36
        Width = 91
        Height = 14
        Caption = '(set in code)'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clNavy
        Font.Height = -12
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
      end
      object lblCustomerId: TLabel
        Left = 16
        Top = 54
        Width = 69
        Height = 15
        Caption = 'Customer ID:'
      end
      object lblCustomerIdValue: TLabel
        Left = 100
        Top = 54
        Width = 91
        Height = 14
        Caption = '(set in code)'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clNavy
        Font.Height = -12
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
      end
      object lblStatus: TLabel
        Left = 580
        Top = 10
        Width = 76
        Height = 15
        Anchors = [akTop, akRight]
        Caption = 'Disconnected'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object btnToggleConnect: TButton
        Left = 580
        Top = 35
        Width = 90
        Height = 27
        Anchors = [akTop, akRight]
        Caption = 'Connect'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
        TabOrder = 0
        OnClick = btnToggleConnectClick
      end
    end
  end
  object pnlCenter: TPanel
    Left = 0
    Top = 90
    Width = 700
    Height = 285
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      700
      285)
    object grpModules: TGroupBox
      Left = 8
      Top = 4
      Width = 684
      Height = 275
      Anchors = [akLeft, akTop, akRight]
      Caption = ' Step 2: Load Runtime Packages '
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 0
      DesignSize = (
        684
        275)
      object lblStep2: TLabel
        Left = 16
        Top = 24
        Width = 579
        Height = 15
        Caption = 
          'Click the buttons below to load module packages at runtime. Each' +
          ' module registers its form via LoadPackage.'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object lblLoadHint: TLabel
        Left = 16
        Top = 42
        Width = 446
        Height = 15
        Caption = 
          'All loaded modules share the same ExeWatch session, API key, use' +
          'r identity and tags.'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsItalic]
        ParentFont = False
      end
      object lblModulesLoaded: TLabel
        Left = 16
        Top = 116
        Width = 116
        Height = 15
        Caption = 'Registered modules: 0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object btnLoadCustomers: TButton
        Left = 16
        Top = 68
        Width = 170
        Height = 33
        Caption = 'Load Customers Module'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        TabOrder = 0
        OnClick = btnLoadCustomersClick
      end
      object btnLoadOrders: TButton
        Left = 196
        Top = 68
        Width = 170
        Height = 33
        Caption = 'Load Orders Module'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        TabOrder = 1
        OnClick = btnLoadOrdersClick
      end
      object lstModules: TListBox
        Left = 16
        Top = 136
        Width = 480
        Height = 125
        Anchors = [akLeft, akTop, akRight, akBottom]
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ItemHeight = 15
        ParentFont = False
        TabOrder = 2
        OnDblClick = lstModulesDblClick
      end
      object btnShowForm: TButton
        Left = 510
        Top = 136
        Width = 160
        Height = 33
        Anchors = [akTop, akRight]
        Caption = 'Show Module Form'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
        TabOrder = 3
        OnClick = btnShowFormClick
      end
      object btnUnloadAll: TButton
        Left = 510
        Top = 178
        Width = 160
        Height = 33
        Anchors = [akTop, akRight]
        Caption = 'Unload All Packages'
        Enabled = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        TabOrder = 4
        OnClick = btnUnloadAllClick
      end
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 375
    Width = 700
    Height = 285
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    DesignSize = (
      700
      285)
    object lblLogOutput: TLabel
      Left = 16
      Top = 4
      Width = 66
      Height = 15
      Caption = 'Log Output:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object memoLog: TMemo
      Left = 8
      Top = 24
      Width = 684
      Height = 252
      Anchors = [akLeft, akTop, akRight, akBottom]
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
    object btnClearLog: TButton
      Left = 632
      Top = 0
      Width = 60
      Height = 21
      Anchors = [akTop, akRight]
      Caption = 'Clear'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 1
      OnClick = btnClearLogClick
    end
  end
end
