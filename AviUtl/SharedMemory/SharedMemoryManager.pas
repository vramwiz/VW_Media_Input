unit SharedMemoryManager;

interface

uses
  System.SysUtils,System.Classes,SharedMemoryBase;

type
  {-----------------------------------------------------------
    共有メモリ管理クラス（1ユニット1クラス）
    ・テキストはレイヤー単位
    ・複数行は TStringList をユーザー側が用意し、渡す
    ・返却は行わず、書き込みのみを行う（責務分離）
  -----------------------------------------------------------}
  TSharedMemoryManager = class
  private
    FShared   : TSharedMemoryStringList;  // 共有メモリ本体
    FMaxLayers: Integer;                  // 最大レイヤー数
    FMax      : Integer;                  // 最大レイヤー数（外部公開用）
  public
    // 共有メモリ生成
    constructor Create(const Name: string; MaxLayers, MaxLen: Integer);
    destructor Destroy; override;

    // 単一行テキスト取得
    function  GetText(Layer: Integer): string;
    function  GetInt(Layer: Integer): Integer;
    function  GetFloat(Layer: Integer): Double;
    // 単一行テキスト書き込み
    procedure SetText(Layer: Integer; const Txt: string);
    procedure SetInt(Layer: Integer; const Value: Integer);
    procedure SetFloat(Layer: Integer; const Value: Double);
    // 複数行テキストを Dest に書き込む（返却はしない）
    procedure GetLines(Layer: Integer; Dest: TStringList);
    // 複数行テキストを書き込む（Src の内容を共有メモリへ保存）
    procedure SetLines(Layer: Integer; const Src: TStringList);
    // 最大行数を返す
    property MaxCount: Integer read FMax;
  end;

var
  GSharedDress        : TSharedMemoryManager;   // 服装共有メモリ
  GSharedFace         : TSharedMemoryManager;   // 表情共有メモリ
  GSharedFaceUID      : TSharedMemoryManager;   // 表情を複数PSDで管理するためのUID共有メモリ
  GSharedTalk         : TSharedMemoryManager;   // セリフからフレームを受け取る（レイヤー別）
  GSharedLipSyncSong  : TSharedMemoryManager;   // フィルター間で口パクソング共有メモリ
  GSharedEyeSyncBlink : TSharedMemoryManager;   // フィルター間で口パクトーク共有メモリ
  GSharedSong         : TSharedMemoryManager;   // 口パクソング共有メモリ
  GSharedPSDAnime     : TSharedMemoryManager;   // アニメーション共有メモリ
  GSharedBase         : TSharedMemoryManager;   // 入力プラグインとの共有メモリ
  GSharedPlugin       : TSharedMemoryManager;   // 拡張プラグインとの共有メモリ

implementation

{-----------------------------------------------------------
  基本構築
-----------------------------------------------------------}
constructor TSharedMemoryManager.Create(
  const Name: string; MaxLayers, MaxLen: Integer);
begin
  inherited Create;
  FMaxLayers := MaxLayers;
  FShared := TSharedMemoryStringList.Create(Name, MaxLayers, MaxLen);
  FMax    := MaxLayers
end;

destructor TSharedMemoryManager.Destroy;
begin
  FShared.Free;
  inherited Destroy;
end;

{-----------------------------------------------------------
  単一テキスト
-----------------------------------------------------------}
function TSharedMemoryManager.GetText(Layer: Integer): string;
begin
  if (Layer < 0) or (Layer >= FMaxLayers) then
    Exit('');
  Result := FShared.Strings[Layer];
end;

function TSharedMemoryManager.GetFloat(Layer: Integer): Double;
var
  str : string;
begin
  str := GetText(Layer);
  Result := StrToFloatDef(str,0);
end;

function TSharedMemoryManager.GetInt(Layer: Integer): Integer;
var
  str : string;
begin
  str := GetText(Layer);
  Result := StrToIntDef(str,0);
end;

procedure TSharedMemoryManager.SetText(Layer: Integer; const Txt: string);
begin
  if (Layer < 0) or (Layer >= FMaxLayers) then Exit;
  FShared.Strings[Layer] := Txt;
end;

procedure TSharedMemoryManager.SetFloat(Layer: Integer; const Value: Double);
var
  str : string;
begin
  str := FloatToStr(Value);
  SetText(Layer,str);
end;

procedure TSharedMemoryManager.SetInt(Layer: Integer; const Value: Integer);
var
  str : string;
begin
  str := IntToStr(Value);
  SetText(Layer,str);
end;

{-----------------------------------------------------------
  複数行：リストを渡してもらい、そこに書き込む
-----------------------------------------------------------}
procedure TSharedMemoryManager.GetLines(Layer: Integer; Dest: TStringList);
var
  S: string;
begin
  if Dest = nil then Exit;

  Dest.Clear;
  S := GetText(Layer);
  if S = '' then Exit;

  Dest.Text := S;  // CR/LF をそのまま流し込む
end;

procedure TSharedMemoryManager.SetLines(Layer: Integer; const Src: TStringList);
begin
  if Src = nil then Exit;
  SetText(Layer, Src.Text);  // CR/LF をまとめて保存
end;

{-----------------------------------------------------------
  グローバル生成／破棄
-----------------------------------------------------------}
initialization
begin
  GSharedDress        := TSharedMemoryManager.Create('Local\SharedDress'        , 100, 4000);
  GSharedFace         := TSharedMemoryManager.Create('Local\SharedFace'         , 100, 4000);
  GSharedFaceUID      := TSharedMemoryManager.Create('Local\GSharedFaceUID'     , 100, 4000);
  GSharedTalk         := TSharedMemoryManager.Create('Local\ShareTalk'          , 100, 4000);
  GSharedLipSyncSong  := TSharedMemoryManager.Create('Local\SharedLipSyncSong'  , 100, 4000);
  GSharedEyeSyncBlink := TSharedMemoryManager.Create('Local\SharedEyeSyncBlink' , 100, 4000);
  GSharedSong         := TSharedMemoryManager.Create('Local\GSharedSong'        , 100, 4000);
  GSharedPSDAnime     := TSharedMemoryManager.Create('Local\GSharedPSDAnime'    , 100, 4000);
  GSharedBase         := TSharedMemoryManager.Create('Local\GSharedBase'        , 100, 4000);
  GSharedPlugin       := TSharedMemoryManager.Create('Local\GSharedPlugin'      , 100, 4000);
end;

finalization
begin
  FreeAndNil(GSharedPlugin);
  FreeAndNil(GSharedBase);
  FreeAndNil(GSharedPSDAnime);
  FreeAndNil(GSharedSong);
  FreeAndNil(GSharedEyeSyncBlink);
  FreeAndNil(GSharedLipSyncSong);
  FreeAndNil(GSharedTalk);
  FreeAndNil(GSharedDress);
  FreeAndNil(GSharedFace);
  FreeAndNil(GSharedFaceUID);
end;

end.

