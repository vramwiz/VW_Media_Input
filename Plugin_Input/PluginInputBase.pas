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
  System.Diagnostics, System.Math, System.SyncObjs, FFmpegDecoderTypes, FFmpegDecoder,
  PluginAudioInputReader, PluginInputSettings;

const
  MAX_FORWARD_DECODE_GAP      = 120;               // 近い前方ジャンプを順方向decodeで追う最大frame数
  SHARED_FRAME_CACHE_CAPACITY = 16;                // ファイル間共有フレームキャッシュの最大保持数
  VIDEO_OUTPUT_BGRX32         = 0;                 // AviUtl2へ32bit BGRxで返す形式
  VIDEO_OUTPUT_BGR24          = 1;                 // AviUtl2へ24bit BGRで返す形式
  VIDEO_OUTPUT_YUY2           = 2;                 // AviUtl2へYUY2で返す形式
  VIDEO_OUTPUT_I420           = 3;                 // AviUtl2へI420で返す試験用形式
  VIDEO_OUTPUT_YC48           = 4;                 // AviUtl2へYC48で返す試験用形式
  VIDEO_OUTPUT_RGBA32         = 5;                 // AviUtl2へ透過保持用32bit RGBA/BGRAで返す形式
  VIDEO_OUTPUT_FORMAT         = VIDEO_OUTPUT_YUY2; // 現在採用するAviUtl2向け映像形式
  ENABLE_REUSABLE_DECODER     = False;             // 終了時にQSVリソースを残さないため再利用を抑止
  BI_YUY2                     = $32595559;         // 'YUY2'
  BI_I420                     = $30323449;         // 'I420'
  BI_YC48                     = $38344359;         // 'YC48'
{$IFDEF DEBUG}
  DECODE_TRACE_ENABLED        = True;  // Debug時だけデコードログ/計測を有効にする
  CLEAR_DECODE_TRACE_ON_OPEN  = True;  // Debug時だけ入力open時にデコードログを作り直す
  READ_VIDEO_SLOW_MS          = 16.0;  // 60fps相当を超えるread_videoを調査用に目印化する
{$ELSE}
  DECODE_TRACE_ENABLED        = False; // Releaseではログ文字列生成や計測を含めない
  CLEAR_DECODE_TRACE_ON_OPEN  = False; // Releaseではログクリアもしない
{$ENDIF}

type
  PFileContext = ^TFileContext;
  // AviUtl2の入力ハンドルとして保持するファイル単位の状態。
  TFileContext = record
    Decoder           : TFFmpegDecoder;          // 映像読み取り用のFFmpegデコーダ
    FileName          : string;                  // 開いている入力ファイル名
    HasVideo          : Boolean;                 // 映像ストリームをAviUtl2へ返せるか
    Width             : Integer;                 // 映像の幅
    Height            : Integer;                 // 映像の高さ
    DurationSec       : Double;                  // 入力ファイルの長さ
    Rate              : Integer;                 // AviUtl2へ返すフレームレート分子
    Scale             : Integer;                 // AviUtl2へ返すフレームレート分母
    FrameCount        : Integer;                 // AviUtl2へ返す総フレーム数
    VideoInfo         : TVideoInfo;              // open時に取得した動画情報
    VideoOutputFormat : Integer;                 // ファイルごとに選択したAviUtl2向け映像形式
    Info              : BITMAPINFOHEADER;        // AviUtl2へ返す映像フォーマット
    AudioInput        : TPluginAudioInputReader; // 音声読み取り用の入力リーダー
    LastDecodedFrame  : Integer;                 // キャッシュしている直近のフレーム番号
    CachedFrame       : TBytes;                  // 直近フレームのBGRx32キャッシュ
    LastError         : string;                  // 直近のデコード/音声openエラー
{$IFDEF DEBUG}
    LastReadVideoRequestTick  : Int64;   // 前回read_video要求時刻
    LastReadVideoRequestFrame : Integer; // 前回read_video要求フレーム
    ReadVideoCallCount        : Int64;   // read_video実行回数
    SlowReadVideoCount        : Int64;   // 調査しきい値を超えたread_video回数
    ReadVideoTotalMs          : Double;  // read_video合計時間
    ReadVideoMaxMs            : Double;  // read_video最大時間
{$ENDIF}
  end;

  TSharedFrameCacheEntry = record
    FileName  : string;  // キャッシュ元ファイル名
    Frame     : Integer; // キャッシュしたフレーム番号
    ImageSize : Integer; // キャッシュした映像バッファサイズ
    Data      : TBytes;  // AviUtl2へ返した映像データ
    LastUsed  : UInt64;  // LRU判定用の利用順カウンタ
  end;

var
  SharedFrameCache        : array[0..SHARED_FRAME_CACHE_CAPACITY - 1] of TSharedFrameCacheEntry;
  // 複数open間で共有するframe cache
  SharedFrameCacheClock   : UInt64;           // 共有キャッシュのLRU順序カウンタ
  SharedFrameCacheLock    : TCriticalSection; // 共有キャッシュ保護用ロック
  ReusableDecoder         : TFFmpegDecoder;   // close直後に次openへ引き渡すデコーダ
  ReusableDecoderFileName : string;           // 再利用デコーダが開いているファイル名
  ReusableDecoderInfo     : TVideoInfo;       // 再利用デコーダの動画情報
  ReusableDecoderLastFrame : Integer;          // 再利用デコーダの最後に読んだフレーム
{$IFDEF DEBUG}
  DecodeTraceLogCleared   : Boolean;          // Debugログをプロセス中に一度だけ初期化したか
{$ENDIF}

// デコードログの出力先ファイル名を返す。
function DecodeTraceLogFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VW_Media_Input_decode.log';
end;

// Debug時のデコードログをTEMPへ追記する。
procedure DecodeTrace(const Msg: string); forward;

{$IFDEF DEBUG}
function StopwatchTicksToMs(Ticks: Int64): Double;
begin
  if TStopwatch.Frequency <= 0 then
    Result := 0
  else
    Result := Ticks * 1000.0 / TStopwatch.Frequency;
end;
{$ENDIF}

// 入力openごとのデコードログを初期化する。
procedure ClearDecodeTraceLog(const Reason: string);
{$IFDEF DEBUG}
var
  F: TextFile;
  LogFileName: string;
  Line: string;
{$ENDIF}
begin
{$IFDEF DEBUG}
  if (not DECODE_TRACE_ENABLED) or (not CLEAR_DECODE_TRACE_ON_OPEN) then
    Exit;

  if DecodeTraceLogCleared then
  begin
    DecodeTrace('log_keep ' + Reason);
    Exit;
  end;
  DecodeTraceLogCleared := True;

  LogFileName := DecodeTraceLogFileName;
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [PluginInputBase] log_clear ' + Reason;
  OutputDebugString(PChar(Line));
  AssignFile(F, LogFileName);
  try
    Rewrite(F);
    Writeln(F, Line);
  finally
    CloseFile(F);
  end;
{$ENDIF}
end;

// Debug時のデコードログをTEMPへ追記する。
procedure DecodeTrace(const Msg: string);
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
  if not DECODE_TRACE_ENABLED then
    Exit;

  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [PluginInputBase] ' + Msg;
  OutputDebugString(PChar(Line));
  LogFileName := DecodeTraceLogFileName;
  AssignFile(F, LogFileName);
  try
    if FileExists(LogFileName) then
      Append(F)
    else
      Rewrite(F);
    Writeln(F, Line);
  finally
    CloseFile(F);
  end;
end;

// 複数open間で共有するフレームキャッシュから指定フレームを取り出す。
function TryReadSharedFrameCache(const FileName: string; Frame, ImageSize: Integer;
  Buffer: Pointer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (SharedFrameCacheLock = nil) or (Buffer = nil) or (ImageSize <= 0) then
    Exit;

  SharedFrameCacheLock.Enter;
  try
    for I := Low(SharedFrameCache) to High(SharedFrameCache) do
      if SameText(SharedFrameCache[I].FileName, FileName) and
        (SharedFrameCache[I].Frame = Frame) and
        (SharedFrameCache[I].ImageSize = ImageSize) and
        (Length(SharedFrameCache[I].Data) = ImageSize) then
      begin
        Move(SharedFrameCache[I].Data[0], Buffer^, ImageSize);
        Inc(SharedFrameCacheClock);
        SharedFrameCache[I].LastUsed := SharedFrameCacheClock;
        Result := True;
        Exit;
      end;
  finally
    SharedFrameCacheLock.Leave;
  end;
end;

// AviUtl2へ返したフレームを共有キャッシュへ保存する。
procedure SaveSharedFrameCache(const FileName: string; Frame, ImageSize: Integer;
  Buffer: Pointer);
var
  I: Integer;
  Slot: Integer;
  OldestUsed: UInt64;
begin
  if (SharedFrameCacheLock = nil) or (Buffer = nil) or (ImageSize <= 0) then
    Exit;

  SharedFrameCacheLock.Enter;
  try
    Slot := Low(SharedFrameCache);
    OldestUsed := High(UInt64);
    for I := Low(SharedFrameCache) to High(SharedFrameCache) do
    begin
      if SameText(SharedFrameCache[I].FileName, FileName) and
        (SharedFrameCache[I].Frame = Frame) and
        (SharedFrameCache[I].ImageSize = ImageSize) then
      begin
        Slot := I;
        Break;
      end;

      if (Length(SharedFrameCache[I].Data) = 0) or (SharedFrameCache[I].LastUsed < OldestUsed) then
      begin
        Slot := I;
        OldestUsed := SharedFrameCache[I].LastUsed;
      end;
    end;

    if Length(SharedFrameCache[Slot].Data) <> ImageSize then
      SetLength(SharedFrameCache[Slot].Data, ImageSize);
    Move(Buffer^, SharedFrameCache[Slot].Data[0], ImageSize);
    SharedFrameCache[Slot].FileName := FileName;
    SharedFrameCache[Slot].Frame := Frame;
    SharedFrameCache[Slot].ImageSize := ImageSize;
    Inc(SharedFrameCacheClock);
    SharedFrameCache[Slot].LastUsed := SharedFrameCacheClock;
  finally
    SharedFrameCacheLock.Leave;
  end;
end;

// 同じファイルを直後に開く場合に備えて保持したdecoderを取り出す。
function TryTakeReusableDecoder(const FileName: string; out Decoder: TFFmpegDecoder; out VideoInfo: TVideoInfo;
  out LastFrame: Integer): Boolean;
begin
  Decoder := nil;
  FillChar(VideoInfo, SizeOf(VideoInfo), 0);
  LastFrame := -1;
  Result := False;
  if SharedFrameCacheLock = nil then
    Exit;

  SharedFrameCacheLock.Enter;
  try
    if (ReusableDecoder <> nil) and SameText(ReusableDecoderFileName, FileName) then
    begin
      Decoder := ReusableDecoder;
      VideoInfo := ReusableDecoderInfo;
      LastFrame := ReusableDecoderLastFrame;
      ReusableDecoder := nil;
      ReusableDecoderFileName := '';
      ReusableDecoderLastFrame := -1;
      Result := True;
    end;
  finally
    SharedFrameCacheLock.Leave;
  end;
end;

// close直後の再openへ渡せるようdecoderを一時保持する。
procedure SaveReusableDecoder(var Decoder: TFFmpegDecoder; const FileName: string; const VideoInfo: TVideoInfo;
  LastFrame: Integer);
var
  OldDecoder: TFFmpegDecoder;
begin
  if (SharedFrameCacheLock = nil) or (Decoder = nil) or (FileName = '') then
    Exit;

  OldDecoder := nil;
  SharedFrameCacheLock.Enter;
  try
    if ReusableDecoder <> Decoder then
      OldDecoder := ReusableDecoder;
    ReusableDecoder := Decoder;
    ReusableDecoderFileName := FileName;
    ReusableDecoderInfo := VideoInfo;
    ReusableDecoderLastFrame := LastFrame;
    Decoder := nil;
  finally
    SharedFrameCacheLock.Leave;
  end;
  OldDecoder.Free;
end;

// ファイル単位の状態と保持リソースを解放する。
procedure FreeFileContext(Ctx: PFileContext);
begin
  if Ctx = nil then
    Exit;

  if Ctx^.HasVideo and ENABLE_REUSABLE_DECODER then
    SaveReusableDecoder(Ctx^.Decoder, Ctx^.FileName, Ctx^.VideoInfo, Ctx^.LastDecodedFrame);
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

// 現在の映像出力形式に応じた1ピクセルあたりのバイト数を返す。
function VideoBytesPerPixel(OutputFormat: Integer): Integer;
begin
  case OutputFormat of
    VIDEO_OUTPUT_BGR24:
      Result := 3;
    VIDEO_OUTPUT_YUY2:
      Result := 2;
    VIDEO_OUTPUT_I420:
      Result := 1;
    VIDEO_OUTPUT_YC48:
      Result := 6;
    VIDEO_OUTPUT_RGBA32:
      Result := 4;
  else
    Result := 4;
  end;
end;

// AviUtl2へ返す1ラインあたりのバイト数を返す。
function VideoStride(const Ctx: PFileContext): Integer;
begin
  Result := Ctx^.Width * VideoBytesPerPixel(Ctx^.VideoOutputFormat);
  if Ctx^.VideoOutputFormat = VIDEO_OUTPUT_BGR24 then
    Result := ((Result + 3) div 4) * 4;
end;

// I420のY/UV planeを合わせた1フレーム分のバイト数を返す。
function I420ImageSize(Width, Height: Integer): Integer;
var
  ChromaWidth: Integer;
  ChromaHeight: Integer;
begin
  ChromaWidth := (Width + 1) div 2;
  ChromaHeight := (Height + 1) div 2;
  Result := Width * Height + ChromaWidth * ChromaHeight * 2;
end;

// AviUtl2へ返す1フレームあたりのバイト数を返す。
function VideoImageSize(const Ctx: PFileContext): Integer;
begin
  case Ctx^.VideoOutputFormat of
    VIDEO_OUTPUT_I420:
      Result := I420ImageSize(Ctx^.Width, Ctx^.Height);
  else
    Result := VideoStride(Ctx) * Ctx^.Height;
  end;
end;

// AviUtl2から渡されたファイルを開き、入力ハンドルを返す。
function PluginInputOpen(fileName: LPCWSTR): INPUT_HANDLE;
var
  Ctx: PFileContext;
  VideoInfo: TVideoInfo;
  ErrorMessage: string;
  AudioErrorMessage: string;
{$IFDEF DEBUG}
  ReusedDecoder: Boolean;
{$ENDIF}
begin
  Result := nil;
  AudioErrorMessage := '';
{$IFDEF DEBUG}
  ReusedDecoder := False;
{$ENDIF}
  New(Ctx);
  FillChar(Ctx^, SizeOf(Ctx^), 0);

  try
    Ctx^.FileName := string(fileName);
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      ClearDecodeTraceLog(Format('file="%s"', [Ctx^.FileName]));
    Ctx^.LastReadVideoRequestFrame := -1;
{$ENDIF}
    Ctx^.LastDecodedFrame := -1;

    if ENABLE_REUSABLE_DECODER and
      TryTakeReusableDecoder(Ctx^.FileName, Ctx^.Decoder, VideoInfo, Ctx^.LastDecodedFrame) then
    begin
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        ReusedDecoder := True;
{$ENDIF}
    end
    else
    begin
      Ctx^.Decoder := TFFmpegDecoder.Create;
      if not Ctx^.Decoder.Open(Ctx^.FileName, VideoInfo, ErrorMessage) then
      begin
        Ctx^.LastError := ErrorMessage;
{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          DecodeTrace(Format('open failed file="%s" err=%s', [Ctx^.FileName, ErrorMessage]));
{$ENDIF}
        FreeFileContext(Ctx);
        Exit;
      end;
    end;

    if Ctx^.Decoder <> nil then
    begin
      Ctx^.HasVideo := (VideoInfo.Width > 0) and (VideoInfo.Height > 0);
      Ctx^.VideoInfo := VideoInfo;
      if VideoInfo.HasAlpha then
        Ctx^.VideoOutputFormat := VIDEO_OUTPUT_RGBA32
      else
        Ctx^.VideoOutputFormat := VIDEO_OUTPUT_FORMAT;
      Ctx^.Width := VideoInfo.Width;
      Ctx^.Height := VideoInfo.Height;
      Ctx^.DurationSec := VideoInfo.DurationSec;
      FpsToRateScale(VideoInfo.Fps, Ctx^.Rate, Ctx^.Scale);

      if Ctx^.HasVideo and (Ctx^.DurationSec > 0) then
        Ctx^.FrameCount := Max(1, Ceil(Ctx^.DurationSec * Ctx^.Rate / Ctx^.Scale))
      else if Ctx^.HasVideo then
        Ctx^.FrameCount := 1;

      if Ctx^.HasVideo then
      begin
        Ctx^.Info.biSize := SizeOf(BITMAPINFOHEADER);
        Ctx^.Info.biWidth := Ctx^.Width;
        Ctx^.Info.biHeight := Ctx^.Height;
        Ctx^.Info.biPlanes := 1;
        case Ctx^.VideoOutputFormat of
          VIDEO_OUTPUT_BGR24:
          begin
            Ctx^.Info.biBitCount := 24;
            Ctx^.Info.biCompression := BI_RGB;
          end;
          VIDEO_OUTPUT_YUY2:
          begin
            Ctx^.Info.biBitCount := 16;
            Ctx^.Info.biCompression := BI_YUY2;
          end;
          VIDEO_OUTPUT_I420:
          begin
            Ctx^.Info.biBitCount := 12;
            Ctx^.Info.biCompression := BI_I420;
          end;
          VIDEO_OUTPUT_YC48:
          begin
            Ctx^.Info.biBitCount := 48;
            Ctx^.Info.biCompression := BI_YC48;
          end;
          VIDEO_OUTPUT_RGBA32:
          begin
            Ctx^.Info.biBitCount := 32;
            Ctx^.Info.biCompression := BI_RGB;
          end;
        else
        begin
          Ctx^.Info.biBitCount := 32;
          Ctx^.Info.biCompression := BI_RGB;
        end;
        end;
        Ctx^.Info.biSizeImage := VideoImageSize(Ctx);
      end;

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

{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        DecodeTrace(Format('open ok file="%s" reused=%s last=%d width=%d ' +
          'height=%d duration=%.3f fps=%.6f frames=%d pix_fmt="%s" ' +
          'alpha=%s output_format=%d audio=%s audio_err=%s',
          [Ctx^.FileName, BoolToStr(ReusedDecoder, True), Ctx^.LastDecodedFrame,
           Ctx^.Width, Ctx^.Height, Ctx^.DurationSec, VideoInfo.Fps,
           Ctx^.FrameCount, VideoInfo.PixelFormatName, BoolToStr(VideoInfo.HasAlpha, True),
           Ctx^.VideoOutputFormat, BoolToStr(VideoInfo.Audio.Present, True), AudioErrorMessage]));
{$ENDIF}

      Result := Ctx;
      Ctx := nil;
    end
  except
    Result := nil;
  end;

  FreeFileContext(Ctx);
end;

// 入力ハンドルに紐づくデコーダとキャッシュを閉じる。
function PluginInputClose(ih: INPUT_HANDLE): BOOL;
{$IFDEF DEBUG}
var
  Ctx: PFileContext;
  Stats: TDecodeLoadStats;
{$ENDIF}
begin
  Result := False;
  if ih = nil then
    Exit;

{$IFDEF DEBUG}
  Ctx := PFileContext(ih);
  if DECODE_TRACE_ENABLED and (Ctx^.Decoder <> nil) then
  begin
    Stats := Ctx^.Decoder.DecodeStats;
    DecodeTrace(Format('close_summary file="%s" read_video_calls=%d ' +
      'read_video_slow=%d read_video_avg_ms=%.3f read_video_max_ms=%.3f ' +
      'decoder_video_frames=%d decoder_avg_ms=%.3f decoder_max_ms=%.3f ' +
      'decode_avg_ms=%.3f decode_max_ms=%.3f transfer_avg_ms=%.3f ' +
      'transfer_max_ms=%.3f convert_avg_ms=%.3f convert_max_ms=%.3f',
      [Ctx^.FileName, Ctx^.ReadVideoCallCount, Ctx^.SlowReadVideoCount,
       IfThen(Ctx^.ReadVideoCallCount > 0, Ctx^.ReadVideoTotalMs / Ctx^.ReadVideoCallCount, 0.0),
       Ctx^.ReadVideoMaxMs, Stats.VideoFrames, Stats.VideoAverageMs, Stats.VideoMaxMs,
       Stats.VideoDecodeAverageMs, Stats.VideoDecodeMaxMs,
       Stats.VideoTransferAverageMs, Stats.VideoTransferMaxMs,
       Stats.VideoConvertAverageMs, Stats.VideoConvertMaxMs]));
  end;
{$ENDIF}

  FreeFileContext(PFileContext(ih));
  Result := True;
end;

// AviUtl2へ動画/音声の入力情報を返す。
function PluginInputGetInfo(ih: INPUT_HANDLE; info: PInputInfo): BOOL;
var
  Ctx: PFileContext;
begin
  Result := False;
  if (ih = nil) or (info = nil) then
    Exit;

  Ctx := PFileContext(ih);
  FillChar(info^, SizeOf(TInputInfo), 0);
  if Ctx^.HasVideo then
    info^.flag := INPUT_INFO_FLAG_VIDEO;
  if (Ctx^.AudioInput <> nil) and Ctx^.AudioInput.HasAudio then
    info^.flag := info^.flag or INPUT_INFO_FLAG_AUDIO;
  info^.rate := Ctx^.Rate;
  info^.scale := Ctx^.Scale;
  info^.n := Ctx^.FrameCount;
  if Ctx^.HasVideo then
  begin
    info^.format := @Ctx^.Info;
    info^.format_size := SizeOf(BITMAPINFOHEADER);
  end;
  if (info^.flag and INPUT_INFO_FLAG_AUDIO) <> 0 then
  begin
    info^.audio_n := Ctx^.AudioInput.SampleCount;
    info^.audio_format := Ctx^.AudioInput.FormatPtr;
    info^.audio_format_size := SizeOf(WAVEFORMATEX);
  end;
  Result := info^.flag <> 0;
end;

// 指定フレームの映像をAviUtl2のバッファへ読み込む。
function PluginInputReadVideo(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer;
var
  Ctx: PFileContext;
  PositionMs: Integer;
  PositionMsOut: Integer;
  ErrorMessage: string;
  ImageSize: Integer;
  Decoded: Boolean;
  FrameGap: Integer;
  ForwardFrame: Integer;
{$IFDEF DEBUG}
  StartTick: TStopwatch;
  RequestTick: Int64;
  RequestIntervalMs: Double;
  ReadElapsedMs: Double;
  ExpectedFrameMs: Double;
  IsSlowRead: Boolean;
{$ENDIF}
  DecodeRoute: string;
begin
  Result := 0;
  if (ih = nil) or (buf = nil) then
    Exit;

  Ctx := PFileContext(ih);
  if (Ctx^.Decoder = nil) or (not Ctx^.HasVideo) then
    Exit;

  if frame < 0 then
    frame := 0;
  ImageSize := VideoImageSize(Ctx);

{$IFDEF DEBUG}
  if DECODE_TRACE_ENABLED then
  begin
    RequestTick := TStopwatch.GetTimeStamp;
    if Ctx^.LastReadVideoRequestTick > 0 then
      RequestIntervalMs := StopwatchTicksToMs(RequestTick - Ctx^.LastReadVideoRequestTick)
    else
      RequestIntervalMs := -1;
    DecodeTrace(Format('read_video_request file="%s" frame=%d ' +
      'prev_request_frame=%d request_gap=%d interval_ms=%.3f last_decoded=%d',
      [Ctx^.FileName, frame, Ctx^.LastReadVideoRequestFrame,
       frame - Ctx^.LastReadVideoRequestFrame, RequestIntervalMs, Ctx^.LastDecodedFrame]));
    Ctx^.LastReadVideoRequestTick := RequestTick;
    Ctx^.LastReadVideoRequestFrame := frame;
  end;
{$ENDIF}

  if (frame = Ctx^.LastDecodedFrame) and (Length(Ctx^.CachedFrame) = ImageSize) then
  begin
    Move(Ctx^.CachedFrame[0], buf^, ImageSize);
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      DecodeTrace(Format('read_video file="%s" frame=%d last=%d gap=0 route=cache bytes=%d',
        [Ctx^.FileName, frame, Ctx^.LastDecodedFrame, ImageSize]));
{$ENDIF}
    Result := ImageSize;
    Exit;
  end;

  if TryReadSharedFrameCache(Ctx^.FileName, frame, ImageSize, buf) then
  begin
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      DecodeTrace(Format('read_video file="%s" frame=%d last=%d gap=%d route=shared_cache bytes=%d',
        [Ctx^.FileName, frame, Ctx^.LastDecodedFrame, frame - Ctx^.LastDecodedFrame, ImageSize]));
{$ENDIF}
    Result := ImageSize;
    Exit;
  end;

{$IFDEF DEBUG}
  if DECODE_TRACE_ENABLED then
    StartTick := TStopwatch.StartNew;
{$ENDIF}
  DecodeRoute := '';
  FrameGap := frame - Ctx^.LastDecodedFrame;
  if (Ctx^.LastDecodedFrame >= 0) and (FrameGap > 0) and (FrameGap <= MAX_FORWARD_DECODE_GAP) then
  begin
    DecodeRoute := 'forward';
    Decoded := True;
    for ForwardFrame := Ctx^.LastDecodedFrame + 1 to frame do
    begin
      case Ctx^.VideoOutputFormat of
        VIDEO_OUTPUT_BGR24:
          Decoded := Ctx^.Decoder.DecodeNextFrameToBgr24Optional(buf, VideoStride(Ctx),
            ForwardFrame = frame, PositionMsOut, ErrorMessage);
        VIDEO_OUTPUT_YUY2:
          Decoded := Ctx^.Decoder.DecodeNextFrameToYuy2Optional(buf, VideoStride(Ctx),
            ForwardFrame = frame, PositionMsOut, ErrorMessage);
        VIDEO_OUTPUT_I420:
          Decoded := Ctx^.Decoder.DecodeNextFrameToI420Optional(buf, VideoStride(Ctx),
            ForwardFrame = frame, PositionMsOut, ErrorMessage);
        VIDEO_OUTPUT_YC48:
          Decoded := Ctx^.Decoder.DecodeNextFrameToYc48Optional(buf, VideoStride(Ctx),
            ForwardFrame = frame, PositionMsOut, ErrorMessage);
        VIDEO_OUTPUT_RGBA32:
          Decoded := Ctx^.Decoder.DecodeNextFrameToBgrx32Optional(buf, VideoStride(Ctx),
            ForwardFrame = frame, PositionMsOut, ErrorMessage);
      else
        Decoded := Ctx^.Decoder.DecodeNextFrameToBgrx32Optional(buf, VideoStride(Ctx),
          ForwardFrame = frame, PositionMsOut, ErrorMessage);
      end;
      if not Decoded then
        Break;
    end;
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      PositionMs := PositionMsOut;
{$ENDIF}
  end
  else
  begin
    DecodeRoute := 'seek';
    PositionMs := Round(frame * Ctx^.Scale * 1000.0 / Ctx^.Rate);
    case Ctx^.VideoOutputFormat of
      VIDEO_OUTPUT_BGR24:
        Decoded := Ctx^.Decoder.DecodeFrameToBgr24(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
      VIDEO_OUTPUT_YUY2:
        Decoded := Ctx^.Decoder.DecodeFrameToYuy2(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
      VIDEO_OUTPUT_I420:
        Decoded := Ctx^.Decoder.DecodeFrameToI420(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
      VIDEO_OUTPUT_YC48:
        Decoded := Ctx^.Decoder.DecodeFrameToYc48(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
      VIDEO_OUTPUT_RGBA32:
        Decoded := Ctx^.Decoder.DecodeFrameToBgrx32(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
    else
      Decoded := Ctx^.Decoder.DecodeFrameToBgrx32(PositionMs, buf, VideoStride(Ctx), ErrorMessage);
    end;
  end;
{$IFDEF DEBUG}
  if DECODE_TRACE_ENABLED then
    StartTick.Stop;
{$ENDIF}

{$IFDEF DEBUG}
  if DECODE_TRACE_ENABLED then
  begin
    ReadElapsedMs := StartTick.Elapsed.TotalMilliseconds;
    Inc(Ctx^.ReadVideoCallCount);
    Ctx^.ReadVideoTotalMs := Ctx^.ReadVideoTotalMs + ReadElapsedMs;
    if ReadElapsedMs > Ctx^.ReadVideoMaxMs then
      Ctx^.ReadVideoMaxMs := ReadElapsedMs;
    if Ctx^.Rate > 0 then
      ExpectedFrameMs := Ctx^.Scale * 1000.0 / Ctx^.Rate
    else
      ExpectedFrameMs := 0;
    IsSlowRead := (ReadElapsedMs >= READ_VIDEO_SLOW_MS) or
      ((ExpectedFrameMs > 0) and (ReadElapsedMs >= ExpectedFrameMs));
    if IsSlowRead then
      Inc(Ctx^.SlowReadVideoCount);
    DecodeTrace(Format('read_video file="%s" frame=%d last=%d gap=%d ' +
      'route=%s ok=%s elapsed_ms=%.3f image_size=%d pos_ms=%d err=%s',
      [Ctx^.FileName, frame, Ctx^.LastDecodedFrame, FrameGap, DecodeRoute,
       BoolToStr(Decoded, True),
       ReadElapsedMs, ImageSize, PositionMs, ErrorMessage]));
    if IsSlowRead then
      DecodeTrace(Format('read_video_slow file="%s" frame=%d last=%d gap=%d ' +
        'route=%s elapsed_ms=%.3f frame_budget_ms=%.3f threshold_ms=%.3f ' +
        'pos_ms=%d ok=%s err=%s',
        [Ctx^.FileName, frame, Ctx^.LastDecodedFrame, FrameGap, DecodeRoute,
         ReadElapsedMs, ExpectedFrameMs, READ_VIDEO_SLOW_MS, PositionMs,
         BoolToStr(Decoded, True), ErrorMessage]));
  end;
{$ENDIF}

  if not Decoded then
  begin
    Ctx^.LastError := ErrorMessage;
    Exit;
  end;

  SaveSharedFrameCache(Ctx^.FileName, frame, ImageSize, buf);

  if Length(Ctx^.CachedFrame) <> ImageSize then
    SetLength(Ctx^.CachedFrame, ImageSize);
  Move(buf^, Ctx^.CachedFrame[0], ImageSize);
  Ctx^.LastDecodedFrame := frame;
  Result := ImageSize;
end;

// 指定範囲の音声サンプルをAviUtl2のバッファへ読み込む。
function PluginInputReadAudio(ih: INPUT_HANDLE; start, sampleLength: Integer; buf: Pointer): Integer;
var
  Ctx: PFileContext;
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
  Result := ShowPluginSettingsDialog(hwnd, hinst);
end;

initialization
  SharedFrameCacheLock := TCriticalSection.Create;

finalization
  ReusableDecoder.Free;
  SharedFrameCacheLock.Free;

end.
