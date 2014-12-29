unit IE;

interface

uses
  SysUtils;

procedure IERun;
procedure ShowBanner;

implementation

uses
  Compiler, Lang, MiscUtils;
  
type

  TCommandHandler = function: Integer;
  
  TCommandHandlerRec = record
    Command: string;
    ShortCmd: string;
    Handler: TCommandHandler;
  end;

procedure ShowBanner;
begin
  LogInfo('     A parser for 2d language --', []);
  LogInfo('              introduced by ohmega@cbv.net', []);
  LogInfo('', []);
end;

function HandleHelp: Integer;
begin
  Log('compile(c)      | compile a 2d file.', []);
  Log('  compile file-name', []);
  Log('----------------|----------------------------------------', []);
  Log('exec(x)         | execute a module.', []);
  Log('  exec module-name module-params', []);
  Log('  e.g. exec stamp (Inr (), Inl())', []);
  Log('----------------|----------------------------------------', []);
  Log('decompile(d)    | decompile a module.', []);
  Log('  decompile module-name', []);
  Log('================|========================================', []);
  Log('list(l)         | list all of the modules.', []);
  Log('  decompile module-name', []);
  Log('----------------|----------------------------------------', []);
  Log('erase(r)        | erase a module.', []);
  Log('  erase module-name', []);
  Log('  erase *       | erase all modules', []);
  Log('================|========================================', []);
  Log('bye(q)          | say bye-bye to me.', []);
  Log('help(?)         | view this help.', []);
  
  Result := 0;
end;

function HandleCompile: Integer;
var
  FileName: string;
begin
  Result := -1;
  FileName := Trim(TheStr);
  if not FileExists(FileName) then
  begin
    LogError('file "%s" not exists.', [FileName]);
    Exit;
  end;

  if UpperCase(ExtractFileExt(FileName)) = '.2D' then
    Result := Compile(FileName)
  else
    Result := CompileL2d(FileName);
end;

function HandleList: Integer;
var
  Module: PModule;
begin
  Result := 0;
  Module := gModule.Next;
  if Module = nil then
  begin
    Log('I do not know any modules at present.', []);
    Exit;
  end;

  Log('---  a list of modules  ---', []);

  while Module <> nil do
  begin
    Log('%s' + #9 + '  %2d instances' + #9 + '  %5d bytes', [Module.Name, Module.Depth, SizeOfModule(Module)]);
    Module := Module.Next;
  end;
end;

function HandleExecute: Integer;
var
  Module: PModule;
  Expr: PExpr;
  V1, V2, Output: PValue;
begin
  Result := -1;
  NextToken;
  Module := FindModule(CurToken);
  if Module = nil then
  begin
    if Length(CurToken) > 0 then
      LogError('module "%s" not exists.', [CurToken])
    else
      LogError('please specify a module you want to execute.', []);
    Exit;
  end;

  Expr := nil;
  CompileExpr(Expr);
  V1 := CaptureValue(ExprToValue(Expr));
  DisposeExpr(Expr);
  V2 := nil;
  NextToken;
  if CurToken = ',' then
  begin
    CompileExpr(Expr);
//  LogWarning(DisExpr(Expr), []);
    V2 := CaptureValue(ExprToValue(Expr));
    DisposeExpr(Expr);
  end
  else if CurToken <> '' then
  begin
    LogError('what do you mean by "%s"?', [CurToken]);
  end;

  Output := nil;
  ExcecuteModule(Module, V1, V2, Output);
  Log('you get: %s', [DisValue(Output)]);

  ReleaseValue(Output);
  ReleaseValue(V1);
  ReleaseValue(V2);
end;

function HandleDecompile: Integer;
var
  Module: PModule;
begin
  Result := -1;
  NextToken;
  Module := FindModule(CurToken);
  if Module = nil then
  begin
    if Length(CurToken) > 0 then
      LogError('module "%s" not exists.', [CurToken])
    else
      LogError('please specify a module you want to decompile.', []);
    Exit;
  end;

  LogWarning('sorry, DECOMPILE not implemented yet.', []);
end;

function HandleErase: Integer;
var
  Module: PModule;
begin
  Result := -1;
  NextToken;
  if CurToken = '*' then
  begin
    LogWarning('erase all of the modules stored in memory...', []);
    GlobalEraseAll;
    Exit;
  end;

  Module := FindModule(CurToken);
  if Module = nil then
  begin
    if Length(CurToken) > 0 then
      LogError('module "%s" not exists.', [CurToken])
    else
      LogError('please specify a module you want to erase.', []);
    Exit;
  end;

  GlobalDisposeModule(Module);
  Log('I have erased module "%s" from my memory.', [CurToken])
end;

const
  CommandHandlers: array [0..5] of TCommandHandlerRec =
  ((Command: 'HELP'; ShortCmd: '?H'; Handler: HandleHelp),
   (Command: 'COMPILE'; ShortCmd: 'C'; Handler: HandleCompile),
   (Command: 'EXEC'; ShortCmd: 'X'; Handler: HandleExecute),
   (Command: 'DECOMPILE'; ShortCmd: 'D'; Handler: HandleDecompile),
   (Command: 'ERASE'; ShortCmd: 'R'; Handler: HandleErase),
   (Command: 'LIST'; ShortCmd: 'L'; Handler: HandleList));

procedure IERun;
var
  command: string;
  cmd: string;
//F: TextFile;
  i: Integer;
label
  NextCmd;
begin
  LogWarning('I (a 2d interactive environment) am ready for your commands.', []);
  Log('Type "help" or "?" for help.', []);

  repeat
NextCmd:
    Write(']');
    Readln(command);
    BeginFetchEle(command);
    NextToken;
    cmd := UpperCase(CurToken);
    if cmd = '' then
      Continue;
      
    for i := 0 to High(CommandHandlers) do
    begin
      if (cmd = CommandHandlers[i].Command) or (Pos(cmd, CommandHandlers[i].ShortCmd) > 0) then
      begin
        CommandHandlers[i].Handler;
        goto NextCmd;
      end;
    end;

    if (cmd = 'Q') or (cmd = 'BYE') or (cmd = 'QUIT') or (cmd = 'EXIT') then
      Break
    else begin
      LogError('I cannot understand your command: ' + CurToken, []);
    end;
  until False;
end;

end.
