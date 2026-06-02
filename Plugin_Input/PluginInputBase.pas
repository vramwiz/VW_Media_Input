unit PluginInputBase;

// AviUtl2入力プラグインとして公開する処理本体ユニット。
// ファイルopen/close、情報取得、映像フレーム読み込み、音声読み込みを各デコーダへ橋渡しする。

interface

uses
  Winapi.Windows, System.SysUtils, AviUtl2InputTypes;

// AviUtl2から渡されたファイルを開き、入力ハンドルを返す。
function PluginInputOpen(fileName: LPCWSTR): INPUT_HANDLE;
// 入力ハンドルに紐づくデコーダとキャッシュを閉じる。
function PluginInputClose(ih: INPUT_HANDLE): BOOL;
// AviUtl2へ動画/音声の入力情報を返す。
function PluginInputGetInfo(ih: INPUT_HANDLE; info: PInputInfo): BOOL;
// 指定フレームの映像をAviUtl2のバッファへ読み込む。
function PluginInputReadVideo(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer;
// 指定範囲の音声サンプルをAviUtl2のバッファへ読み込む。
function PluginInputReadAudio(ih: INPUT_HANDLE; start, sampleLength: Integer; buf: Pointer): Integer;
// 入力プラグインの設定ダイアログを表示する。
function PluginInputConfig(hwnd: HWND; hinst: HINST): BOOL;

implementation

uses
  System.Math, FFmpegDecoderTypes, FFmpegDecoder, PluginAudioInputReader;

type
  PFileContext = ^TFileContext;
  // AviUtl2の入力ハンドルとして保持するファイル単位の状態。
  TFileContext = record
    Decoder: TFFmpegDecoder; // 映像読み取り用のFFmpegデコーダ
    FileName: string; // 開いている入力ファイル名
    Width: Integer; // 映像の幅
    Height: Integer; // 映像の高さ
    DurationSec: Double; // 入力ファイルの長さ
    Rate: Integer; // AviUtl2へ返すフレームレート分子
    Scale: Integer; // AviUtl2へ返すフレームレート分母
    FrameCount: Integer; // AviUtl2へ返す総フレーム数
    Info: BITMAPINFOHEADER; // AviUtl2へ返す映像フォーマット
    AudioInput: TPluginAudioInputReader; // 音声読み取り用の入力リーダー
    LastDecodedFrame: Integer; // キャッシュしている直近のフレーム番号
    CachedFrame: TBytes; // 直近フレームのBGRx32キャッシュ
    LastError: string; // 直近のデコード/音声openエラー
  end;

// ファイル単位の状態と保持リソースを解放する。
procedure FreeFileContext(Ctx: PFileContext);
begin
  if Ctx = nil then
    Exit;

  Ctx^.Decoder.Free;
  Ctx^.AudioInput.Free;
  Ctx^.CachedFrame := nil;
  Dispose(Ctx);
end;

// 2つの整数の最大公約数を求める。
function GreatestCommonDivisor(A, B: Integer): Integer;
var
  T: Integer; // ユークリッド互除法の一時値
begin
  A := Abs(A);
  B := Abs(B);
  while B <> 0 do
  begin
    T := A mod B;
    A := B;
    B := T;
  end;
  if A = 0 then
    Result := 1
  else
    Result := A;
end;

// fps実数値をAviUtl2へ返すrate/scale形式へ変換する。
procedure FpsToRateScale(Fps: Double; out Rate, Scale: Integer);
var
  Divisor: Integer; // rate/scaleを約分する最大公約数
begin
  if Fps <= 0 then
    Fps := 30.0;

  Scale := 1000;
  Rate := Round(Fps * Scale);
  if Rate <= 0 then
    Rate := 30000;

  Divisor := GreatestCommonDivisor(Rate, Scale);
  Rate := Rate div Divisor;
  Scale := Scale div Divisor;
end;

// AviUtl2から渡されたファイルを開き、入力ハンドルを返す。
function PluginInputOpen(fileName: LPCWSTR): INPUT_HANDLE;
var
  Ctx: PFileContext; // 新しく作成する入力ハンドル用状態
  VideoInfo: TVideoInfo; // FFmpegから取得した動画情報
  ErrorMessage: string; // 映像open時のエラーメッセージ
  AudioErrorMessage: string; // 音声open時のエラーメッセージ
begin
  Result := nil;
  AudioErrorMessage := '';
  New(Ctx);
  FillChar(Ctx^, SizeOf(Ctx^), 0);

  try
    Ctx^.FileName := string(fileName);
    Ctx^.Decoder := TFFmpegDecoder.Create;
    Ctx^.LastDecodedFrame := -1;

    if Ctx^.Decoder.Open(Ctx^.FileName, VideoInfo, ErrorMessage) then
    begin
      Ctx^.Width := VideoInfo.Width;
      Ctx^.Height := VideoInfo.Height;
      Ctx^.DurationSec := VideoInfo.DurationSec;
      FpsToRateScale(VideoInfo.Fps, Ctx^.Rate, Ctx^.Scale);

      if Ctx^.DurationSec > 0 then
        Ctx^.FrameCount := Max(1, Ceil(Ctx^.DurationSec * Ctx^.Rate / Ctx^.Scale))
      else
        Ctx^.FrameCount := 1;

      Ctx^.Info.biSize := SizeOf(BITMAPINFOHEADER);
      Ctx^.Info.biWidth := Ctx^.Width;
      Ctx^.Info.biHeight := Ctx^.Height;
      Ctx^.Info.biPlanes := 1;
      Ctx^.Info.biBitCount := 32;
      Ctx^.Info.biCompression := BI_RGB;
      Ctx^.Info.biSizeImage := Ctx^.Width * Ctx^.Height * 4;

      if VideoInfo.Audio.Present then
      begin
        Ctx^.AudioInput := TPluginAudioInputReader.Create;
        if not Ctx^.AudioInput.Open(Ctx^.FileName, VideoInfo, AudioErrorMessage) then
        begin
          Ctx^.AudioInput.Free;
          Ctx^.AudioInput := nil;
          Ctx^.LastError := AudioErrorMessage;
        end;
      end
      else
        Ctx^.LastError := AudioErrorMessage;

      Result := Ctx;
      Ctx := nil;
    end
    else
      Ctx^.LastError := ErrorMessage;
  except
    Result := nil;
  end;

  FreeFileContext(Ctx);
end;

// 入力ハンドルに紐づくデコーダとキャッシュを閉じる。
function PluginInputClose(ih: INPUT_HANDLE): BOOL;
begin
  Result := False;
  if ih = nil then
    Exit;

  FreeFileContext(PFileContext(ih));
  Result := True;
end;

// AviUtl2へ動画/音声の入力情報を返す。
function PluginInputGetInfo(ih: INPUT_HANDLE; info: PInputInfo): BOOL;
var
  Ctx: PFileContext; // AviUtl2から渡された入力ハンドルの状態
begin
  Result := False;
  if (ih = nil) or (info = nil) then
    Exit;

  Ctx := PFileContext(ih);
  FillChar(info^, SizeOf(TInputInfo), 0);
  info^.flag := INPUT_INFO_FLAG_VIDEO;
  if (Ctx^.AudioInput <> nil) and Ctx^.AudioInput.HasAudio then
    info^.flag := info^.flag or INPUT_INFO_FLAG_AUDIO;
  info^.rate := Ctx^.Rate;
  info^.scale := Ctx^.Scale;
  info^.n := Ctx^.FrameCount;
  info^.format := @Ctx^.Info;
  info^.format_size := SizeOf(BITMAPINFOHEADER);
  if (info^.flag and INPUT_INFO_FLAG_AUDIO) <> 0 then
  begin
    info^.audio_n := Ctx^.AudioInput.SampleCount;
    info^.audio_format := Ctx^.AudioInput.FormatPtr;
    info^.audio_format_size := SizeOf(WAVEFORMATEX);
  end;
  Result := True;
end;

// 指定フレームの映像をAviUtl2のバッファへ読み込む。
function PluginInputReadVideo(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer;
var
  Ctx: PFileContext; // AviUtl2から渡された入力ハンドルの状態
  PositionMs: Integer; // ランダムアクセス時に要求する再生位置
  PositionMsOut: Integer; // 順方向デコード時にデコーダから返る再生位置
  ErrorMessage: string; // 映像デコード時のエラーメッセージ
  ImageSize: Integer; // 1フレーム分のバイト数
  Decoded: Boolean; // 映像デコードが成功したか
begin
  Result := 0;
  if (ih = nil) or (buf = nil) then
    Exit;

  Ctx := PFileContext(ih);
  if Ctx^.Decoder = nil then
    Exit;

  if frame < 0 then
    frame := 0;
  ImageSize := Ctx^.Info.biSizeImage;

  if (frame = Ctx^.LastDecodedFrame) and (Length(Ctx^.CachedFrame) = ImageSize) then
  begin
    Move(Ctx^.CachedFrame[0], buf^, ImageSize);
    Result := ImageSize;
    Exit;
  end;

  if (Ctx^.LastDecodedFrame >= 0) and (frame = Ctx^.LastDecodedFrame + 1) then
    Decoded := Ctx^.Decoder.DecodeNextFrameToBgrx32(buf, Ctx^.Width * 4, PositionMsOut, ErrorMessage)
  else
  begin
    PositionMs := Round(frame * Ctx^.Scale * 1000.0 / Ctx^.Rate);
    Decoded := Ctx^.Decoder.DecodeFrameToBgrx32(PositionMs, buf, Ctx^.Width * 4, ErrorMessage);
  end;

  if not Decoded then
  begin
    Ctx^.LastError := ErrorMessage;
    Exit;
  end;

  if Length(Ctx^.CachedFrame) <> ImageSize then
    SetLength(Ctx^.CachedFrame, ImageSize);
  Move(buf^, Ctx^.CachedFrame[0], ImageSize);
  Ctx^.LastDecodedFrame := frame;
  Result := ImageSize;
end;

// 指定範囲の音声サンプルをAviUtl2のバッファへ読み込む。
function PluginInputReadAudio(ih: INPUT_HANDLE; start, sampleLength: Integer; buf: Pointer): Integer;
var
  Ctx: PFileContext; // AviUtl2から渡された入力ハンドルの状態
begin
  Result := 0;
  if (ih = nil) or (buf = nil) or (sampleLength <= 0) then
    Exit;

  Ctx := PFileContext(ih);
  if Ctx^.AudioInput = nil then
    Exit;

  Result := Ctx^.AudioInput.ReadAudio(start, sampleLength, buf);
end;

// 入力プラグインの設定ダイアログを表示する。
function PluginInputConfig(hwnd: HWND; hinst: HINST): BOOL;
begin
  MessageBox(hwnd, 'VW_Media_Input FFmpeg video input', 'VW_Media_Input', MB_OK);
  Result := True;
end;

end.
