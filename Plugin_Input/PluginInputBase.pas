unit PluginInputBase;

interface

uses
  Winapi.Windows,System.SysUtils, AviUtl2InputTypes,Vcl.Graphics,Math;


function PluginInputOpen(fileName: LPCWSTR): INPUT_HANDLE;
function PluginInputClose(ih: INPUT_HANDLE): BOOL;
function PluginInputGetInfo(ih: INPUT_HANDLE; info: PInputInfo): BOOL;
function PluginInputReadVideo(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer;
function PluginInputConfig(hwnd: HWND; hinst: HINST): BOOL;

implementation

uses SharedMemoryManager;

type
  PFileContext = ^TFileContext;
  TFileContext = record
    Width   : Integer;              // 動画の横サイズ（ピクセル）
    Height  : Integer;              // 動画の縦サイズ（ピクセル）
    MaxSec  : Double;               // 動画の最大再生時間（秒）
    Rate    : Integer;              // AviUtl2 の rate（分子）
    Scale   : Integer;              // AviUtl2 の scale（分母）
    Info    : BITMAPINFOHEADER;     // AviUtlへ渡す動画フォーマット情報
  end;

procedure ParseBaseFileName(
  const FileName: string;
  out Width, Height: Integer;
  out MaxSec: Double;
  out Rate, Scale: Integer
);
var
  Base  : string;
  Parts : TArray<string>;
  Fps   : Double;
  P     : Integer;
begin
  // デフォルト値
  Width  := 1920;
  Height := 1080;
  MaxSec := 30.0;

  Fps   := 30.0;   // 論理FPS（ファイル名解釈用）
  Scale := 1;      // AviUtl2 scale（分母）

  // ファイル名のみ取り出して拡張子除去
  Base := ChangeFileExt(ExtractFileName(FileName), '');
  if Base = '' then Exit;

  // : があれば右側のみ採用（表示名を除外）
  P := Pos(':', Base);
  if P > 0 then
    Base := Copy(Base, P + 1, MaxInt);

  // 従来どおり _ 区切り解析
  Parts := Base.Split(['_']);

  // 幅・高さ
  if Length(Parts) >= 2 then
  begin
    Width  := StrToIntDef(Parts[0], Width);
    Height := StrToIntDef(Parts[1], Height);
    MaxSec := 0.0;
  end;

  // 秒
  if Length(Parts) >= 3 then
    MaxSec := StrToFloatDef(Parts[2], MaxSec);

  // fps（論理値）
  if Length(Parts) >= 4 then
    Fps := StrToFloatDef(Parts[3], Fps);

  // scale
  if Length(Parts) >= 5 then
    Scale := StrToIntDef(Parts[4], Scale);

  if Scale <= 0 then
    Scale := 1;

  // AviUtl2 用 rate を算出
  Rate := Round(Fps * Scale);
  if Rate <= 0 then
    Rate := 30;
end;
//------------------------------------------------------------------------------
// ファイルを開く
//------------------------------------------------------------------------------
function PluginInputOpen(fileName: LPCWSTR): INPUT_HANDLE;
var
  Ctx   : PFileContext;
  Name  : string;
begin
  Result := nil;

  New(Ctx);
  FillChar(Ctx^, SizeOf(Ctx^), 0);

  try
    Name := string(fileName);

    // ファイル名からサイズ・時間・rate・scale を取得
    ParseBaseFileName(
      Name,
      Ctx^.Width,
      Ctx^.Height,
      Ctx^.MaxSec,
      Ctx^.Rate,
      Ctx^.Scale
    );

    // AviUtlへ渡す画像情報
    Ctx^.Info.biSize        := SizeOf(BITMAPINFOHEADER);
    Ctx^.Info.biWidth       := Ctx^.Width;
    Ctx^.Info.biHeight      := Ctx^.Height;
    Ctx^.Info.biPlanes      := 1;
    Ctx^.Info.biBitCount    := 32;
    Ctx^.Info.biCompression := BI_RGB;
    Ctx^.Info.biSizeImage   := Ctx^.Width * Ctx^.Height * 4;

    Result := Ctx;
  except
    Dispose(Ctx);
    Result := nil;
  end;
end;



//------------------------------------------------------------------------------
// ファイルを閉じる
//------------------------------------------------------------------------------
function PluginInputClose(ih: INPUT_HANDLE): BOOL;
var
  Ctx: PFileContext;
begin
  Result := False;
  if ih = nil then Exit;

  Ctx := PFileContext(ih);

  Dispose(Ctx);
  Result := True;
end;

//------------------------------------------------------------------------------
// 情報取得
//------------------------------------------------------------------------------
function PluginInputGetInfo(ih: INPUT_HANDLE; info: PInputInfo): BOOL;
var
  Ctx: PFileContext;
begin
  Result := False;
  if (ih = nil) or (info = nil) then Exit;

  Ctx := PFileContext(ih);

  FillChar(info^, SizeOf(TInputInfo), 0);
  info^.flag := INPUT_INFO_FLAG_VIDEO;

  // AviUtl2 正規値をそのまま設定
  info^.rate  := Ctx^.Rate;
  info^.scale := Ctx^.Scale;

  // 総フレーム数（AviUtl2 仕様そのまま）
  if (info^.rate > 0) and (info^.scale > 0) then
    info^.n := Ceil(Ctx^.MaxSec * info^.rate / info^.scale)
  else
    info^.n := 0;

  info^.format      := @Ctx^.Info;
  info^.format_size := SizeOf(BITMAPINFOHEADER);

  Result := True;
end;

//------------------------------------------------------------------------------
// フレーム読み込み（共有メモリの内容を反映してから描画）
//------------------------------------------------------------------------------
function PluginInputReadVideo(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer;
var
  Ctx : PFileContext;
  Sec : Double;
begin
  Result := 0;
  if (ih = nil) or (buf = nil) then Exit;
  if (GSharedBase = nil) then Exit;

  Ctx := PFileContext(ih);

  // AviUtl2 定義どおりの秒算出
  if (Ctx^.Rate > 0) and (Ctx^.Scale > 0) then
    Sec := frame * Ctx^.Scale / Ctx^.Rate
  else
    Sec := 0.0;

  // 共有メモリへ書き込み（意味は従来と同一）
  GSharedBase.SetInt(  0, Ctx^.Rate);    // rate
  GSharedBase.SetInt(  1, frame);        // frame
  GSharedBase.SetFloat(2, Sec);          // 秒位置
  GSharedBase.SetInt(3, Ctx^.Width);     // 横幅
  GSharedBase.SetInt(4, Ctx^.Height);    // 縦幅

  Result := Ctx^.Info.biSizeImage;
end;


//------------------------------------------------------------------------------
// 設定ダイアログ（確認用）
//------------------------------------------------------------------------------
function PluginInputConfig(hwnd: HWND; hinst: HINST): BOOL;
begin
  MessageBox(hwnd, 'Syncroh2 Base Plugin', 'AviUtl2 Syncroh2 Plugin', MB_OK);
  Result := True;
end;


end.
