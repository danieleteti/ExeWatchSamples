// ***************************************************************************
//
// ExeWatch - DMVCFramework Integration Sample
//
// WebModule: configures the MVC engine, template engine, middleware,
// and the global ExeWatch exception handler.
//
// ***************************************************************************

unit WebModuleU;

interface

uses
  System.SysUtils,
  System.Classes,
  Web.HTTPApp,
  MVCFramework;

type
  TMyWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    fMVC: TMVCEngine;
  end;

var
  WebModuleClass: TComponentClass = TMyWebModule;

implementation

{$R *.dfm}

uses
  ControllerU,
  System.IOUtils,
  MVCFramework.Commons,
  MVCFramework.Logger,
  MVCFramework.Serializer.URLEncoded,
  MVCFramework.View.Renderers.TemplatePro,
  MVCFramework.Middleware.Redirect,
  MVCFramework.Middleware.StaticFiles,
  MVCFramework.HTMX,
  ExeWatchSDKv1;

procedure TMyWebModule.WebModuleCreate(Sender: TObject);
var
  LWwwPath: string;
begin
  fMVC := TMVCEngine.Create(Self,
    procedure(Config: TMVCConfig)
    begin
      Config[TMVCConfigKey.DefaultContentType] := TMVCMediaType.TEXT_HTML;
      Config[TMVCConfigKey.DefaultContentCharset] := TMVCConstants.DEFAULT_CONTENT_CHARSET;
      Config[TMVCConfigKey.AllowUnhandledAction] := 'false';
      Config[TMVCConfigKey.LoadSystemControllers] := 'true';
      Config[TMVCConfigKey.DefaultViewFileExtension] := 'html';
      Config[TMVCConfigKey.ViewPath] := TPath.Combine(AppPath, 'templates');
      Config[TMVCConfigKey.ViewCache] := 'false';
      Config[TMVCConfigKey.MaxEntitiesRecordCount] := IntToStr(TMVCConstants.MAX_RECORD_COUNT);
      Config[TMVCConfigKey.ExposeServerSignature] := 'false';
      Config[TMVCConfigKey.ExposeXPoweredBy] := 'true';
    end);

  // Static files (CSS, JS, images)
  LWwwPath := TPath.Combine(AppPath, 'www');

  // Controllers
  fMVC.AddController(TWebController);

  // Template engine
  fMVC.SetViewEngine(TMVCTemplateProViewEngine);

  // URL-encoded form support
  fMVC.AddSerializer(TMVCMediaType.APPLICATION_FORM_URLENCODED,
    TMVCURLEncodedSerializer.Create(nil));

  // Middleware
  fMVC.AddMiddleware(TMVCRedirectMiddleware.Create(['/'], '/web'));
  fMVC.AddMiddleware(TMVCStaticFilesMiddleware.Create('/static', LWwwPath));

  // Global exception handler: log unhandled errors to ExeWatch
  fMVC.SetExceptionHandler(
    procedure(E: Exception; SelectedController: TMVCController;
      WebContext: TWebContext; var ExceptionHandled: Boolean)
    begin
      EW.IncrementCounter('http.errors', 1);
      EW.ErrorWithException(E, 'unhandled');

      if (SelectedController <> nil) and WebContext.Request.IsHTMX then
      begin
        // Return error as HTML fragment for HTMX to swap in
        SelectedController.Render(
          '<div class="alert alert-danger">' +
          '<strong>Error:</strong> ' + E.Message +
          '</div>');
        WebContext.Response.StatusCode := 500;
        ExceptionHandled := True;
      end;
    end);
end;

procedure TMyWebModule.WebModuleDestroy(Sender: TObject);
begin
  fMVC.Free;
end;

end.
