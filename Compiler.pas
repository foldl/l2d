unit Compiler;

interface

uses
  SysUtils, Lang, Types;

var
  CurToken: string;
  Backup: string;
  TheStr: string;

function Compile(FileName: string): Integer;
function CompileL2d(FileName: string): Integer;
function CompileExpr(var Expr: PExpr; const bFetchNew: Boolean = True): Integer;

// tokener
function  NextToken: Boolean;
procedure BeginFetchEle(const Str: string);

implementation

uses
  MiscUtils;

var
  RowNum, ColNum: Integer;
  Map: array of Char;

procedure CharError(Expected, But: string; X, Y: Integer);
begin
  LogError('at (%d, %d), "%s" expected, but "%s" found.', [Y + 1, X + 1, Expected, But]);
end;

procedure CharWarning(Expected, But: string; X, Y: Integer);
begin
  LogWarning('at (%d, %d), "%s" expected, but "%s" found.', [Y + 1, X + 1, Expected, But]);
end;

procedure ErrorInBlock(Error: string; Block: PBlock);
begin
  LogError('%s in block at (%d, %d).', [Error,
            ((Block.LT.Y + Block.RB.Y) div 2) + 1,
            ((Block.LT.X + Block.RB.X) div 2) + 1]);
end;

procedure WarningInBlock(Error: string; Block: PBlock);
begin
  LogWarning('%s in block at (%d, %d).', [Error,
            ((Block.LT.Y + Block.RB.Y) div 2) + 1,
            ((Block.LT.X + Block.RB.X) div 2) + 1]);
end;

procedure WireErrorInModule(Error: string; Module: PModule; const X, Y: Integer);
begin
  LogError('at (%d, %d), wire error in module "%s": %s',
           [Y + 1, X + 1, Module.Name, Error]);
end;

procedure ExpectedInBlock(Expected, But: string; Block: PBlock);
begin
  ErrorInBlock(Format('"%s" expected but "%s" found', [Expected, But]), Block);
end;

function XY2Index(const X, Y: Integer): Integer; overload;
begin
  Result := X + Y * ColNum;
end;

function XY2Index(const P: TPoint): Integer; overload;
begin
  Result := XY2Index(P.X, P.Y);
end;

function CharAt(const X, Y: Integer): Char; overload;
begin
  Result := Map[XY2Index(X, Y)];
end;

function CharAt(const P: TPoint): Char; overload;
begin
  Result := Map[XY2Index(P)];
end;

procedure GetProgramSize(FileName: string; var RowNum, ColNum: Integer);
var
  F: TextFile;
  s: string;
begin
  RowNum := 0;
  ColNum := 0;

  AssignFile(F, FileName);
  try
    Reset(F);
    while not Eof(F) do
    begin
      Inc(RowNum);
      Readln(F, s);
      if Length(s) > ColNum then
        ColNum := Length(s);
    end;
  finally
    CloseFile(F);
  end;
end;

procedure DumpMap(FileName: string);
var
  F: TextFile;
  Buf: array of Char;
  i, j: Integer;
begin
  SetLength(Buf, ColNum + 1);
  Buf[ColNum] := Chr(0);

  AssignFile(F, FileName);
  try
    Rewrite(F);
    for i := 0 to RowNum - 1 do
    begin
      for j := 0 to ColNum - 1 do
      begin
        if Map[i * ColNum + j] <> Chr(0) then
          Buf[j] := Map[i * ColNum + j]
        else
          Buf[j] := ' ';
      end;
      Writeln(F, PChar(@Buf[0]));
    end;
  finally
    CloseFile(F);
  end;
end;

procedure ClearArea(LT, RB: TPoint); overload;
var
  i, index: Integer;
begin
  for i := LT.Y to RB.Y do
  begin
    index := XY2Index(LT.X, i);
    FillChar(Map[index], RB.X - LT.X + 1, 0);      //
  end;
end;

procedure ClearModule(Module: PModule); overload;
begin
  ClearArea(Module.LT, Module.RB);
end;

procedure SyntaxError;
begin
  LogError('syntax error:', []);
  LogError(Backup, []);
 // Spac
  LogError(SpaceStr(Length(Backup) - Length(TheStr)) + '^', []);
end;

const
  SYMBOL_CHARS: set of Char = ['a'..'z', 'A'..'Z', '0'..'9', '_'];

function NextToken: Boolean;
var
  i: Integer;
  LastChar: Char;
begin
  TheStr := Trim(TheStr);
  Result := Length(TheStr) > 0;
  CurToken := '';
  if not Result then
    Exit;

  LastChar := TheStr[1];

  if LastChar in SYMBOL_CHARS then
    for i := 2 to Length(TheStr) do
    begin
      if not (TheStr[i] in SYMBOL_CHARS) then
      begin
        CurToken := Copy(TheStr, 1, i - 1);
        Delete(TheStr, 1, i - 1);
        Exit;
      end;
    end
  else begin
    if LastChar in ['(', ')', '[', ']', ','] then
    begin
      CurToken := LastChar;
      Delete(TheStr, 1, 1);
      Exit;
    end;
    for i := 2 to Length(TheStr) do
    begin
      if not (TheStr[i] in ['(', ')', '[', ']', ',', '-', '=', '>']) then
      begin
        CurToken := Copy(TheStr, 1, i - 1);
        Delete(TheStr, 1, i - 1);
        Exit;
      end;
    end;
  end;

  CurToken := TheStr;
  TheStr := '';
end;

function RequireToken(const Token: string): Boolean;
begin
  Result := NextToken;
  if Result then
  begin
    if CurToken <> Token then
    begin
      Result := False;
      LogError('"%s" required, but "%s" found.', [Token, CurToken]);
    end;
  end;
end;

type
  PWireMap = ^TWireMap;
  TWireMap = record
    Next: PWireMap;
    Name: string;
    PW: PWire;
  end;

var
  WireMap: TWireMap = (Next: nil; Name: ''; PW: nil);

procedure FreeWireMap(bFreeWire: Boolean = False);
var
  PWM: PWireMap;
begin
  while WireMap.Next <> nil do
  begin
    PWM := WireMap.Next;
    WireMap.Next := PWM.Next;
    if bFreeWire then
    begin
      Dispose(PWM.PW);
    end;
    Dispose(PWM);
  end;
end;

function GetWire(Module: PModule; Name: string): PWire;
var
  PWM: PWireMap;
begin
  PWM := WireMap.Next;
  while PWM <> nil do
  begin
    if PWM.Name <> Name then
      PWM := PWM.Next
    else
      Break;
  end;
  
  if PWM = nil then
  begin
    New(PWM);
    FillChar(PWM^, SizeOf(PWM^), 0);

    New(PWM.PW);
    FillChar(PWM.PW^, SizeOf(PWM.PW^), 0);

    PWM.Name := Name;
    
    PWM.Next := WireMap.Next;
    WireMap.Next := PWM;

    PWM.PW.Next := Module.RootWire.Next;
    Module.RootWire.Next := PWM.PW;
  end;

  Result := PWM.PW;
end;

function FindWireName(PW: PWire): string;
var
  PWM: PWireMap;
begin
  PWM := WireMap.Next;
  while PWM <> nil do
  begin
    if PWM.PW <> PW then
      PWM := PWM.Next
    else
      Break;
  end;
  if PWM <> nil then
    Result := PWM.Name;
end;

{
function NextToken: Boolean;
var
  i: Integer;  
begin
  TheStr := Trim(TheStr);
  Result := Length(TheStr) > 0;
  CurToken := '';
  if not Result then
    Exit;

  for i := 1 to Length(TheStr) do
  begin
    if TheStr[i] in [' ', '(', ')', '[', ']', '>', ','] then
    begin
      if i > 1 then
      begin
        CurToken := Copy(TheStr, 1, i - 1);
        Delete(TheStr, 1, i - 1);
      end
      else begin
        CurToken := Copy(TheStr, 1, 1);
        Delete(TheStr, 1, 1);
      end;
      Exit;
    end;
  end;

  CurToken := TheStr;
  TheStr := '';
end;
}  
procedure BeginFetchEle(const Str: string);
begin
  TheStr := Str;
  Backup := TheStr;
  CurToken := '';
end;

function ParseExpr(var Expr: PExpr; const bFetchNew: Boolean = True): Integer;
var
  s: string;

  procedure NewExpr;
  begin
    New(Expr);
    FillChar(Expr^, SizeOf(Expr^), 0);
  end;

begin
  Expr := nil;
  Result := 0;

  if bFetchNew then
    if not NextToken then
      Exit;
  s := CurToken;
  if s = '(' then
  begin
    if not NextToken then
    begin
      SyntaxError;
      Result := -1;
      Exit;
    end;

    if CurToken = ')' then
    begin
      NewExpr;
      Expr.et := etBase;
      Exit;
    end
    else begin
      NewExpr;
      Expr.et := etPair;
      Expr.Left := nil;
      Expr.Right := nil;
      
      Result := ParseExpr(Expr.Left, False);
      if (Result <> 0) or (Expr.Left = nil) then
        Exit;

      if (not NextToken) or (CurToken <> ',') then
      begin
        SyntaxError;
        Result := -1;
        Exit;
      end;

      Result := ParseExpr(Expr.Right);
      if Result <> 0 then
        Exit;

      if (not NextToken) or (CurToken <> ')') then
      begin
        SyntaxError;
        Result := -1;
        Exit;
      end;
    end;
  end
  else if s = ')' then
  begin
    SyntaxError;
    Result := -1;
    Exit;
  end
  else if s = ',' then
  begin
    Exit;
  end
  else if s = 'Inl' then
  begin
    NewExpr;
    Expr.et := etInl;
    Result := ParseExpr(Expr.Left);
  end
  else if s = 'Inr' then
  begin
    NewExpr;
    Expr.et := etInr;
    Result := ParseExpr(Expr.Left);
  end
  else if s = 'N' then
  begin
    NewExpr;
    Expr.et := etInface;
    Expr.Inface := N;
    Exit;
  end
  else if s = 'W' then
  begin
    NewExpr;
    Expr.et := etInface;
    Expr.Inface := W;
    Exit;
  end
  else if s = 'E' then
  begin
    NewExpr;
    Expr.et := etOutface;
    Expr.Outface := E;
    Exit;
  end
  else if s = 'S' then
  begin
    NewExpr;
    Expr.et := etOutface;
    Expr.Outface := Lang.S;
    Exit;
  end
  else begin
    LogError('unknown token: ' + s, []);
    Result := -1;
  end;
end;

function CompileExpr(var Expr: PExpr; const bFetchNew: Boolean): Integer;
begin
  Result := ParseExpr(Expr, bFetchNew);
end;

function CompileBlock(Block: PBlock; Command: string): Integer;
var
  s: string;
begin
  Result := 0;
//Log('parsing block: %s', [Command]);
  BeginFetchEle(Command);
  NextToken;
  s := UpperCase(CurToken);

  if s = 'SPLIT' then
  begin
    Block.bc := bcSplit;
    Block.Expr := nil;

    Result := CompileExpr(Block.Expr);
    if (Result <> 0) or (Block.Expr = nil) then
      Exit;
  end
  else if s = 'SEND' then
  begin
    Block.bc := bcSend;
    Block.Expr := nil;
    Block.Expr2 := nil;

    NextToken;
    if CurToken <> '[' then
    begin
      ExpectedInBlock('[', CurToken, Block);
      Result := -1;
      Exit;
    end;

    NextToken;
    if CurToken <> ']' then
    begin
      Result := CompileExpr(Block.Expr, False);
      if (Result <> 0) or (Block.Expr = nil) then
        Exit;
        
      NextToken;
      if CurToken = ',' then
      begin
        Result := CompileExpr(Block.Expr2);
        if (Result <> 0) or (Block.Expr2 = nil) then
          Exit;
        NextToken;
      end;
    end
    else;

    if CurToken <> ']' then
    begin
      ExpectedInBlock(']', CurToken, Block);
      Result := -1;
      Exit;
    end;
{
    if (Block.Expr <> nil) and ((Block.Expr.et <> etPair) or (Block.Expr.Right.et <> etOutface))
      or (Block.Expr2 <> nil) and ((Block.Expr2.et <> etPair) or (Block.Expr2.Right.et <> etOutface)) then
    begin
      ExpectedInBlock('send [], send [(exp, outface)], send [(exp, outface), (exp, outface)]', Block);
      Result := -1;
      Exit;
    end;
}
  end
  else if s = 'CASE' then
  begin
    Block.bc := bcCase;
    Result := CompileExpr(Block.Expr);
    if (Result <> 0) or (Block.Expr = nil) then
      Exit;

    NextToken;
    if UpperCase(CurToken) <> 'OF' then
    begin
      ExpectedInBlock('of', CurToken, Block);
      Result := -1;
      Exit;
    end;

    NextToken;
    if CurToken = 'E' then
      Block.OutFace1 := Lang.E
    else if CurToken = 'S' then
      Block.OutFace1 := Lang.S
    else begin
      ExpectedInBlock('E or S', CurToken, Block);
      Result := -1;
      Exit;
    end;

    NextToken;
    if UpperCase(CurToken) <> ',' then
    begin
      ExpectedInBlock(',', CurToken, Block);
      Result := -1;
      Exit;
    end;

    NextToken;
    if CurToken = 'E' then
      Block.OutFace2 := Lang.E
    else if CurToken = 'S' then
      Block.OutFace2 := Lang.S
    else begin
      ExpectedInBlock('E or S', CurToken, Block);
      Result := -1;
      Exit;
    end;
{
    if Block.OutFace1 = Block.OutFace2 then
    begin
      ErrorInBlock('two outfaces are the same in "case".', Block);
      Result := -1;
      Exit;
    end;
}
  end
  else if s = 'USE' then
  begin
    Block.bc := bcUse;
    Block.Module := nil;
    NextToken;
    Block.UseModuleName := CurToken;
  end
  else begin
    LogError('unkown block command: ' + s, []);
    Result := -1;
  end;
end;

function PtInRect(const Rect: TRect; const P: TPoint): Boolean; overload;
begin
  Result := (P.X >= Rect.Left) and (P.X <= Rect.Right) and (P.Y >= Rect.Top)
    and (P.Y <= Rect.Bottom);
end;

function PtInRect(const LT, RB: TPoint; const P: TPoint): Boolean; overload;
begin
  Result := (P.X >= LT.X) and (P.X <= RB.X) and (P.Y >= LT.Y)
    and (P.Y <= RB.Y);
end;

function PtOnRect(const LT, RB: TPoint; const X, Y: Integer): Boolean; overload;
begin
  Result := (X >= LT.X) and (X <= RB.X) and ((Y = LT.Y) or (Y = RB.Y))
           or (Y >= LT.Y) and (Y <= RB.Y) and ((X = LT.X) or (X = RB.X));
end;

function CompileWire(Module: PModule; var Wire: TWire; const X, Y: Integer): Integer;
var
  DDX, DDY, DX, DY, i, j, ODX, ODY: Integer;
  bStartFound, bEndFound: Boolean;
  Rect: TRect;
  Pt: TPoint;
  Temp: Integer;
  bErr: Boolean;
  
  procedure InitSearch(bInverseDir: Boolean);
  begin
    if bInverseDir then
    begin
      DX := - DDX;
      DY := - DDY;
    end
    else begin
      DX := DDX;
      DY := DDY;
    end;

    i := X + DX;
    j := Y + DY;
  end;

  procedure SetStartPt(const X, Y: Integer);
  begin
    if bStartFound then
      bErr := True;
      
    bStartFound := True;
    Wire.SourcePt.X := X;
    Wire.SourcePt.Y := Y;

    if DX <> 0 then
      if DX = -1 then
        Wire.SourceFace := fW
      else
        Wire.SourceFace := fE
    else
      if DY = -1 then
        Wire.SourceFace := fN
      else
        Wire.SourceFace := fS;

    InitSearch(True);
  end;

  procedure SetEndPt(const X, Y: Integer);
  begin
    if bEndFound then
      bErr := True;

    bEndFound := True;
    Wire.TargetPt.X := X;
    Wire.TargetPt.Y := Y;

    if DX <> 0 then
      if DX = -1 then
        Wire.TargetFace := fW
      else
        Wire.TargetFace := fE
    else
      if DY = -1 then
        Wire.TargetFace := fN
      else
        Wire.TargetFace := fS;

    InitSearch(True);
  end;

  function IsPtOnBlockSide(const X, Y: Integer): Boolean;
  var
    PB: PBlock;
  begin
    Result := False;
    PB := Module.RootBlock.Next;
    while PB <> nil do
    begin
      Result := PtOnRect(PB.LT, PB.RB, X, Y);
      if Result then
        Break;
      PB := PB.Next;
    end;
  end;
label
  quit;
begin
  bErr := False;
  bStartFound := False;
  bEndFound := False; //Map[XY2Index(X, Y)] in ['>', '<', 'v', '^'];
{  if bEndFound then
  begin
    Wire.TargetPt.X := X;
    Wire.TargetPt.Y := Y;
  end;

  SetEndPt(i, j);
              SetEndPt(i, j);
}
  Rect.Left := Module.LT.X;
  Rect.Top  := Module.LT.Y;
  Rect.Right := Module.RB.X;
  Rect.Bottom := Module.RB.Y;

  DDX := 0;
  DDY := 0;
  case Map[XY2Index(X, Y)] of
    '-', '>':  DDX := 1;
    '<'     :  DDX := -1;
    '|', 'v':  DDY := 1;
    '^'     :  DDY := -1;
  end;

  if DDX or DDY = 0 then
    goto quit;

  InitSearch(False);

//  Map[XY2Index(X, Y)] := Chr(0);
  Dec(i, DX);
  Dec(j, DY);

  while (not (bStartFound and bEndFound)) and (not bErr) do
  begin
    Pt.X := i;
    Pt.Y := j;
    
    if not PtInRect(Rect, Pt) then
    begin
      if (DX <> 0) and ((i <= Rect.Left) or (i >= Rect.Right)) then
      begin
        if i <= Rect.Left then
          SetStartPt(i - DX, j - DY)
        else
          SetEndPt(i - DX, j - DY);

        Continue;
      end
      else if (DY <> 0) and ((j <= Rect.Top) or (j >= Rect.Bottom)) then
      begin
        if j <= Rect.Top then
          SetStartPt(i - DX, j - DY)
        else
          SetEndPt(i - DX, j - DY);

        Continue;
      end
      else begin
        WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
        Break;
      end;
    end;

    case Map[XY2Index(i, j)] of
      '-':  if DX = 0 then
            begin
              WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
              Break;
            end
            else Map[XY2Index(i, j)] := Chr(0);
      '|':  if DY = 0 then
            begin
              WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
              Break;
            end
            else Map[XY2Index(i, j)] := Chr(0);
      '>', '<'
         :  if (DX <> 0) and (not bEndFound) then
            begin
              Map[XY2Index(i, j)] := Chr(0);
              SetEndPt(i, j);
              Continue;
            end
            else begin
              WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
              Break;
            end;
      'v', '^'
         :  if (DY <> 0) and (not bEndFound) then
            begin
              Map[XY2Index(i, j)] := Chr(0);
              SetEndPt(i, j);
              Continue;
            end
            else begin
              WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
              Break;
            end;
      '#':  begin
            end;
      '+':  begin
              Temp := 0;
              ODX := DX;
              ODY := DY;
              Map[XY2Index(i, j)] := Chr(0);
              if (ODX <> -1) and (Map[XY2Index(i + 1, j + 0)] in HWireChar) then
              begin
                  DX := 1;
                  DY := 0;
                Inc(Temp);
              end;
              if (ODX <> 1) and (Map[XY2Index(i - 1, j + 0)] in HWireChar) then
              begin
                  DX := -1;
                  DY := 0;
                Inc(Temp);
              end;
              if (ODY <> -1) and (Map[XY2Index(i + 0, j + 1)] in VWireChar) then
              begin
                  DX := 0;
                  DY := 1;
                Inc(Temp);
              end;
              if (ODY <> 1) and (Map[XY2Index(i + 0, j - 1)] in VWireChar) then
              begin
                  DX := 0;
                  DY := -1;
                Inc(Temp);
              end;

              // check border
              if Temp = 0 then
              begin
                if    IsPtOnBlockSide(i + 0, j - 1) then
                begin
                  DX := 0;
                  DY := -1;
                  SetStartPt(i, j);
                  Continue;
                end
                else if IsPtOnBlockSide(i + 0, j + 1) then
                begin
                  DX := 0;
                  DY := 1;
                  SetStartPt(i, j);
                  Continue;
                end
                else if IsPtOnBlockSide(i + 1, j + 1) then
                begin
                  DX := 1;
                  DY := 0;
                  SetStartPt(i, j);
                  Continue;
                end
                else if IsPtOnBlockSide(i - 1, j + 0) then
                begin
                  DX := -1;
                  DY := 0;
                  SetStartPt(i, j);
                  Continue;
                end;
              end;

              if Temp <> 1 then
              begin
                WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
                Break;
              end;
            end;
      ' ', Chr(0):
            begin
              if not bStartFound then
              begin
                SetStartPt(i - DX, j - DY);
                Continue;
              end
              else if not bEndFound then
              begin
                SetEndPt(i - DX, j - DY);
                Continue;
              end
              else begin
                WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
                Break;
              end;
            end;
    else
      WireErrorInModule(Map[XY2Index(i, j)], Module, i, j);
      Break;
    end;

    Inc(i, DX);
    Inc(j, DY);
  end;

quit:
  if not (bStartFound and bEndFound) or bErr then
  begin
    Result := -1;
    WireErrorInModule('error when parsing wire.', Module, X, Y);
  end
  else
    Result := 0;
end;

function ConnectWires(Module: PModule): Integer;
var
  PW: PWire;
  PB: PBlock;
  PP: PPoint;
  Pt: TPoint;
  Face: TFace;
  ModuleRect: TRect;
  Counter: Integer;
  PWN: PWireNode;
begin
  Log('connecting wires.', []);
  
  Result := 0;
  ModuleRect.Left := Module.LT.X;
  ModuleRect.Top  := Module.LT.Y;
  ModuleRect.Right := Module.RB.X;
  ModuleRect.Bottom := Module.RB.Y;
  Face := fE;
  PP := nil;
  PW := @Module.RootWire;
  while PW.Next <> nil do
  begin
    PW := PW.Next;
    Counter := 0;
//    Log('connecting wire from (%d, %d) to (%d, %d).',
//        [Pw.SourcePt.Y + 1, Pw.SourcePt.X + 1,
//         Pw.TargetPt.Y + 1, Pw.TargetPt.X + 1]);

    while Counter <= 1 do
    begin
      if Counter = 0 then
      begin
        PP := @PW.SourcePt;
        Face := PW.SourceFace;
      end
      else if Counter = 1 then
      begin
        PP := @PW.TargetPt;
        Face := PW.TargetFace;
      end      
      else
        Break;

      Pt := PP^;

      // check if connect to the I/O ports of the module
      if (Pt.X = ModuleRect.Left) and (Face = fW) then
      begin
        if Module.W = nil then
        begin
          PW.Source := nil;
          Module.W := PW;
          PW.SourceFace := fW;
          Inc(Counter);
          Continue;
        end
        else begin
          LogError('connecting wire failed: W edge of module "%s".', [Module.Name]);
          Continue;
        end;
      end
      else if (Pt.X = ModuleRect.Right) and (Face = fE) then
      begin
        PW.Target := nil;
        PW.TargetFace := fE;

        New(PWN);
        FillChar(PWN^, SizeOf(PWN^), 0);
        PWN.Wire := PW;
        PWN.Next := Module.OutputWires.Next;
        Module.OutputWires.Next := PWN;

        Inc(Counter);
        Continue;
      end
      else if (Pt.Y = ModuleRect.Top) and (Face = fN) then
      begin
        if Module.N = nil then
        begin
          PW.Source := nil;
          PW.SourceFace := fN;
          Module.N := PW;
          Inc(Counter);
          Continue;
        end
        else begin
          LogError('connecting wire failed: N edge of module "%s".', [Module.Name]);
          Continue;
        end;
      end
      else if (Pt.Y = ModuleRect.Bottom) or (Pt.Y = ModuleRect.Bottom) then
      begin
        LogError('wire cannot be connected to the bottom edge of a module.', []);
        Continue;
      end
      else;

      case Face of
        fE: Inc(Pt.X);
        fW: Dec(Pt.X);
        fS: Inc(Pt.Y);
        fN: Dec(Pt.Y);
      end;
      
      PB := Module.RootBlock.Next;
      while PB <> nil do
      begin

        if PtInRect(PB.LT, PB.RB, Pt) then
        begin
          Inc(Counter);

          case Face of
            fE: begin
                  if (PB.W = nil) and (PW.Target = nil) then
                  begin
                    PB.W := PW;
                    PW.Target := PB;
                  end
                  else begin
                    LogError('at (%d, %d), connected wire failed.',
                             [PP.Y + 1, PP.X + 1]);
                  end;
                end;
            fW: begin
                  if (PB.E = nil) and (PW.Source = nil) then
                  begin
                    PB.E := PW;
                    PW.Source := PB;
                  end
                  else begin
                    LogError('at (%d, %d), connected wire failed.',
                             [PP.Y + 1, PP.X + 1]);
                  end;
                end;
            fS: begin
                  if (PB.N = nil) and (PW.Target = nil) then
                  begin
                    PB.N := PW;
                    PW.Target := PB;
                  end
                  else begin
                    LogError('at (%d, %d), connected wire failed.',
                             [PP.Y + 1, PP.X + 1]);
                  end;
                end;
            fN: begin
                  if (PB.S = nil) and (PW.Source = nil) then
                  begin
                    PB.S := PW;
                    PW.Source := PB;
                    Break;
                  end
                  else begin
                    LogError('at (%d, %d), connected wire failed.',
                             [PP.Y + 1, PP.X + 1]);
                  end;
                end;
          end;

          Break;
        end;

        PB := PB.Next;
      end;

      if PB = nil then
        Break;
    end;

    if Counter <= 1 then
    begin

      LogError('connecting wire failed (%d ends connected), from (%d, %d) to (%d, %d).',
               [Counter, PW.SourcePt.Y + 1, PW.SourcePt.X + 1,
                PW.TargetPt.Y + 1, PW.TargetPt.X + 1]);
      Result := -1;
    end;
  end;
end;

function CompileWires(Module: PModule): Integer;
var
  CurX, CurY: Integer;
  Wire: TWire;
  PW: PWire;
begin
  Result := 0;

  // scaning for wires
  for CurY := Module.LT.Y to Module.RB.Y do
  begin
    for CurX := Module.LT.X to Module.RB.X do
    begin
      if Map[XY2Index(CurX, CurY)] in DirectionedWire then
      begin
        FillChar(Wire, SizeOf(Wire), 0);
        if CompileWire(Module, Wire, CurX, CurY) = 0 then
        begin
          New(PW);
          PW^ := Wire;
          PW.Next := Module.RootWire.Next;
          Module.RootWire.Next := PW;
        end
        else
          Result := -1;
      end;
    end;
  end;
end;

function VerifySplitExpr(PB: PBlock; Expr: PExpr): Boolean;
var
  TypeSet: TExprTypeSet;
  InFaceSet: TInFaceSet;
  OutFaceSet: TOutFaceSet;
begin
  Result := True;
  if Expr = nil then
    Exit;

  ExprPropSet(Expr, TypeSet, InFaceSet, OutFaceSet);
  PB.InFaceSet := InFaceSet;

  if etOutface in TypeSet then
  begin
    ErrorInBlock('SPLIT cannot uses outfaces(E or S) as input', PB);
    Result := False;
  end;

  if (W in InFaceSet) and (PB.W = nil) then
  begin
    ErrorInBlock('SPLIT needs a wire at W', PB);
    Result := False;
  end;

  if (N in InFaceSet) and (PB.N = nil) then
  begin
    ErrorInBlock('SPLIT needs a wire at N', PB);
    Result := False;
  end;

  if Expr.et in [etInl, etInr, etBase] then
  begin
    ErrorInBlock('SPLIT needs a PAIR expression.', PB);
    Result := False;
  end;
end;

function VerifySendExpr(PB: PBlock; Expr: PExpr): Boolean;
var
  TypeSet: TExprTypeSet;
  InFaceSet: TInFaceSet;
  OutFaceSet: TOutFaceSet;
begin
  Result := True;
  if Expr = nil then
    Exit;

  if Expr.et = etPair then
  begin
    if (Expr.Right = nil) or (Expr.Right.et <> etOutface) then
    begin
      ErrorInBlock('SEND needs to send something to E or S.', PB);
      Result := False;
    end;

    if Expr.Left <> nil then
    begin
      ExprPropSet(Expr.Left, TypeSet, InFaceSet, OutFaceSet);
      PB.InFaceSet := PB.InFaceSet + InFaceSet;

      if etOutface in TypeSet then
      begin
        ErrorInBlock('SEND cannot send outfaces(E or S) to somewhere else', PB);
        Result := False;
      end;
      if (W in InFaceSet) and (PB.W = nil) then
      begin
        ErrorInBlock('SEND needs a wire at W', PB);
        Result := False;
      end;
      if (N in InFaceSet) and (PB.N = nil) then
      begin
        ErrorInBlock('SEND needs a wire at N', PB);
        Result := False;
      end;

      ExprPropSet(Expr.Right, TypeSet, InFaceSet, OutFaceSet);
      if etInface in TypeSet then
      begin
        ErrorInBlock('SEND cannot send something to infaces(N or W)', PB);
        Result := False;
      end;
      if (S in OutFaceSet) and (PB.S = nil) then
      begin
        ErrorInBlock('SEND needs a wire at S', PB);
        Result := False;
      end;
      if (E in OutFaceSet) and (PB.E = nil) then
      begin
        ErrorInBlock('SEND needs a wire at E', PB);
        Result := False;
      end;
    end
    else begin
      ErrorInBlock('SEND needs to send something to E or S', PB);
      Result := False;
    end;
  end
  else begin
    ErrorInBlock('SEND needs a PAIR expression', PB);
    Result := False;
  end;
end;

function VerifyCaseExpr(PB: PBlock; Expr: PExpr): Boolean;
var
  TypeSet: TExprTypeSet;
  InFaceSet: TInFaceSet;
  OutFaceSet: TOutFaceSet;
begin
  Result := True;
  if Expr = nil then
    Exit;

  ExprPropSet(Expr, TypeSet, InFaceSet, OutFaceSet);
  PB.InFaceSet := InFaceSet;

  if etOutface in TypeSet then
  begin
    ErrorInBlock('CASE cannot uses outfaces(E or S) as input', PB);
    Result := False;
  end;

  if (W in InFaceSet) and (PB.W = nil) then
  begin
    ErrorInBlock('CASE needs a wire at W', PB);
    Result := False;
  end;

  if (N in InFaceSet) and (PB.N = nil) then
  begin
    ErrorInBlock('CASE needs a wire at N', PB);
    Result := False;
  end;
end;

function VerifyModuleBlocks(var Module: TModule): Integer;
var
  PB: PBlock;
begin
  Result := 0;

  Log('verifying module "%s"', [Module.Name]);

  PB := Module.RootBlock.Next;
  while PB <> nil do
  begin
    // now execute
    case PB.bc of
      bcSplit:
        begin
          if PB.Expr <> nil then
          begin
            if not VerifySplitExpr(PB, PB.Expr) then
              Dec(Result);
          end
          else begin
            ErrorInBlock('SPLIT needs an expression.', PB);
            Dec(Result);
          end;
{
          if PB.InFace in  then
          begin
            LogError('SPLIT needs a N input.', []);
            Dec(Result);
          end;

          if (PB.InFace = Lang.W) and (PB.W = nil) then
          begin
            LogError('SPLIT needs a W input.', []);
            Dec(Result);
          end;
}
          if PB.S = nil then
          begin
            ErrorInBlock('SPLIT needs a S output.', PB);
            Dec(Result);
          end;

          if PB.E = nil then
          begin
            ErrorInBlock('SPLIT needs a E output.', PB);
            Dec(Result);
          end;
        end;
      bcSend:
        begin
          if PB.Expr <> nil then
          begin
            if not VerifySendExpr(PB, PB.Expr) then
              Dec(Result);
          end;

          if not VerifySendExpr(PB, PB.Expr2) then
              Dec(Result);
        end;
      bcCase:
        begin
          if PB.Expr <> nil then
          begin
            if not VerifyCaseExpr(PB, PB.Expr) then
              Dec(Result);
          end
          else begin
            ErrorInBlock('CASE needs an expression.', PB);
            Dec(Result);
          end;

          if (E = PB.OutFace1) and (PB.E = nil) then
          begin
            ErrorInBlock('CASE needs a wire at E.', PB);
            Dec(Result);
          end;
          if (S = PB.OutFace1) and (PB.S = nil) then
          begin
            ErrorInBlock('CASE needs a wire at S.', PB);
            Dec(Result);
          end;
        end;
      bcUse:
        begin
          if (PB.N = nil) and (PB.W = nil) and (PB.S = nil) and (PB.E = nil) then
          begin
            WarningInBlock('USE has no wire connected to any side.', PB);
          end;
          if (PB.S <> nil) and (PB.E <> nil) then
          begin
            ErrorInBlock('USE has too many outputs.', PB);
            Dec(Result);
          end;
        end;
    else
      LogError('VerifyModule: you cannot get to here. -- unknown block type.', []);
      Dec(Result);
    end;

    PB := PB.Next;
  end;
end;

function VerifyModuleWires(var Module: TModule): Integer;
var
  PW: PWire;
  PWN: PWireNode;
begin
  Result := 0;
  PW := Module.RootWire.Next;
  
  while PW <> nil do
  begin
  
    if PW.Source = nil then
    begin
      if (Module.N <> PW) and (Module.W <> PW) then
      begin
        LogError('a wire %s does not have a driven port.', [FindWireName(PW)]);
//      Dec(Result);
      end;
    end
    else;

    if PW.Target = nil then
    begin
      PWN := Module.OutputWires.Next;
      while PWN <> nil do
        if PWN.Wire <> PW then
          PWN := PWN.Next
        else
          Break;
      if PWN = nil then
      begin
        LogWarning('a wire %s does not have a target port.', [FindWireName(PW)]);
      end;
    end
    else;

    PW := PW.Next;
  end;
end;

function VerifyModule(var Module: TModule): Integer;
begin
  Result := VerifyModuleWires(Module) + VerifyModuleBlocks(Module);
end;

function CompileModule(var Module: TModule): Integer;
var
  s: string;
  i, j: Integer;
  bBlockFound: Boolean;
  CurX, CurY: Integer;
  Block: TBlock;
  PB: PBlock;
begin
  // scaning for blocks
  CurY := Module.LT.Y + 1;
  CurX := Module.LT.X + 1;
  while CurY <= Module.RB.Y - 1 do
  begin
    bBlockFound := False;
    FillChar(Block, SizeOf(Block), 0);

    while CurX <= Module.RB.X - 1 do
      if Map[XY2Index(CurX, CurY)] <> '*' then
        Inc(CurX)
      else begin
        bBlockFound := True;
        Break;
      end;

    // not found in this line, move the next
    if not bBlockFound then
    begin
      Inc(CurY);
      CurX := Module.LT.X + 1;
      Continue;
    end;

    Block.LT.X := CurX;
    Block.LT.Y := CurY;
    Block.RB.Y := CurY + 2;

    if CurY + 2 > Module.RB.Y then
    begin
      LogError('block in module "%s" is broken.', [Module.Name]);
      Continue;
    end;

    Inc(CurX);
    while (CurX <= Module.RB.X - 1) and (Map[XY2Index(CurX, CurY)] = '=') do
      Inc(CurX);
    bBlockFound := Map[XY2Index(CurX, CurY)] = '*';
    if not bBlockFound then
      Continue;

    Block.RB.X := CurX;

    if Map[XY2Index(Block.RB.X, Block.RB.Y)] <> '*' then
    begin
      CharError('*', Map[XY2Index(Block.RB.X, Block.RB.Y)], Block.RB.X, Block.RB.Y);
      Continue;
    end;
    if Map[XY2Index(Block.LT.X, Block.RB.Y)] <> '*' then
    begin
      CharError('*', Map[XY2Index(Block.LT.X, Block.RB.Y)], Block.LT.X, Block.RB.Y);
      Continue;
    end;
    if Map[XY2Index(Block.LT.X, Block.RB.Y - 1)] <> '!' then
    begin
      CharError('!', Map[XY2Index(Block.LT.X, Block.RB.Y - 1)], Block.LT.X, Block.RB.Y - 1);
      Continue;
    end;
    if Map[XY2Index(Block.RB.X, Block.RB.Y - 1)] <> '!' then
    begin
      CharError('!', Map[XY2Index(Block.RB.X, Block.RB.Y - 1)], Block.RB.X, Block.RB.Y - 1);
      Continue;
    end;

    j := XY2Index(Block.LT.X, Block.RB.Y) + 1;
    for i := j to j + Block.RB.X - Block.LT.X - 2 do
    begin
      if Map[i] <> '=' then
      begin
        CharWarning('=', Map[i], i - j + Block.LT.X + 1, Block.RB.Y);
      end;
    end;

    Map[XY2Index(Block.RB.X, Block.RB.Y - 1)] := Chr(0);
    s := PChar(@Map[XY2Index(Block.LT.X + 1, Block.RB.Y - 1)]);
    Result := CompileBlock(@Block, s);
    ClearArea(Block.LT, Block.RB);

    if Result = 0 then
    begin
      New(PB);
      PB^ := Block;
      PB.Next := Module.RootBlock.Next;
      Module.RootBlock.Next := PB;

//      LogWarning('expr: ' + DisExpr(PB.Expr), []);
//      LogWarning('expr2:' + DisExpr(PB.Expr2), []);
    end;

  end; // end of while CurY <= Module.RB.Y - 1 do

  Result := CompileWires(@Module) +
            ConnectWires(@Module) +
            VerifyModule(Module);
end;

function CompileL2dModuleDecl(var Module: TModule): Integer;
label
  ParseWire,
  ParseName;
var
  PW: PWire;
  PWN: PWireNode;
begin
  Result := 0;

ParseWire:  
  NextToken;
  if CurToken = ')' then goto ParseName;

  PW := GetWire(@Module, CurToken);

  if not RequireToken('->') then
  begin
    Dec(Result);
    Exit;
  end;

  NextToken;
  if CurToken = 'N' then
  begin
    if Module.N <> nil then
      LogWarning('"N" side reconnected.', []);
    Module.N := PW
  end
  else if CurToken = 'W' then
  begin
    if Module.W <> nil then
      LogWarning('"W" side reconnected.', []);
    Module.W := PW
  end
  else begin
    LogError('invalid side "%s", "N" or "W" expected.', [CurToken]);
    Dec(Result);
    Exit;
  end;

  NextToken;
  if CurToken = ',' then
    goto ParseWire
  else if CurToken <> ')' then
  begin
    LogError('unexpected "%s", ") or ," expected.', [CurToken]);
    Dec(Result);
    Exit;
  end;

ParseName:
  if not RequireToken('==>') then
  begin
    Dec(Result);
    Exit;
  end;

  NextToken;
  Module.Name := CurToken;

  if not RequireToken('==>') then
  begin
    Dec(Result);
    Exit;
  end;

  if not RequireToken('(') then
  begin
    Dec(Result);
    Exit;
  end;

  NextToken;
  while CurToken <> ')' do
  begin
    New(PWN);
    PWN.Wire := GetWire(@Module, CurToken);
    PWN.Next := Module.OutputWires.Next;
    Module.OutputWires.Next := PWN;
    
    NextToken;
    if CurToken <> ',' then
      Break
    else
      NextToken;
  end;
  if CurToken <> ')' then
  begin
    LogError('")" expected, but "%s" found.', [CurToken]);
    Dec(Result);
    Exit;
  end;
end;

function CompileL2dModuleDef(var Module: TModule): Integer;
label
  ParseWire,
  ParseModu;
var
  PW: PWire;
  Block: TBlock;
  PB: PBlock;
  LastToken: string;
begin
  Result := 0;
  if CurToken <> '(' then
    Exit;
  FillChar(Block, SizeOf(Block), 0);

ParseWire:  
  NextToken;
  if CurToken = ')' then goto ParseModu;

  PW := GetWire(@Module, CurToken);

  if not RequireToken('->') then
  begin
    Dec(Result);
    Exit;
  end;

  NextToken;
  if CurToken = 'N' then
  begin
    if Block.N <> nil then
      LogWarning('"N" side reconnected.', []);
    Block.N := PW
  end
  else if CurToken = 'W' then
  begin
    if Block.W <> nil then
      LogWarning('"W" side reconnected.', []);
    Block.W := PW
  end
  else begin
    LogError('invalid side "%s", "N" or "W" expected.', [CurToken]);
    Dec(Result);
    Exit;
  end;

  NextToken;
  if CurToken = ',' then
    goto ParseWire
  else if CurToken <> ')' then
  begin
    LogError('unexpected "%s", ") or ," expected.', [CurToken]);
    Dec(Result);
    Exit;
  end;

ParseModu:
  if not RequireToken('==>') then
  begin
    Dec(Result);
    Exit;
  end;

  Inc(Result, CompileBlock(@Block, TheStr));

  if not RequireToken('==>') then
  begin
    Dec(Result);
    Exit;
  end;

  if not RequireToken('(') then
  begin
    Dec(Result);
    Exit;
  end;

  NextToken;
  while CurToken <> ')' do
  begin
//    NextToken;
    LastToken := CurToken;

    if not RequireToken('->') then
    begin
      Dec(Result);
      Exit;
    end;

    NextToken;
    PW := GetWire(@Module, CurToken);

    if LastToken = 'S' then
    begin
      if Block.S <> nil then
        LogWarning('"S" side reconnected.', []);
      Block.S := PW
    end
    else if LastToken = 'E' then
    begin
      if Block.E <> nil then
        LogWarning('"E" side reconnected.', []);
      Block.E := PW
    end
    else begin
      LogError('invalid side "%s", "S" or "E" expected.', [LastToken]);
      Dec(Result);
      Exit;
    end;

    NextToken;
    if CurToken <> ',' then
      Break
    else
      NextToken;
  end;
  
  if CurToken <> ')' then
  begin
    LogError('")" expected, but "%s" found.', [CurToken]);
    Dec(Result);
    Exit;
  end;

  if Result = 0 then
  begin
    New(PB);
    PB^ := Block;
    PB.Next := Module.RootBlock.Next;
    Module.RootBlock.Next := PB;
    if PB.N <> nil then
      PB.N.Target := PB;
    if PB.W <> nil then
      PB.W.Target := PB;
    if PB.S <> nil then
      PB.S.Source := PB;
    if PB.E <> nil then
      PB.E.Source := PB;
  end;
end;

function CompileL2dModule(var F: TextFile): Integer;
label
  quit;
var
  s: string;
  Module: TModule;
  PM: PModule;
  bDone: Boolean;
begin
  Result := 0;
  bDone := False;
  FillChar(Module, SizeOf(Module), 0);  

  if not RequireToken('(') then
  begin
    Dec(Result);
    Exit;
  end;

  Inc(Result, CompileL2dModuleDecl(Module));

  if Result <> 0 then
    goto quit;

  Log('module found: %s', [Module.Name]);

  while (Result = 0) and not (Eof(F)) do
  begin
    Readln(F, s);
    BeginFetchEle(s);
    NextToken;
    if CurToken <> 'end' then
      Inc(Result, CompileL2dModuleDef(Module))
    else begin
      bDone := True;
      if Result = 0 then
      begin
        Break;
      end;
    end;
  end;

quit:
  if not bDone then
    Dec(Result);
  Inc(Result, VerifyModule(Module));
  if Result = 0 then
  begin
    New(PM);
    PM^ := Module;

    GlobalRegisterModule(PM);
  end
  else begin
    DisposeModule(@Module);
  end;
  FreeWireMap;
end;

function CompileL2d(FileName: string): Integer;
var
  F: TextFile;
  s: string;
begin
  Result := 0;
  AssignFile(F, FileName);
  try
    Reset(F);
    while (Result = 0) and not (Eof(F)) do
    begin
      Readln(F, s);
      BeginFetchEle(s);
      NextToken;
      if CurToken = 'module' then
        Inc(Result, CompileL2dModule(F))
      else begin
//        LogError('"module" expected, but "%s" is found.', [CurToken]);
//        Dec(Result);
      end;
    end;
  finally
    CloseFile(F);
  end;
end;

function Compile(FileName: string): Integer;
var
  F: TextFile;
  s: string;
  i: Integer;
  Module: TModule;
  PM: PModule;
  bLTFound: Boolean;
  StartPos: Integer;
begin
  Result := 0;
  GetProgramSize(FileName, RowNum, ColNum);
  Log('program map size confirmed: %d * %d.', [RowNum, ColNum]);
  if RowNum * ColNum < 1 then
  begin
    LogError('map size = 0, nothing to compile.', []);
    Exit;
  end;

  SetLength(Map, RowNum * ColNum + 1);
  FillChar(Map[0], RowNum * ColNum + 1, 0);

  AssignFile(F, FileName);
  try
    Reset(F);
    for i := 0 to RowNum - 1 do
    begin
      Readln(F, s);
      StrCopy(@Map[i * ColNum], PChar(s));
    end;
  finally
    CloseFile(F);
  end;
  Log('program map loaded.', []);

  Log('scanning for modules....', []);
  StartPos := 0;
  while True do
  begin
    bLTFound := False;
    FillChar(Module, SizeOf(Module), 0);
    
    for i := StartPos to RowNum * ColNum - 1 do
        if Map[i] = ',' then
        begin
          Module.LT.X := i mod ColNum;
          Module.LT.Y := i div ColNum;
          bLTFound := True;
          Break;
        end;

    if not bLTFound then
      Break;

    bLTFound := False;
    for i := Module.LT.X + 1 to ColNum - 1 do
      if not (Map[Module.LT.Y * ColNum + i] in ['.', '|']) then
      begin
        Module.RB.X := i;
        if Map[Module.LT.Y * ColNum + i] = ',' then
        begin
          bLTFound := True;
          Break;
        end
        else begin
//        CharError(', ', Map[Module.LT.X * ColNum + i], i, Module.LT.Y);
          Break;
        end;
      end;

    StartPos := XY2Index(Module.RB.X, Module.LT.Y);
    if not bLTFound then
    begin
      StartPos := XY2Index(Module.LT.X + 1, Module.LT.Y);
      Continue;
    end;

    bLTFound := False;
    for i := Module.LT.Y + 1 to RowNum - 1 do
      if not (Map[Module.LT.X + ColNum * i] in [':', '-']) then
      begin
        Module.RB.Y := i;
        if Map[Module.LT.X + ColNum * i] = ',' then
        begin
          bLTFound := True;
          Break;
        end
        else begin
//        CharError(', ', Map[Module.LT.X * ColNum + i], i, Module.LT.Y);
          Break;
        end;
      end;

    if not bLTFound then
      Continue;

    bLTFound := False;
    if Map[XY2Index(Module.RB)] = ',' then
    begin
      bLTFound := True;
    end
    else
      CharError(', ', Map[Module.LT.X * ColNum + i], Module.RB.X, Module.RB.Y);

    if not bLTFound then
      Continue;

    if Module.RB.Y - Module.LT.Y < 1 then
    begin
      LogError('module name missing.' + Map[Module.LT.X * ColNum + i],
               [Module.LT.Y + 2, Module.LT.X + 2]);
      Continue;
    end;

    // check module borders
    bLTFound := True;
    for i := Module.LT.Y + 1 to Module.RB.Y - 1 do
    begin
      if not (CharAt(Module.RB.X, i) in [':', '-']) then
      begin
        CharWarning(': or -', CharAt(Module.RB.X, i), Module.RB.X, i);
//        DumpMap('clear.2d');
//        bLTFound := False;
      end;
    end;
    if not bLTFound then
      Continue;
    for i := Module.LT.X + 1 to Module.RB.X - 1 do
    begin
      if not (CharAt(i, Module.RB.Y) in ['.', '|']) then
      begin
        CharWarning('. or |', CharAt(i, Module.RB.Y), i, Module.RB.Y);
      end;
    end;
    if not bLTFound then
      Continue;

    i := XY2Index(Module.LT.X + 1, Module.LT.Y + 1);
    while not (Map[i] in [' ', '|', ':', '!']) do
      Inc(i);
    Map[i] := Chr(0);
    Module.Name := PChar(@(Map[XY2Index(Module.LT.X + 1, Module.LT.Y + 1)]));
    FillChar(Map[XY2Index(Module.LT.X + 1, Module.LT.Y + 1)], Length(Module.Name), 0);

//  DumpMap(Module.Name + '_before.2d');

    Log('module found: %s', [Module.Name]);
    Result := CompileModule(Module);
//  DumpMap(Module.Name + '_after.2d');
    ClearModule(@Module);

    if Result = 0 then
    begin
      New(PM);
      PM^ := Module;

      GlobalRegisterModule(PM);
    end
    else
      DisposeModule(@Module);
  end;
end;


end.
