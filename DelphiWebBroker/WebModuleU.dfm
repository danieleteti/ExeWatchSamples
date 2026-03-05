object WebModule1: TWebModule1
  Actions = <
    item
      Default = True
      Name = 'DefaultHandler'
      PathInfo = '/'
      OnAction = WebModule1DefaultHandlerAction
    end
    item
      Name = 'Health'
      PathInfo = '/health'
      OnAction = WebModule1HealthAction
    end
    item
      Name = 'APIInfo'
      PathInfo = '/api/info'
      OnAction = WebModule1APIInfoAction
    end
    item
      Name = 'APIEcho'
      PathInfo = '/api/echo'
      OnAction = WebModule1APIEchoAction
    end
    item
      Name = 'APITime'
      PathInfo = '/api/time'
      OnAction = WebModule1APITimeAction
    end
    item
      Name = 'APIDelay'
      PathInfo = '/api/delay'
      OnAction = WebModule1APIDelayAction
    end>
  Height = 230
  Width = 415
end
