{
  -------------------------------------------------------------------------------
  概要
  -------------------------------------------------------------------------------
  このユニットは、Windows の共有メモリ（メモリマップトファイル）API
  CreateFileMapping / MapViewOfFile を Delphi から安全に利用するための
  基本クラス群を提供します。

  TSharedMemoryBase
    - 名前付き共有メモリの作成、マッピング、解放を管理する基礎クラス。
    - 固定サイズのバッファを確保し、任意のバイナリ／構造体データを
      読み書きできるよう設計されています。
    - ファイルハンドルを使用せず、純粋にメモリ上で共有されるローカルマップを生成します。

  TSharedMemoryStringList
    - 固定長文字列の配列を共有メモリ上に配置する実装クラス。
    - Add / IndexOf / Strings[] などのシンプルなインターフェイスを持ち、
      複数フォームまたは複数プロセス間で文字列リストを共有可能です。
    - メモリサイズは Create 時に行数（MaxLines）と文字列長（MaxLen）で指定します。

  -------------------------------------------------------------------------------
  特徴
  -------------------------------------------------------------------------------
  ・共有メモリの生存期間は CreateFree に対応し、自動的にハンドルを管理。
  ・固定長構造のため、可変長文字列やレコード破壊の心配がありません。
  ・同一マップ名を指定することで、複数プロセス／フォーム間でデータを共有可能。
  ・TStringList 互換の簡易インターフェイス（Add / Count / Strings[]）を提供。

  -------------------------------------------------------------------------------
  注意事項
  -------------------------------------------------------------------------------
  ・固定サイズ構造のため、可変長文字列（UnicodeString / AnsiString）は使用できません。
  ・メモリサイズを超える書き込みは自動的に無視されます（Add → False を返す）。
  ・同名マップを複数生成した場合、同一の物理領域を共有します。
  ・このユニットは OS の IPC（プロセス間通信）機能を直接利用しており、
    ネットワーク通信やファイル同期を目的としたものではありません。

  -------------------------------------------------------------------------------
  対応環境
  -------------------------------------------------------------------------------
  - Delphi 10 以降
  - Windows 10 / 11
  - 32bit / 64bit 対応

  -------------------------------------------------------------------------------
  License
  -------------------------------------------------------------------------------
  MIT License
  Copyright (c) 2025 VRAMWiz
}
unit SharedMemoryBase;

interface

uses
  Windows, SysUtils, Math;

type
  { 汎用共有メモリ管理クラス }
  TSharedMemoryBase = class
  private
    FHandle: THandle;   // CreateFileMapping のハンドル
    FView: Pointer;     // MapViewOfFile の結果（マップ先アドレス）
    FSize: Integer;     // 確保サイズ（バイト）
    FName: string;      // 共有メモリ名（例："Local\SharedMemTest"）
    FIsOwner: Boolean;  // 初回生成フラグ（既存なら False）

    function GetIsOpened: Boolean;
  protected
    { 内部ユーティリティ：基本型アクセス（再利用用） }
    procedure WriteInt(Dest: PInteger; const Value: Integer);
    function  ReadInt(Src: PInteger): Integer;

    procedure WriteString(Dest: PWideChar; MaxLen: Integer; const Value: string);
    function  ReadString(Src: PWideChar; MaxLen: Integer): string;

    procedure ClearBuffer(Dest: Pointer; Size: Integer);

    { マッピング操作（派生側でフック可能） }
    function Map: Boolean; virtual;
    procedure Unmap; virtual;
  public
    constructor Create(const AName: string; ASize: Integer); virtual;
    destructor Destroy; override;

    { 状態確認 }
    property Handle: THandle read FHandle;
    property View: Pointer read FView;
    property Size: Integer read FSize;
    property Name: string read FName;
    property IsOpened: Boolean read GetIsOpened;
    property IsOwner: Boolean read FIsOwner;
  end;

  { 固定スロット方式の共有文字列リストクラス      }

  TSharedMemoryStringList = class(TSharedMemoryBase)
  private
    FMaxLines: Integer;  // 最大行数
    FMaxLen: Integer;    // 1行あたり最大文字数（WideChar単位）

    function GetCount: Integer;
    procedure SetCount(Value: Integer);
    function GetString(Index: Integer): string;
    procedure SetString(Index: Integer; const Value: string);
  public
    { 生成時に上限を指定して確保サイズを自動算出 }
    constructor Create(const AName: string; AMaxLines, AMaxLen: Integer); reintroduce; virtual;

    function Add(const S: string): Boolean;      // 行追加 True:成功
    function IndexOf(const S: string): Integer;  // 文字列検索

    { 行数と個別アクセス }
    property Count: Integer read GetCount write SetCount;
    property Strings[Index: Integer]: string read GetString write SetString; default;

    { パラメータ確認用 }
    property MaxLines: Integer read FMaxLines;
    property MaxLen: Integer read FMaxLen;
  end;

implementation

{----------------------------------------------}
{               内部ユーティリティ              }
{----------------------------------------------}

procedure TSharedMemoryBase.WriteInt(Dest: PInteger; const Value: Integer);
begin
  if (FView <> Pointer(0)) and (Dest <> nil) then
    Dest^ := Value;
end;

function TSharedMemoryBase.ReadInt(Src: PInteger): Integer;
begin
  if (FView <> Pointer(0)) and (Src <> nil) then
    Result := Src^
  else
    Result := 0;
end;

procedure TSharedMemoryBase.WriteString(Dest: PWideChar; MaxLen: Integer; const Value: string);
var
  L: Integer;
begin
  if (FView = Pointer(0)) or (Dest = nil) or (MaxLen <= 0) then Exit;

  // 上限 - 1（#0 終端分）でクリップ
  L := Min(Length(Value), MaxLen - 1);
  if L > 0 then
    Move(Value[1], Dest^, L * SizeOf(WideChar));
  Dest[L] := #0;
end;

function TSharedMemoryBase.ReadString(Src: PWideChar; MaxLen: Integer): string;
var
  L: Integer;
begin
  Result := '';
  if (FView = Pointer(0)) or (Src = nil) or (MaxLen <= 0) then Exit;

  L := lstrlenW(Src);
  if L > MaxLen then
    L := MaxLen;
  if L > 0 then
    SetString(Result, Src, L)
  else
    Result := '';
end;

procedure TSharedMemoryBase.ClearBuffer(Dest: Pointer; Size: Integer);
begin
  if (FView <> Pointer(0)) and (Dest <> nil) and (Size > 0) then
    FillChar(Dest^, Size, 0);
end;

{----------------------------------------------}
{               マッピング制御                 }
{----------------------------------------------}

function TSharedMemoryBase.Map: Boolean;
begin
  Result := False;
  if FHandle = 0 then Exit;

  FView := MapViewOfFile(FHandle, FILE_MAP_ALL_ACCESS, 0, 0, FSize);
  Result := (FView <> Pointer(0));
end;

procedure TSharedMemoryBase.Unmap;
begin
  if FView <> Pointer(0) then
  begin
    UnmapViewOfFile(FView);
    FView := Pointer(0);
  end;
end;

{----------------------------------------------}
{                 生成／破棄                   }
{----------------------------------------------}

constructor TSharedMemoryBase.Create(const AName: string; ASize: Integer);
begin
  inherited Create;

  FHandle := 0;
  FView := Pointer(0);
  FSize := ASize;
  FName := AName;
  FIsOwner := False;

  if (FName = '') or (FSize <= 0) then
    raise Exception.Create('Invalid shared memory parameters.');

  // 共有メモリ作成（既存なら接続）
  FHandle := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, Cardinal(FSize), PChar(FName));
  if FHandle = 0 then
    raise Exception.CreateFmt('Failed to create file mapping (%s).', [SysErrorMessage(GetLastError)]);

  // 既存かどうか
  FIsOwner := (GetLastError <> ERROR_ALREADY_EXISTS);

  if not Map then
  begin
    CloseHandle(FHandle);
    FHandle := 0;
    raise Exception.Create('Failed to map shared memory.');
  end;

  // 新規作成時のみ初期化
  if FIsOwner then
    ClearBuffer(FView, FSize);
end;

destructor TSharedMemoryBase.Destroy;
begin
  try
    Unmap;
    if FHandle <> 0 then
    begin
      CloseHandle(FHandle);
      FHandle := 0;
    end;
  finally
    inherited Destroy;
  end;
end;

function TSharedMemoryBase.GetIsOpened: Boolean;
begin
  Result := (FView <> Pointer(0));
end;

{ TSharedMemoryStringList }

type
  PWideCharArray = ^TWideCharArray;
  TWideCharArray = array[0..0] of WideChar;

function TSharedMemoryStringList.GetCount: Integer;
begin
  if (View = nil) then
    Exit(0);
  Result := PInteger(View)^;
end;

procedure TSharedMemoryStringList.SetCount(Value: Integer);
begin
  if (View = nil) then Exit;
  if Value < 0 then Value := 0;
  if Value > FMaxLines then Value := FMaxLines;
  PInteger(View)^ := Value;
end;

function TSharedMemoryStringList.GetString(Index: Integer): string;
var
  LineStart: PWideChar;
  Offset: Integer;
begin
  Result := '';
  if (View = nil) then Exit;
  if (Index < 0) or (Index >= FMaxLines) then Exit;

  Offset := SizeOf(Integer) + (Index * FMaxLen * SizeOf(WideChar));
  LineStart := PWideChar(PByte(View) + Offset);
  Result := ReadString(LineStart, FMaxLen);
end;

function TSharedMemoryStringList.IndexOf(const S: string): Integer;
var
  i, C: Integer;
  L: string;
begin
  Result := -1;
  if (FView = nil) then Exit;

  C := GetCount;
  for i := 0 to C - 1 do
  begin
    L := GetString(i);
    if SameText(L, S) then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

procedure TSharedMemoryStringList.SetString(Index: Integer; const Value: string);
var
  LineStart: PWideChar;
  Offset: Integer;
begin
  if (View = nil) then Exit;
  if (Index < 0) or (Index >= FMaxLines) then Exit;

  Offset := SizeOf(Integer) + (Index * FMaxLen * SizeOf(WideChar));
  LineStart := PWideChar(PByte(View) + Offset);
  WriteString(LineStart, FMaxLen, Value);
end;

constructor TSharedMemoryStringList.Create(
  const AName: string; AMaxLines, AMaxLen: Integer);
begin
  FMaxLines := Max(AMaxLines, 1);
  FMaxLen   := Max(AMaxLen, 2);

  // Count(Integer) + Lines[MaxLines, MaxLen] の分を確保
  inherited Create(
    AName,
    SizeOf(Integer) + (FMaxLines * (FMaxLen * SizeOf(WideChar)))
  );

  // 新規作成時のみ初期化
  if IsOwner then
    SetCount(0);
end;

function TSharedMemoryStringList.Add(const S: string): Boolean;
var
  C: Integer;
begin
  Result := False;
  if (View = nil) then Exit;

  C := GetCount;
  if (C >= FMaxLines) then Exit; // 上限

  // 追加
  SetString(C, S);
  Inc(C);
  SetCount(C);
  Result := True;
end;


end.

