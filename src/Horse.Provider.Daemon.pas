unit Horse.Provider.Daemon;

interface

{$IF DEFINED(HORSE_DAEMON)}


uses

  Horse.Provider.Abstract, Horse.Constants, IdHTTPWebBrokerBridge, IdSSLOpenSSL, IdContext,
  System.SyncObjs, System.SysUtils;

type

  THorseProviderIOHandleSSL = class
  private
    FKeyFile: string;
    FRootCertFile: string;
    FCertFile: string;
    FOnGetPassword: TPasswordEvent;
    FActive: Boolean;
    procedure SetCertFile(const Value: string);
    procedure SetKeyFile(const Value: string);
    procedure SetRootCertFile(const Value: string);
    procedure SetOnGetPassword(const Value: TPasswordEvent);
    procedure SetActive(const Value: Boolean);
    function GetCertFile: string;
    function GetKeyFile: string;
    function GetRootCertFile: string;
    function GetOnGetPassword: TPasswordEvent;
    function GetActive: Boolean;
  public
    constructor Create;
    property Active: Boolean read GetActive write SetActive default True;
    property CertFile: string read GetCertFile write SetCertFile;
    property RootCertFile: string read GetRootCertFile write SetRootCertFile;
    property KeyFile: string read GetKeyFile write SetKeyFile;
    property OnGetPassword: TPasswordEvent read GetOnGetPassword write SetOnGetPassword;
  end;

  THorseProvider = class(THorseProviderAbstract)
  private
    class var FPort: Integer;
    class var FHost: string;
    class var FMaxConnections: Integer;
    class var FListenQueue: Integer;
    class var FIdHTTPWebBrokerBridge: TIdHTTPWebBrokerBridge;
    class var FHorseProviderIOHandleSSL: THorseProviderIOHandleSSL;
    class function GetDefaultHTTPWebBroker: TIdHTTPWebBrokerBridge;
    class function GetDefaultHorseProviderIOHandleSSL: THorseProviderIOHandleSSL;
    class function HTTPWebBrokerIsNil: Boolean;
    class procedure OnAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String; var VUsername, VPassword: String; var VHandled: Boolean);
    class procedure OnQuerySSLPort(APort: Word; var VUseSSL: Boolean);
    class procedure SetListenQueue(const Value: Integer); static;
    class procedure SetMaxConnections(const Value: Integer); static;
    class procedure SetPort(const Value: Integer); static;
    class procedure SetIOHandleSSL(const Value: THorseProviderIOHandleSSL); static;
    class procedure SetHost(const Value: string); static;
    class function GetListenQueue: Integer; static;
    class function GetMaxConnections: Integer; static;
    class function GetPort: Integer; static;
    class function GetDefaultPort: Integer; static;
    class function GetDefaultHost: string; static;
    class function GetIOHandleSSL: THorseProviderIOHandleSSL; static;
    class function GetHost: string; static;
    class procedure InternalListen; virtual;
    class procedure InternalStopListen; virtual;
    class procedure InitServerIOHandlerSSLOpenSSL(AIdHTTPWebBrokerBridge: TIdHTTPWebBrokerBridge; FHorseProviderIOHandleSSL: THorseProviderIOHandleSSL);
  public
    constructor Create; reintroduce; overload;
    constructor Create(APort: Integer); reintroduce; overload; deprecated 'Use Port or Listen(PortValue) method to set port';
    class property Host: string read GetHost write SetHost;
    class property Port: Integer read GetPort write SetPort;
    class property MaxConnections: Integer read GetMaxConnections write SetMaxConnections;
    class property ListenQueue: Integer read GetListenQueue write SetListenQueue;
    class property IOHandleSSL: THorseProviderIOHandleSSL read GetIOHandleSSL write SetIOHandleSSL;
    class procedure Listen; overload; override;
    class procedure StopListen; override;
    class procedure Listen(APort: Integer; const AHost: string = '0.0.0.0'; ACallback: TProc<TObject> = nil); reintroduce; overload; static;
    class procedure Listen(APort: Integer; ACallback: TProc<TObject>); reintroduce; overload; static;
    class procedure Listen(AHost: string; const ACallback: TProc<TObject> = nil); reintroduce; overload; static;
    class procedure Listen(ACallback: TProc<TObject>); reintroduce; overload; static;
    class procedure Start; deprecated 'Use Listen instead';
    class procedure Stop; deprecated 'Use StopListen instead';
    class destructor UnInitialize;
  end;

{$ENDIF}

implementation

{$IF DEFINED(HORSE_DAEMON)}


uses

  Web.WebReq, Horse.WebModule, IdCustomTCPServer,
  Posix.Stdlib, Posix.SysStat, Posix.SysTypes, Posix.Unistd, Posix.Signal, Posix.Fcntl, ThirdParty.Posix.Syslog;

var
  FEvent: TEvent;
  FRunning: Boolean;
  FPID: pid_t;
  FId: Integer;

const
  EXIT_FAILURE = 1;
  EXIT_SUCCESS = 0;

procedure HandleSignals(SigNum: Integer); cdecl;
begin
  case SigNum of
    SIGTERM:
      begin
        FRunning := False;
        FEvent.SetEvent;
      end;
    SIGHUP:
      begin
        Syslog(LOG_NOTICE, 'daemon: reloading config');
      end;
  end;
end;

{ THorseProvider }

class function THorseProvider.GetDefaultHTTPWebBroker: TIdHTTPWebBrokerBridge;
begin
  if HTTPWebBrokerIsNil then
  begin
    FIdHTTPWebBrokerBridge := TIdHTTPWebBrokerBridge.Create(nil);
    FIdHTTPWebBrokerBridge.OnParseAuthentication := OnAuthentication;
    FIdHTTPWebBrokerBridge.OnQuerySSLPort := OnQuerySSLPort;
  end;
  Result := FIdHTTPWebBrokerBridge;
end;

class function THorseProvider.HTTPWebBrokerIsNil: Boolean;
begin
  Result := FIdHTTPWebBrokerBridge = nil;
end;

class procedure THorseProvider.OnQuerySSLPort(APort: Word; var VUseSSL: Boolean);
begin
  VUseSSL := (FHorseProviderIOHandleSSL <> nil) and (FHorseProviderIOHandleSSL.Active);
end;

constructor THorseProvider.Create(APort: Integer);
begin
  inherited Create;
  SetPort(APort);
end;

constructor THorseProvider.Create;
begin
  inherited Create;
end;

class function THorseProvider.GetDefaultHorseProviderIOHandleSSL: THorseProviderIOHandleSSL;
begin
  if FHorseProviderIOHandleSSL = nil then
    FHorseProviderIOHandleSSL := THorseProviderIOHandleSSL.Create;
  Result := FHorseProviderIOHandleSSL;
end;

class function THorseProvider.GetDefaultHost: string;
begin
  Result := DEFAULT_HOST;
end;

class function THorseProvider.GetDefaultPort: Integer;
begin
  Result := DEFAULT_PORT;
end;

class function THorseProvider.GetHost: string;
begin
  Result := FHost;
end;

class function THorseProvider.GetIOHandleSSL: THorseProviderIOHandleSSL;
begin
  Result := GetDefaultHorseProviderIOHandleSSL;
end;

class function THorseProvider.GetListenQueue: Integer;
begin
  Result := FListenQueue;
end;

class function THorseProvider.GetMaxConnections: Integer;
begin
  Result := FMaxConnections;
end;

class function THorseProvider.GetPort: Integer;
begin
  Result := FPort;
end;

class procedure THorseProvider.InitServerIOHandlerSSLOpenSSL(AIdHTTPWebBrokerBridge: TIdHTTPWebBrokerBridge; FHorseProviderIOHandleSSL: THorseProviderIOHandleSSL);
var
  LIOHandleSSL: TIdServerIOHandlerSSLOpenSSL;
begin
  LIOHandleSSL := TIdServerIOHandlerSSLOpenSSL.Create(AIdHTTPWebBrokerBridge);
  LIOHandleSSL.SSLOptions.CertFile := FHorseProviderIOHandleSSL.CertFile;
  LIOHandleSSL.SSLOptions.RootCertFile := FHorseProviderIOHandleSSL.FRootCertFile;
  LIOHandleSSL.SSLOptions.KeyFile := FHorseProviderIOHandleSSL.KeyFile;
  LIOHandleSSL.OnGetPassword := FHorseProviderIOHandleSSL.OnGetPassword;
  AIdHTTPWebBrokerBridge.IOHandler := LIOHandleSSL;
end;

class procedure THorseProvider.InternalListen;
var
  LIdx: Integer;
  LIdHTTPWebBrokerBridge: TIdHTTPWebBrokerBridge;
begin
  inherited;
  FEvent := TEvent.Create;
  try
    openlog(nil, LOG_PID or LOG_NDELAY, LOG_DAEMON);

    if getppid() > 1 then
    begin
      FPID := fork();
      if FPID < 0 then
        raise Exception.Create('Error forking the process');

      if FPID > 0 then
        Halt(EXIT_SUCCESS);

      if setsid() < 0 then
        raise Exception.Create('Impossible to create an independent session');

      Signal(SIGCHLD, TSignalHandler(SIG_IGN));
      Signal(SIGHUP, HandleSignals);
      Signal(SIGTERM, HandleSignals);

      FPID := fork();
      if FPID < 0 then
        raise Exception.Create('Error forking the process');

      if FPID > 0 then
        Halt(EXIT_SUCCESS);

      for LIdx := sysconf(_SC_OPEN_MAX) downto 0 do
        __close(LIdx);

      FId := __open('/dev/null', O_RDWR);
      dup(FId);
      dup(FId);

      umask(027);

      chdir('/');
    end;

    FRunning := True;
    try

      if FPort <= 0 then
        FPort := GetDefaultPort;
      if FHost.IsEmpty then
        FHost := GetDefaultHost;
      LIdHTTPWebBrokerBridge := GetDefaultHTTPWebBroker;
      WebRequestHandler.WebModuleClass := WebModuleClass;
      try

        if FMaxConnections > 0 then
        begin
          WebRequestHandler.MaxConnections := FMaxConnections;
          GetDefaultHTTPWebBroker.MaxConnections := FMaxConnections;
        end;
        if FListenQueue = 0 then
          FListenQueue := IdListenQueueDefault;

        if FHorseProviderIOHandleSSL <> nil then
          InitServerIOHandlerSSLOpenSSL(LIdHTTPWebBrokerBridge, GetDefaultHorseProviderIOHandleSSL);
        LIdHTTPWebBrokerBridge.ListenQueue := FListenQueue;
        LIdHTTPWebBrokerBridge.Bindings.Clear;
        LIdHTTPWebBrokerBridge.Bindings.Add;
        LIdHTTPWebBrokerBridge.Bindings.Items[0].IP:= FHost;
        LIdHTTPWebBrokerBridge.Bindings.Items[0].Port:= FPort;
        LIdHTTPWebBrokerBridge.DefaultPort := FPort;
        LIdHTTPWebBrokerBridge.Active := True;
        LIdHTTPWebBrokerBridge.StartListening;

        Syslog(LOG_INFO, Format(START_RUNNING, [FHost, FPort]));

      except
        on E: Exception do
          Syslog(LOG_ERR, E.ClassName + ': ' + E.Message);
      end;

      while FRunning do
        FEvent.WaitFor();

      ExitCode := EXIT_SUCCESS;
    except
      on E: Exception do
      begin
        Syslog(LOG_ERR, 'Error: ' + E.Message);
        ExitCode := EXIT_FAILURE;
      end;
    end;

    Syslog(LOG_NOTICE, 'daemon stopped');
    closelog();
  finally
    FEvent.Free;
  end;

end;

class procedure THorseProvider.InternalStopListen;
begin
  if not HTTPWebBrokerIsNil then
  begin
    GetDefaultHTTPWebBroker.StopListening;
    FRunning := False;
  end
  else
    raise Exception.Create('Horse not listen');
end;

class procedure THorseProvider.Start;
begin
  SetOnListen(
    procedure(Sender: TObject)
    begin
      Writeln(Format(START_RUNNING, [FHost, FPort]));
      Write('Press return to stop ...');
      ReadLn;
      StopListen;
    end);
  Listen;
end;

class procedure THorseProvider.Stop;
begin
  StopListen;
end;

class procedure THorseProvider.StopListen;
begin
  InternalStopListen;
end;

class procedure THorseProvider.Listen;
begin
  InternalListen;;
end;

class procedure THorseProvider.Listen(APort: Integer; const AHost: string; ACallback: TProc<TObject>);
begin
  SetPort(APort);
  SetHost(AHost);
  SetOnListen(ACallback);
  InternalListen;
end;

class procedure THorseProvider.Listen(AHost: string; const ACallback: TProc<TObject>);
begin
  Listen(FPort, AHost, ACallback);
end;

class procedure THorseProvider.Listen(ACallback: TProc<TObject>);
begin
  Listen(FPort, FHost, ACallback);
end;

class procedure THorseProvider.Listen(APort: Integer; ACallback: TProc<TObject>);
begin
  Listen(APort, FHost, ACallback);
end;

class procedure THorseProvider.OnAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String; var VUsername, VPassword: String; var VHandled: Boolean);
begin
  VHandled := True;
end;

class procedure THorseProvider.SetHost(const Value: string);
begin
  FHost := Value;
end;

class procedure THorseProvider.SetIOHandleSSL(const Value: THorseProviderIOHandleSSL);
begin
  FHorseProviderIOHandleSSL := Value;
end;

class procedure THorseProvider.SetListenQueue(const Value: Integer);
begin
  FListenQueue := Value;
end;

class procedure THorseProvider.SetMaxConnections(const Value: Integer);
begin
  FMaxConnections := Value;
end;

class procedure THorseProvider.SetPort(const Value: Integer);
begin
  FPort := Value;
end;

class destructor THorseProvider.UnInitialize;
begin
  FreeAndNil(FIdHTTPWebBrokerBridge);
  if FEvent <> nil then
    FreeAndNil(FEvent);
  if FHorseProviderIOHandleSSL <> nil then
    FreeAndNil(FHorseProviderIOHandleSSL);
end;

{ THorseProviderIOHandleSSL }

constructor THorseProviderIOHandleSSL.Create;
begin
  FActive := True;
end;

function THorseProviderIOHandleSSL.GetActive: Boolean;
begin
  Result := FActive;
end;

function THorseProviderIOHandleSSL.GetCertFile: string;
begin
  Result := FCertFile;
end;

function THorseProviderIOHandleSSL.GetKeyFile: string;
begin
  Result := FKeyFile;
end;

function THorseProviderIOHandleSSL.GetOnGetPassword: TPasswordEvent;
begin
  Result := FOnGetPassword;
end;

function THorseProviderIOHandleSSL.GetRootCertFile: string;
begin
  Result := FRootCertFile;
end;

procedure THorseProviderIOHandleSSL.SetActive(const Value: Boolean);
begin
  FActive := Value;
end;

procedure THorseProviderIOHandleSSL.SetCertFile(const Value: string);
begin
  FCertFile := Value;
end;

procedure THorseProviderIOHandleSSL.SetKeyFile(const Value: string);
begin
  FKeyFile := Value;
end;

procedure THorseProviderIOHandleSSL.SetOnGetPassword(const Value: TPasswordEvent);
begin
  FOnGetPassword := Value;
end;

procedure THorseProviderIOHandleSSL.SetRootCertFile(const Value: string);
begin
  FRootCertFile := Value;
end;

{$ENDIF}

end.
