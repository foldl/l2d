unit MiscUtils;

interface

uses
  SysUtils, Windows;

const
  cTab = #9;

type

  TLogStaff = (lsSeparator, lsBigError);

  TSetOfChar = set of Char;

const
  White = FOREGROUND_BLUE or FOREGROUND_GREEN or FOREGROUND_RED or FOREGROUND_INTENSITY;
  
  clInformation = FOREGROUND_GREEN or FOREGROUND_INTENSITY;
  clError       = FOREGROUND_RED or FOREGROUND_INTENSITY;
  clWarning     = FOREGROUND_GREEN or FOREGROUND_RED or FOREGROUND_INTENSITY;

procedure LogInfo(const Fmt: string; Params: array of const);
procedure LogError(const Fmt: string; Params: array of const);
procedure LogWarning(const Fmt: string; Params: array of const);
procedure Log(const Fmt: string; Params: array of const; const LogColor: Integer = White);
procedure LogStaff(const Staff: TLogStaff);

function Fetch(var Str: string; const Delimiter: string): string;

function CreateDirs(const Dir: string): Boolean;
function SpaceStr(const Len: Integer): string;

implementation

var
  hConsole: Cardinal = 0;
  LastColor: Word = 0;

const
  TEXT_COLOR_MASK = $FF;
  
procedure TextColor(const Color: Word);
var
  Info: TConsoleScreenBufferInfo;
begin
  if hConsole = 0 then
    hConsole := GetStdHandle(STD_OUTPUT_HANDLE);

  if hConsole <> INVALID_HANDLE_VALUE then
  begin
     GetConsoleScreenBufferInfo(hConsole, Info) ;
     LastColor := Info.wAttributes and TEXT_COLOR_MASK;
     SetConsoleTextAttribute(hConsole, Color and TEXT_COLOR_MASK);
  end;
end;

procedure RestoreTextColor;
begin
  if hConsole = 0 then
    hConsole := GetStdHandle(STD_OUTPUT_HANDLE);

  if hConsole <> INVALID_HANDLE_VALUE then
     SetConsoleTextAttribute(hConsole, LastColor and TEXT_COLOR_MASK);
end;

{
function SetTextBKColor(const Color: Word): Word;
const
  TEXT_COLOR_MASK = $FFFF;
var
  Info: TConsoleScreenBufferInfo ;
  hStdin: Cardinal;
begin
  hStdin := GetStdHandle(STD_OUTPUT_HANDLE);
  Result := 0;
  if hStdin <> INVALID_HANDLE_VALUE then
  begin
     GetConsoleScreenBufferInfo(hStdin, Info) ;
     SetConsoleTextAttribute(hStdin, Color and TEXT_COLOR_MASK);
     Result := Info.wAttributes and TEXT_COLOR_MASK;
  end;
end;
}

procedure Log(const Fmt: string; Params: array of const; const LogColor: Integer);
var
  str: string;
begin
  str := Format(Fmt, Params);

  TextColor(LogColor);
  Writeln(str);
  TextColor(White);;
end;

procedure LogStaff(const Staff: TLogStaff);
begin
  case Staff of
    lsSeparator : Log('===================================', []);
    lsBigError  : Log('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!', []);
  else
  end;
end;

procedure LogInfo(const Fmt: string; Params: array of const);
begin
  MiscUtils.Log(Fmt, Params, clInformation);
end;

procedure LogError(const Fmt: string; Params: array of const);
begin
  MiscUtils.Log(Fmt, Params, clError);
end;

procedure LogWarning(const Fmt: string; Params: array of const);
begin
  MiscUtils.Log(Fmt, Params, clWarning);
end;

function Fetch(var Str: string; const Delimiter: string): string;
var
  Posi: Integer;
begin
  Posi := Pos(Delimiter, Str);
  if Posi > 0 then
  begin
    Result := Copy(Str, 1, Posi - 1);
    Delete(Str, 1, Posi + Length(Delimiter) - 1);
  end
  else begin
    Result := Str;
    Str    := '';
  end;
end;

function HexFixup(const HexStr: string): string;
begin
  Result := HexStr;
  if Length(HexStr) < 2 then
    Exit
  else begin
    if UpperCase(Copy(HexStr, 1, 2)) = '0X' then
      Delete(Result, 1, 2)
    else if HexStr[1] = '$' then
      Delete(Result, 1, 1)
    else;
  end;
end;

function TrimChars(const S: string; Chars: TSetOfChar): string;
var
  I, L: Integer;
begin
  L := Length(S);
  I := 1;
  while (I <= L) and (S[I] in Chars) do Inc(I);
  if I > L then Result := '' else
  begin
    while S[L] in Chars do Dec(L);
    Result := Copy(S, I, L - I + 1);
  end;
end;

function CreateDirs(const Dir: string): Boolean;
var
  i: Integer;
begin
  for i := 4 to Length(Dir) do
  begin
    if Dir[i] = '\' then
      CreateDir(Copy(Dir, 1, i - 1));
  end;
  CreateDir(Dir);
  Result := DirectoryExists(Dir);
end;

function SpaceStr(const Len: Integer): string;
begin
  if Len < 1 then
    Exit;
  SetLength(Result, Len);
  FillChar(Result[1], Len, Ord(' '));
end;

end.
