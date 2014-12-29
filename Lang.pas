unit Lang;

interface

uses
  Types;
  
type

  PModule = ^TModule;
  
  TValueType = (vtBase, vtPair, vtInl, vtInr);

  PValue = ^TValue;
  TValue = record
    _RefCount: Integer;
    case vt : TValueType of
      vtPair: (Left, Right: PValue);
      vtInl, vtInr:  (Padding: PValue);
  end;

  PValueNode =^TValueNode;
  TValueNode = record
    Next: PValueNode;
    Value: PValue;
  end;
  
  TFace    = (fW, fN, fE, fS);
  TInFace  = (W, N);
  TOutFace = (E, S);

  TExprType = (etBase, etPair, etInl, etInr, etInface, etOutface);
  PExpr = ^TExpr;
  TExpr = record
    case et: TExprType of
      etPair:       (Left, Right: PExpr);
      etInl, etInr: (Padding: PExpr);
      etInface:     (Inface: TInFace);
      etOutface:    (Outface: TOutFace);
  end;

  TExprTypeSet = set of TExprType;
  TInFaceSet = set of TInFace;
  TOutFaceSet = set of TOutFace;
  
  TBlockCommand = (bcSplit, bcSend, bcCase, bcUse);
  PBlock = ^TBlock;
  PWire = ^TWire;

  TBlock = record
    Next: PBlock;
    LT, RB: TPoint;
    N, W, E, S: PWire;
    Expr: PExpr;
    InFaceSet: TInFaceSet;
    UseModuleName: string;
    case bc : TBlockCommand of
      bcCase:             (OutFace1, OutFace2: TOutFace);
      bcSend:             (Expr2: PExpr);
      bcUse:              (Module: PModule);
  end;

  TWire = record
    Next:   PWire;
    Source: PBlock;
    Target: PBlock;
    Value:  PValue;
    ValueNode: TValueNode;
    SourcePt, TargetPt: TPoint;
    SourceFace, TargetFace: TFace;
  end;

  PWireNode =^TWireNode;
  TWireNode = record
    Next: PWireNode;
    Wire: PWire;
  end;

  TModule = record
    Next: PModule;
    bLinked: Boolean;
     
    Name: string;
    LT, RB: TPoint;

    Depth: Integer;

    // for memory management
    RootBlock: TBlock;
    RootWire:  TWire;

    // input
    N, W: PWire;

    // output
    OutputWires: TWireNode;
  end;

function DisExpr(Expr: PExpr): string;
function DisValue(Value: PValue): string;

function ExprToValue(Expr: PExpr): PValue; overload;
function ExprTypeSet(Expr: PExpr): TExprTypeSet;
function ExprInFaceSet(Expr: PExpr): TInFaceSet;
function ExprOutFaceSet(Expr: PExpr): TOutFaceSet;
procedure ExprPropSet(Expr: PExpr; var TypeSet: TExprTypeSet;
                      var InFaceSet: TInFaceSet; var OutFaceSet: TOutFaceSet);

procedure DisposeModule(Module: PModule);
procedure DisposeBlock(var Block: PBlock);
procedure DisposeExpr(var Expr: PExpr);

function  SizeOfModule(Module: PModule): Integer;

function  CaptureValue(Value: PValue): PValue;
procedure ReleaseValue(var Value: PValue);

function  UniqueValue(Value: PValue): PValue;

function FindModule(const Name: string): PModule;

procedure GlobalRegisterModule(Module: PModule);
procedure GlobalDisposeModule(Module: PModule);
procedure GlobalEraseAll;

function ExcecuteModule(Module: PModule; Input1, Input2: PValue;
                        var PrimaryOutput: PValue): Integer;

var
  gModule: TModule;

const DirectionedWire: set of Char = ['-', '|', '<', '>', 'v', '^'];
const BlockBolder    : set of Char = ['=', '!', '*'];
const WireChar       : set of Char = ['-', '|', '<', '>', 'v', '^', '+', '#'];
const HWireChar      : set of Char = ['-',      '<', '>',           '+', '#'];
const VWireChar      : set of Char = [     '|',           'v', '^', '+', '#'];

implementation

uses
  MiscUtils;
  
function ExprTypeSet(Expr: PExpr): TExprTypeSet;

  procedure Calc(Expr: PExpr; var R: TExprTypeSet);
  begin
    if Expr = nil then
      Exit;

    Include(R, Expr.et);
    case Expr.et of
      etPair: begin
                Calc(Expr.Left, R);
                Calc(Expr.Right, R);
              end;
      etInl, etInr: Calc(Expr.Padding, R);
    end;
  end;

begin
  Result := [];
  Calc(Expr, Result);
end;

function ExprInFaceSet(Expr: PExpr): TInFaceSet;

  procedure Calc(Expr: PExpr; var R: TInFaceSet);
  begin
    if Expr = nil then
      Exit;

    if Expr.et = etInface then
      Include(R, Expr.Inface);
      
    case Expr.et of
      etPair: begin
                Calc(Expr.Left, R);
                Calc(Expr.Right, R);
              end;
      etInl, etInr: Calc(Expr.Padding, R);
    end;
  end;

begin
  Result := [];
  Calc(Expr, Result);
end;

function ExprOutFaceSet(Expr: PExpr): TOutFaceSet;

  procedure Calc(Expr: PExpr; var R: TOutFaceSet);
  begin
    if Expr = nil then
      Exit;

    if Expr.et = etOutface then
      Include(R, Expr.Outface);

    case Expr.et of
      etPair: begin
                Calc(Expr.Left, R);
                Calc(Expr.Right, R);
              end;
      etInl, etInr: Calc(Expr.Padding, R);
    end;
  end;

begin
  Result := [];
  Calc(Expr, Result);
end;

procedure ExprPropSet(Expr: PExpr; var TypeSet: TExprTypeSet;
                      var InFaceSet: TInFaceSet; var OutFaceSet: TOutFaceSet);

  procedure Calc(Expr: PExpr);
  begin
    if Expr = nil then
      Exit;

    Include(TypeSet, Expr.et);
    
    if Expr.et = etInface then
      Include(InFaceSet, Expr.Inface);

    if Expr.et = etOutface then
      Include(OutFaceSet, Expr.Outface);

    case Expr.et of
      etPair: begin
                Calc(Expr.Left);
                Calc(Expr.Right);
              end;
      etInl, etInr: Calc(Expr.Padding);
    end;
  end;

begin
  TypeSet := [];
  InFaceSet := [];
  OutFaceSet := [];
  Calc(Expr);
end;

function DisExpr(Expr: PExpr): string;
begin
  if Expr = nil then
  begin
    Result := 'nil';
    Exit;
  end;

  Result := '?';
  case Expr.et of
    etBase: Result := '()';
    etPair: Result := '(' + DisExpr(Expr.Left) + ', ' + DisExpr(Expr.Right) + ')';
    etInl : Result := 'Inl ' + DisExpr(Expr.Padding);
    etInr : Result := 'Inr ' + DisExpr(Expr.Padding);
    etInface:
      case Expr.Inface of
        W: Result := 'W';
        N: Result := 'N';
      end;
    etOutface:
      case Expr.Outface of
        E: Result := 'E';
        S: Result := 'S';
      end;
  end;
end;

function DisValue(Value: PValue): string;
begin
  if Value = nil then
  begin
    Result := 'nil';
    Exit;
  end;

  Result := '?';
  case Value.vt of
    vtBase: Result := '()';
    vtPair: Result := '(' + DisValue(Value.Left) + ', ' + DisValue(Value.Right) + ')';
    vtInl : Result := 'Inl ' + DisValue(Value.Padding);
    vtInr : Result := 'Inr ' + DisValue(Value.Padding);
  end;
end;

procedure DisposeBlock(var Block: PBlock);
begin
  DisposeExpr(Block.Expr);
  if Block.bc = bcSend then
    DisposeExpr(Block.Expr2);
  Block.Expr := nil;
  Block.Expr2 := nil;
end;

procedure DisposeExpr(var Expr: PExpr);
begin
  if Expr = nil then
    Exit;
  case Expr.et of
    etPair:
      begin
        DisposeExpr(Expr.Left);
        DisposeExpr(Expr.Right);
      end;
    etInl, etInr:
      begin
        DisposeExpr(Expr.Padding);
      end;
  end;
  Dispose(Expr);
  Expr := nil;
end;

function FindModule(const Name: string): PModule;
begin
  Result := gModule.Next;
  while Result <> nil do
  begin
    if Result.Name = Name then
      Break
    else
      Result := Result.Next;
  end;
end;

function  CaptureValue(Value: PValue): PValue;
begin
  Result := Value;

  if Value <> nil then
  begin
//  Log('++ref @%p, %s', [Value, DisValue(Value)]);
    Inc(Value._RefCount);
  end;
end;

procedure ReleaseValue(var Value: PValue);
begin
  if Value = nil then
    Exit;

//Log('--ref @%p --> %d, %s', [Value, Value._RefCount - 1, DisValue(Value)]);
  Dec(Value._RefCount);
  if Value._RefCount <= 0 then
  begin
    case Value.vt of
    vtPair:
      begin
        ReleaseValue(Value.Left);
        ReleaseValue(Value.Right);
      end;
    vtInl, vtInr:
      begin
        ReleaseValue(Value.Padding);
      end;
    end;
//  LogWarning('mm: dispose data @%p', [Value]);
    Dispose(Value);
    Value := nil;
  end;

  Value := nil;
end;

function ExprToValue(Expr: PExpr): PValue; overload;

  procedure ExprToV(Expr: PExpr; var P: PValue);
  begin
    New(P);
//  Log('new value @%p', [P]);
    FillChar(P^, SizeOf(P^), 0);
    P.vt := vtBase;
    if Expr = nil then
      Exit;
      
    case Expr.et of
      etPair:
        begin
          P.vt := vtPair;
          ExprToV(Expr.Left, P.Left);
          ExprToV(Expr.Right, P.Right);
          CaptureValue(P.Left);
          CaptureValue(P.Right);
        end;
      etInl, etInr:
        begin
          if Expr.et = etInl then
            P.vt := vtInl
          else
            P.vt := vtInr;
          ExprToV(Expr.Padding, P.Padding);
          CaptureValue(P.Padding);
        end;
      etBase: P.vt := vtBase;
    else
      LogError('expression "%s" cannot be evaluated at present.', [DisExpr(Expr)]);
    end;
  end;
begin
  Result := nil;

  if Expr <> nil then
    ExprToV(Expr, Result);
end;

function ExprToValue(Expr: PExpr; N, W: PValue): PValue; overload;

  procedure ExprToV(Expr: PExpr; var P: PValue);
  begin
    if Expr.et <> etInface then
    begin
      New(P);
//    Log('new value @%p', [P]);
      FillChar(P^, SizeOf(P^), 0);
      P.vt := vtBase;
    end;
    case Expr.et of
      etPair:
        begin
          P.vt := vtPair;
          ExprToV(Expr.Left, P.Left);
          ExprToV(Expr.Right, P.Right);
          CaptureValue(P.Left);
          CaptureValue(P.Right);
        end;
      etInl, etInr:
        begin
          if Expr.et = etInl then
            P.vt := vtInl
          else
            P.vt := vtInr;
          ExprToV(Expr.Padding, P.Padding);
          CaptureValue(P.Padding);
        end;
      etBase: P.vt := vtBase;
      etInface:
        begin
          case Expr.Inface of
            Lang.N: P := N;
            Lang.W: P := W;
          end;
        end;
    else
      LogError('expression "%s" cannot be evaluated at present.', [DisExpr(Expr)]);
    end;
  end;
begin
  Result := nil;

  if Expr <> nil then
    ExprToV(Expr, Result);
end;

function  UniqueValue(Value: PValue): PValue;
begin
  Result := nil;
end;

function LinkModules(Module: PModule): Integer;
var
  PB: PBlock;
  PM: PModule;
begin
  Result := 0;
  PB := Module.RootBlock.Next;
  Module.bLinked := True;
  while PB <> nil do
  begin
    if PB.bc = bcUse then
    begin
      PB.Module := FindModule(PB.UseModuleName);
      if PB.Module <> nil then
      begin
        Log('"%s" in module "%s" linked.', [PB.UseModuleName, Module.Name]);
      end
      else begin
//        LogError('"%s" link failed.', [PB.UseModuleName]);
        Module.bLinked := False;
      end;
    end;

    PB := PB.Next;
  end;

  PM := gModule.Next;
  while PM <> nil do
  begin
    if (not PM.bLinked) and (PM <> Module) then
    begin
      PB := PM.RootBlock.Next;
      PM.bLinked := True;
      while PB <> nil do
      begin
        if PB.bc = bcUse then
        begin
          if PB.UseModuleName = Module.Name then
          begin
            PB.Module := Module;
            Log('"%s" in module "%s" linked.', [PB.UseModuleName, PM.Name])
          end
          else if PB.Module = nil then
            PM.bLinked := False
          else;
        end;
        PB := PB.Next;
      end;
    end;
    
    PM := PM.Next;
  end;
end;

procedure GlobalRegisterModule(Module: PModule);
var
  P: PModule;
begin
  P := FindModule(Module.Name);
  if P <> nil then
  begin
    LogWarning('updating module "%s"', [Module.Name]);
    GlobalDisposeModule(P);
  end;

  // add Module to the list
  Module.Next := gModule.Next;
  gModule.Next := Module;

  LinkModules(Module);
end;

procedure GlobalDisposeModule(Module: PModule);
var
  P: PModule;
  B: PBlock;
begin
  // release the references to this module
  P := gModule.Next;
  while P <> nil do
  begin
    B := P.RootBlock.Next;
    while B <> nil do
    begin
      if (B.bc = bcUse) and (B.Module = Module) then
      begin
        B.Module := nil;
        P.bLinked := False;
      end;
        
      B := B.Next;
    end;

    P := P.Next;
  end;

  P := @gModule;
  while (p <> nil) and (P.Next <> Module) do
    P := P.Next;
  if p <> nil then
  begin
    P.Next := Module.Next;
    DisposeModule(Module);
    Dispose(Module);
  end
  else
    LogError('module "%s" not find in global list.', [Module.Name]);
end;

procedure GlobalEraseAll;
var
  Module: PModule;
begin
  while gModule.Next <> nil do
  begin
    Module := gModule.Next;
    gModule.Next := Module.Next;
    DisposeModule(Module);
    Dispose(Module);
  end;
end;

function SizeOfStr(const s: string): Integer;
begin
  Result := Length(s) + SizeOf(Integer);
end;

function SizeOfBlocks(Module: PModule): Integer;
var
  pb: PBlock;
begin
  pb := Module.RootBlock.Next;
  Result := 0;
  while pb <> nil do
  begin
    Inc(Result, SizeOf(pb^) + SizeOfStr(pb.UseModuleName));
    pb := pb.Next;
  end;
end;

function SizeOfValue(Value: PValue): Integer;
begin
  Result := 0;
  if Value <> nil then
    case Value.vt of
      vtPair:
        Result := SizeOf(Value^) + SizeOfValue(Value.Left) + SizeOfValue(Value.Right);
      vtInl, vtInr:
        Result := SizeOf(Value^) + SizeOfValue(Value.Padding);
    end;
end;

function SizeOfValueNode(ValueNode: PValueNode): Integer;
var
  P: PValueNode;
begin
  P := ValueNode;
  Result := 0;
  while P <> nil do
  begin
    Inc(Result, SizeOfValue(P.Value));
    P := P.Next;
  end;
end;

function SizeOfWires(Module: PModule): Integer;
var
  pw: PWire;
begin
  pw := Module.RootWire.Next;
  Result := 0;
  while pw <> nil do
  begin
    Inc(Result, SizeOf(pw^) + SizeOfValueNode(pw.ValueNode.Next));
    pw := pw.Next;
  end;
end;

function SizeOfOutputWires(Module: PModule): Integer;
var
  pwn: PWireNode;
begin
  pwn := Module.OutputWires.Next;
  Result := 0;
  while pwn <> nil do
  begin
    Inc(Result, SizeOf(pwn^));
    pwn := pwn.Next; 
  end;
end;

function  SizeOfModule(Module: PModule): Integer;
begin
  Result := 0;
  if Module <> nil then
    Result := SizeOf(Module^) + SizeOfBlocks(Module) + SizeOfWires(Module)
              + SizeOfOutputWires(Module)
              + SizeOfStr(Module.Name);
end;

function NewModuleInstance(Module: PModule): Integer;
var
  PW: PWire;
  PVN: PValueNode;
begin
  Result := 0;
  if Module = nil then
    Exit;
  Inc(Module.Depth);
    
  PW := Module.RootWire.Next;
  while PW <> nil do
  begin
    New(PVN);
    PVN.Next := PW.ValueNode.Next;
    PW.ValueNode.Next := PVN;
    PVN.Value := PW.Value;    // no reference count issue here
    PW.Value := nil;
    
    PW := PW.Next;
  end;

  Result := Module.Depth;
end;

function DisposeModuleInstance(Module: PModule): Integer;
var
  PW: PWire;
  PVN: PValueNode;
begin
//LogWarning('DisposeModuleInstance module "%s".', [Module.Name]);

  Result := 0;
  if Module = nil then
    Exit;
  Dec(Module.Depth);
  if Module.Depth < 0 then
  begin
    LogWarning('module "%s" may not has any instance.', [Module.Name]);
    Module.Depth := 0;
  end;
  
  Result := Module.Depth;

  PW := Module.RootWire.Next;
  while PW <> nil do
  begin
    ReleaseValue(PW.Value);
    
    PVN := PW.ValueNode.Next;
    if PVN <> nil then
    begin
      PW.ValueNode.Next := PVN.Next;
      PW.Value := PVN.Value;
      Dispose(PVN);
    end;
    
    PW := PW.Next;
  end;
end;

procedure DisposeModule(Module: PModule);
var
  pw: PWire;
  pb: PBlock;
  pwn: PWireNode;
begin
  // free instances
  while Module.Depth > 0 do
    DisposeModuleInstance(Module);

  while Module.RootWire.Next <> nil do
  begin
    pw := Module.RootWire.Next;
    Module.RootWire.Next := pw.Next;
    Dispose(pw);
  end;

  while Module.OutputWires.Next <> nil do
  begin
    pwn := Module.OutputWires.Next;
    Module.OutputWires.Next := pwn.Next;
    Dispose(pwn);
  end;

  while Module.RootBlock.Next <> nil do
  begin
    pb := Module.RootBlock.Next;
    Module.RootBlock.Next := pb.Next;
    DisposeBlock(pb);
    Dispose(pb);
  end;
end;

procedure ChangeWireCapture(var P: PWire; NewValue: PValue);
begin
  if Assigned(P) then
  begin
    if Assigned(P.Value) then ReleaseValue(P.Value);
    P.Value := CaptureValue(NewValue);
  end
  else
    P := nil;
end;

function ExcecuteModule(Module: PModule; Input1, Input2: PValue;
                        var PrimaryOutput: PValue): Integer;
var
  bRun, bErr: Boolean;
  PB: PBlock;
  PV, PV1, PV2: PValue;
  InfaceSet: TInfaceSet;
  SubOutput: PValue;

  procedure CheckModuleOutput(PW: PWire);
  begin
    if (PrimaryOutput = nil) and Assigned(PW) and (PW.Target = nil) and (PW.Value <> nil) then
    begin
      // transfer the reference
      PrimaryOutput := PW.Value;
      PW.Value := nil;
    end;
  end;

label
  next, quit;
begin
  if not Module.bLinked then
  begin
    LogError('some USE blocks in module "%s" have not been linked.', [Module.Name]);
    Result := -1;
    Exit;
  end;
    
  if NewModuleInstance(Module) > 32 then
  begin
    DisposeModuleInstance(Module);
    LogError('too many instance of module "%s" hava been created.', [Module.Name]);
    Result := -1;
    Exit;
  end;

  if Module.N <> nil then
    Module.N.Value := CaptureValue(Input1);
  if Module.W <> nil then
    Module.W.Value := CaptureValue(Input2);
    
  Result := 0;
  bRun := True;
  bErr := False;
  while bRun and (not bErr) and (not Assigned(PrimaryOutput)) do
  begin
    bRun := False;
    PB := Module.RootBlock.Next;
    while PB <> nil do
    begin
      if (PB.N <> nil) and (not Assigned(PB.N.Value)) then
        goto next;
      if (PB.W <> nil) and (not Assigned(PB.W.Value)) then
        goto next;
        
      PV1 := nil;
      PV2 := nil;
      if PB.N <> nil then
        PV1 := PB.N.Value;
      if PB.W <> nil then
        PV2 := PB.W.Value;

      // now execute
      case PB.bc of
        bcSplit:
          begin
            InfaceSet := [];
            if PB.N <> nil then
              Include(InfaceSet, N);
            if PB.W <> nil then
              Include(InfaceSet, W);

            if (InfaceSet * PB.InFaceSet) = PB.InFaceSet then
            begin
              PV := ExprToValue(PB.Expr, PV1, PV2);
              if PV.vt = vtPair then
              begin
                ChangeWireCapture(PB.S, PV.Left);
                ChangeWireCapture(PB.E, PV.Right);

                CheckModuleOutput(PB.S);
                CheckModuleOutput(PB.E);
              end
              else begin
                LogError('SPLIT needs a PAIR expression.', []);
                bErr := True;
              end;

              bRun := True;
            end;
          end;
        bcSend:
          begin
            InfaceSet := [];
            if PB.N <> nil then
              Include(InfaceSet, N);
            if PB.W <> nil then
              Include(InfaceSet, W);

            if (InfaceSet * PB.InFaceSet) = PB.InFaceSet then
            begin
              PV := ExprToValue(PB.Expr.Left, PV1, PV2);
              case PB.Expr.Right.Outface of
                E: begin
                     ChangeWireCapture(PB.E, PV);
                     CheckModuleOutput(PB.E);
                   end;
                S: begin
                     ChangeWireCapture(PB.S, PV);
                     CheckModuleOutput(PB.S);
                   end;
              else
                ReleaseValue(PV);
              end;

              if PB.Expr2 <> nil then
              begin
                PV := ExprToValue(PB.Expr2.Left, PV1, PV2);
                case PB.Expr2.Right.Outface of
                  E: begin
                       ChangeWireCapture(PB.E, PV);
                       CheckModuleOutput(PB.E);
                     end;
                  S: begin
                       ChangeWireCapture(PB.S, PV);
                       CheckModuleOutput(PB.S);
                     end;
                else
                  ReleaseValue(PV);
                end;
              end;

              bRun := True;
            end;
          end;
        bcCase:
          begin
            InfaceSet := [];
            if PB.N <> nil then
              Include(InfaceSet, N);
            if PB.W <> nil then
              Include(InfaceSet, W);

            if (InfaceSet * PB.InFaceSet) = PB.InFaceSet then
            begin
              if PV1 <> nil then
                PV := PV1
              else
                PV := PV2;

              case PV.vt of
                vtInl: if PB.OutFace1 = S then
                       begin
                         ChangeWireCapture(PB.S, PV.Padding);
                         CheckModuleOutput(PB.S);
                       end
                       else begin
                         ChangeWireCapture(PB.E, PV.Padding);
                         CheckModuleOutput(PB.E);
                       end;
                vtInr: if PB.OutFace2 = S then
                       begin
                         ChangeWireCapture(PB.S, PV.Padding);
                         CheckModuleOutput(PB.S);
                       end
                       else begin
                         ChangeWireCapture(PB.E, PV.Padding);
                         CheckModuleOutput(PB.E);
                       end;
              else
                LogWarning('CASE generates nothing.', []);
//                LogError('CASE needs a Inr or Inl expression.', []);
//                bErr := True;
              end;

              bRun := True;
            end;
          end;
        bcUse:
          begin
              
            Log('use "%s", N = %s, W = %s', [PB.UseModuleName, DisValue(PV1), DisValue(PV2)]);
            SubOutput := nil;
            ExcecuteModule(PB.Module, PV1, PV2, SubOutput);
            if PB.S <> nil then
            begin
              // transfer the reference
              PB.S.Value := SubOutput;
              SubOutput := nil;
              CheckModuleOutput(PB.S);
            end
            else if PB.E <> nil then
            begin
              // transfer the reference
              PB.E.Value := SubOutput;
              SubOutput := nil;
              CheckModuleOutput(PB.E);
            end
            else
              ReleaseValue(PrimaryOutput);

            bRun := True;
          end;
      else
        LogError('command not implemented', []);
      end;

      if bRun then
      begin
        // release input
        if PB.N <> nil then
          ReleaseValue(PB.N.Value);
        if PB.W <> nil then
          ReleaseValue(PB.W.Value);
      end;
next:
      PB := PB.Next;
    end;
  end;

quit:
  if Module.N <> nil then
    ReleaseValue(Module.N.Value);
  if Module.W <> nil then
    ReleaseValue(Module.W.Value);

//  if Module.FirstOutput <> nil then
//    ChangeWireCapture(PrimaryOutput, Module.FirstOutput.Value);
  
  DisposeModuleInstance(Module);
end;

end.
