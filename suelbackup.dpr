program suelbackup;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  inifiles,
  Windows,
  System.Threading,
  System.SyncObjs,
  System.IOUtils,
  System.Net.URLClient,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.Mime;

procedure informacoes;
begin
  Writeln('How To use: ');
  Writeln('Crie um arquivo com o nome setting.ini');
  Writeln('com a seguinte estrutura');
  Writeln('');
  Writeln('[SUELBACKUP]');
  Writeln('database=nome_do_seu_banco');
  Writeln('database_user=usuario');
  Writeln('database_password=senha se houver, deixe em branco se n�o houver');
  Writeln('webhook=seuwebhook');
  Writeln('mysqldir=diret�rio onde tem o mysqldump.exe');
  Writeln('file_path=caminho + nome do arquivo onde ser� salvo o arquivo tempor�rio, se em branco, salva em /tmp/backup.sql');
  Writeln('');
  readln;
end;

function TestConfigurationFile(): Boolean;
var
  ini: TIniFile;
begin
  Writeln(ExtractFilePath(ParamStr(0)));
  ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'setting.ini');
  result := ini.SectionExists('SUELBACKUP') and
    (Trim(ini.ReadString('SUELBACKUP', 'database', '')) <> String.Empty) and
    (Trim(ini.ReadString('SUELBACKUP', 'database_user', '')) <> String.Empty)
    and (Trim(ini.ReadString('SUELBACKUP', 'webhook', '')) <> String.Empty) and
    (Trim(ini.ReadString('SUELBACKUP', 'mysqldir', '')) <> String.Empty)
end;

function GetDosOutput(CommandLine: string; Work: string = 'C:\'): string;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutPipeRead, StdOutPipeWrite: THandle;
  WasOK: Boolean;
  Buffer: array [0 .. 255] of AnsiChar;
  BytesRead: Cardinal;
  WorkDir: string;
  Handle: Boolean;
begin
  result := '';
  with SA do
  begin
    nLength := SizeOf(SA);
    bInheritHandle := True;
    lpSecurityDescriptor := nil;
  end;
  CreatePipe(StdOutPipeRead, StdOutPipeWrite, @SA, 0);
  try
    with SI do
    begin
      FillChar(SI, SizeOf(SI), 0);
      cb := SizeOf(SI);
      dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
      wShowWindow := SW_HIDE;
      hStdInput := GetStdHandle(STD_INPUT_HANDLE); // don't redirect stdin
      hStdOutput := StdOutPipeWrite;
      hStdError := StdOutPipeWrite;
    end;
    WorkDir := Work;
    Handle := CreateProcess(nil, PChar('cmd.exe /C ' + CommandLine), nil, nil,
      True, 0, nil, PChar(WorkDir), SI, PI);
    CloseHandle(StdOutPipeWrite);
    if Handle then
      try
        repeat
          WasOK := ReadFile(StdOutPipeRead, Buffer, 255, BytesRead, nil);
          if BytesRead > 0 then
          begin
            Buffer[BytesRead] := #0;
            result := result + Buffer;
          end;
        until not WasOK or (BytesRead = 0);
        WaitForSingleObject(PI.hProcess, INFINITE);
      finally
        CloseHandle(PI.hThread);
        CloseHandle(PI.hProcess);
      end;
  finally
    CloseHandle(StdOutPipeRead);
  end;
end;


function DateTimeToUNIXTimeFAST(DelphiTime : TDateTime): LongWord;
begin
  Result := Round((DelphiTime - 25569) * 86400);
end;
var
  ini: TIniFile;
  database: string;
  user: string;
  password: string;
  webhook: string;
  mysqlDir: string;
  dirToSave: string;
  timestamp: TDateTime;
  filepath : string;

  NetHTTPClient: TNetHTTPClient;
  mime: TMultipartFormData;

begin
  try
    if System.SysUtils.FileExists('setting.ini') then
    begin
      if TestConfigurationFile() then
      begin
        ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'setting.ini');
        database := ini.ReadString('SUELBACKUP', 'database', '');
        user := ini.ReadString('SUELBACKUP', 'database_user', 'root');
        password := ini.ReadString('SUELBACKUP', 'database_password', '');
        webhook := ini.ReadString('SUELBACKUP', 'webhook', '');
        mysqlDir := ini.ReadString('SUELBACKUP', 'mysqldir', 'C:\xampp\mysql\bin');
        dirToSave := ini.ReadString('SUELBACKUP', 'dirtosave', TPath.GetTempPath);
        ini.Free;
        timestamp := Now;
          Writeln(GetDosOutput(Format('%s\mysqldump.exe --compact --compress --skip-lock-tables --lock-tables=false --databases %s --user=%s --password=%s  >> %sbackup_%d.sql',
            [mysqlDir, database, user, password, dirToSave, DateTimeToUNIXTimeFAST(timestamp)])));
        filepath := dirToSave + 'backup_' + IntToStr(DateTimeToUNIXTimeFAST(timestamp)) +'.sql';
        if TFile.Exists(filepath) then
        begin
             mime := TMultipartFormData.Create(false);
             mime.AddFile('sql_backup',filepath);
             NetHTTPClient :=  TNetHTTPClient.Create(nil);
             NetHTTPClient.Post(webhook,mime);
             mime.Free;
             NetHTTPClient.Free;
        end;
      end
      else
      begin
        Writeln('Verifique o arquivo de configura��o, alguma coisa t� errada!');
        Writeln('');
        informacoes;
      end;
    end
    else
    begin
      Writeln('Arquivo de configura��o n�o foi encontrado...');
      Writeln('');
      informacoes();
    end;
    if ParamStr(1) = '-test' then
    begin
      readln;
    end
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ReadLn;
    end;
  end;

end.

