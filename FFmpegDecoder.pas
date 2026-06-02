unit FFmpegDecoder;

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.SysUtils, System.Generics.Collections,
  System.Diagnostics, System.Math, Vcl.Graphics, FFmpegDecoderTypes;

type
  EFFmpegDecoder = class(Exception);

  TFFmpegDecoder = class
  private
    FFileName: string; // 現在開いている動画ファイル名
    FFormatContext: Pointer; // avformatで開いた入力コンテキスト
    FCodecContext: Pointer; // avcodecで開いたデコードコンテキスト
    FStream: Pointer; // 対象の映像ストリーム
    FStreamIndex: Integer; // 対象の映像ストリーム番号
    FAudioCodecContext: Pointer; // 音声用デコードコンテキスト
    FAudioStream: Pointer; // 対象の音声ストリーム
    FAudioStreamIndex: Integer; // 対象の音声ストリーム番号
    FAudioFrame: Pointer; // 音声デコードに再利用するAVFrame
    FSwrContext: Pointer; // PCM変換用swresampleコンテキスト
    FWaveOut: HWAVEOUT; // デバッグ用音声出力
    FAudioPlaybackActive: Boolean; // 音声出力中かどうか
    FAudioBuffers: TList<PAudioWaveBuffer>; // waveOut完了待ちのPCMバッファ
    FAudioStats: TAudioPlaybackStats; // 音声デコード確認用の数値
    FDecodeStats: TDecodeLoadStats; // デコード負荷確認用の数値
    FPacket: Pointer; // 読み込みに再利用するAVPacket
    FFrame: Pointer; // デコードに再利用するAVFrame
    FInfo: TVideoInfo; // 現在開いている動画の基本情報
    FDirectSwsContext: Pointer; // AviUtl2バッファ直接出力用の色変換コンテキスト
    FDirectSwsSrcWidth: Integer; // 直接出力用swsの入力幅
    FDirectSwsSrcHeight: Integer; // 直接出力用swsの入力高さ
    FDirectSwsSrcFormat: Integer; // 直接出力用swsの入力ピクセル形式
    FDirectSwsDstFormat: Integer; // 直接出力用swsの出力ピクセル形式
    // 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
    procedure DecodeAudioPacket(Packet: Pointer);
    // waveOutで再生完了したPCMバッファを解放する
    procedure CleanupAudioBuffers;
    // PCMバッファをwaveOutへ渡す
    procedure QueueAudioPcm(const Pcm: TBytes);
    // PCMバッファから音量確認用の統計を更新する
    procedure UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
    // 映像デコード負荷の統計を更新する
    procedure UpdateVideoLoadStats(ElapsedMs: Double);
    // 音声デコード負荷の統計を更新する
    procedure UpdateAudioLoadStats(ElapsedMs: Double);
  public
    // デコーダインスタンスを初期化する
    constructor Create;
    // 開いている動画を閉じてインスタンスを破棄する
    destructor Destroy; override;
    // 保持しているFFmpegリソースを解放する
    procedure Close;
    // 動画を開いてデコード可能な状態にする
    function Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
    function DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload;
    // 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
    function DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードする
    function DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
    function DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
    function DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を開始する
    function StartAudioPlayback(out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を停止する
    procedure StopAudioPlayback;
    // 一時デコーダで動画情報だけを読む
    class function ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean; static;
    // 一時デコーダで指定位置のフレームだけを読む
    class function DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload; static;
    property Info: TVideoInfo read FInfo;
    property AudioStats: TAudioPlaybackStats read FAudioStats;
    property DecodeStats: TDecodeLoadStats read FDecodeStats;
    property FileName: string read FFileName;
  end;

implementation

uses
  FFmpegApi, FFmpegDecodeStats, FFmpegFrameConvert, FFmpegStreamInfo;

// デコーダインスタンスを初期化する
constructor TFFmpegDecoder.Create;
begin
  inherited Create;
  FStreamIndex := -1;
  FAudioStreamIndex := -1;
  FWaveOut := 0;
  FAudioBuffers := TList<PAudioWaveBuffer>.Create;
end;

// 開いている動画を閉じてインスタンスを破棄する
destructor TFFmpegDecoder.Destroy;
begin
  Close;
  FAudioBuffers.Free;
  inherited Destroy;
end;

// 保持しているFFmpegリソースを解放する
procedure TFFmpegDecoder.Close;
var
  CodecContext: PAVCodecContext;
  AudioCodecContext: PAVCodecContext;
  FormatContext: PAVFormatContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
begin
  StopAudioPlayback;

  if FDirectSwsContext <> nil then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(FDirectSwsContext));
    FDirectSwsContext := nil;
  end;
  FDirectSwsSrcWidth := 0;
  FDirectSwsSrcHeight := 0;
  FDirectSwsSrcFormat := 0;
  FDirectSwsDstFormat := 0;

  Packet := PAVPacket(FPacket);
  if Assigned(Packet) then
  begin
    TFFmpegApi.av_packet_free(@Packet);
    FPacket := nil;
  end;

  Frame := PAVFrame(FFrame);
  if Assigned(Frame) then
  begin
    TFFmpegApi.av_frame_free(@Frame);
    FFrame := nil;
  end;

  AudioFrame := PAVFrame(FAudioFrame);
  if Assigned(AudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@AudioFrame);
    FAudioFrame := nil;
  end;

  SwrContext := PSwrContext(FSwrContext);
  if Assigned(SwrContext) then
  begin
    TFFmpegApi.swr_free(@SwrContext);
    FSwrContext := nil;
  end;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  if Assigned(AudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
    FAudioCodecContext := nil;
  end;

  CodecContext := PAVCodecContext(FCodecContext);
  if Assigned(CodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@CodecContext);
    FCodecContext := nil;
  end;

  FormatContext := PAVFormatContext(FFormatContext);
  if Assigned(FormatContext) then
  begin
    TFFmpegApi.avformat_close_input(@FormatContext);
    FFormatContext := nil;
  end;

  FFileName := '';
  FStream := nil;
  FStreamIndex := -1;
  FAudioStream := nil;
  FAudioStreamIndex := -1;
  FillChar(FInfo, SizeOf(FInfo), 0);
  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FillChar(FDecodeStats, SizeOf(FDecodeStats), 0);
  FAudioStats.LastPtsMs := -1;
end;

// 映像デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateVideoLoadStats(ElapsedMs: Double);
begin
  FFmpegDecodeStats.UpdateVideoLoadStats(FDecodeStats, ElapsedMs);
end;

// 音声デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateAudioLoadStats(ElapsedMs: Double);
begin
  FFmpegDecodeStats.UpdateAudioLoadStats(FDecodeStats, ElapsedMs);
end;

// デバッグ用の音声再生を開始する
function TFFmpegDecoder.StartAudioPlayback(out ErrorMessage: string): Boolean;
var
  WaveFormat: TWaveFormatEx;
  Ret: MMRESULT;
begin
  ErrorMessage := '';
  Result := False;

  StopAudioPlayback;

  if (not FInfo.Audio.Present) or (FAudioCodecContext = nil) or (FAudioStream = nil) or (FSwrContext = nil) then
  begin
    ErrorMessage := Format('Audio decoder is not open. present=%s codec=%s stream=%s swr=%s %s',
      [BoolToStr(FInfo.Audio.Present, True),
       BoolToStr(FAudioCodecContext <> nil, True),
       BoolToStr(FAudioStream <> nil, True),
       BoolToStr(FSwrContext <> nil, True),
       FInfo.Audio.OpenError]);
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := AUDIO_OUTPUT_CHANNELS;
  WaveFormat.nSamplesPerSec := AUDIO_OUTPUT_SAMPLE_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := WaveFormat.nChannels * WaveFormat.wBitsPerSample div 8;
  WaveFormat.nAvgBytesPerSec := WaveFormat.nSamplesPerSec * WaveFormat.nBlockAlign;

  Ret := waveOutOpen(@FWaveOut, WAVE_MAPPER, @WaveFormat, 0, 0, CALLBACK_NULL);
  if Ret <> MMSYSERR_NOERROR then
  begin
    FWaveOut := 0;
    ErrorMessage := Format('waveOutOpen failed: %d', [Ret]);
    Exit;
  end;

  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FAudioStats.LastPtsMs := -1;
  FAudioPlaybackActive := True;
  Result := True;
end;

// デバッグ用の音声再生を停止する
procedure TFFmpegDecoder.StopAudioPlayback;
var
  Buffer: PAudioWaveBuffer;
begin
  FAudioPlaybackActive := False;

  if FWaveOut <> 0 then
    waveOutReset(FWaveOut);

  if FAudioBuffers <> nil then
  begin
    while FAudioBuffers.Count > 0 do
    begin
      Buffer := FAudioBuffers[FAudioBuffers.Count - 1];
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(FAudioBuffers.Count - 1);
    end;
  end;

  if FWaveOut <> 0 then
  begin
    waveOutClose(FWaveOut);
    FWaveOut := 0;
  end;

  FAudioStats.QueuedBuffers := 0;
end;

// 動画を開いてデコード可能な状態にする
function TFFmpegDecoder.Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  AudioCodecContext: PAVCodecContext;
  Codec: PAVCodec;
  AudioCodec: PAVCodec;
  Packet: PAVPacket;
  Frame: PAVFrame;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
  Utf8FileName: UTF8String;
  Ret: Integer;
  StreamIndex: Integer;
  AudioStreamIndex: Integer;
  Stream: PAVStream;
  AudioStream: PAVStream;
  CodecPar: PAVCodecParameters;
  AudioCodecPar: PAVCodecParameters;
  InLayout: TAVChannelLayout;
  OutLayout: TAVChannelLayout;
  SwrRet: Integer;
begin
  Close;
  FillChar(Info, SizeOf(Info), 0);
  ErrorMessage := '';
  Result := False;
  FormatContext := nil;
  CodecContext := nil;
  AudioCodecContext := nil;
  Packet := nil;
  Frame := nil;
  AudioFrame := nil;
  SwrContext := nil;
  AudioStream := nil;
  AudioStreamIndex := -1;
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);

  try
    TFFmpegApi.EnsureLoaded;

    Utf8FileName := UTF8String(FileName);
    Ret := TFFmpegApi.avformat_open_input(@FormatContext, PAnsiChar(Utf8FileName), nil, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avformat_find_stream_info(FormatContext, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0);
    if StreamIndex < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(StreamIndex);
      Exit;
    end;

    Stream := StreamAt(FormatContext, StreamIndex);
    if not Assigned(Stream) then
    begin
      ErrorMessage := 'Video stream pointer is nil.';
      Exit;
    end;

    CodecPar := Stream.codecpar;
    if not Assigned(CodecPar) then
    begin
      ErrorMessage := 'Codec parameters pointer is nil.';
      Exit;
    end;

    Codec := TFFmpegApi.avcodec_find_decoder(CodecPar.codec_id);
    if not Assigned(Codec) then
    begin
      ErrorMessage := 'Decoder was not found.';
      Exit;
    end;

    CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
    if not Assigned(CodecContext) then
    begin
      ErrorMessage := 'avcodec_alloc_context3 failed.';
      Exit;
    end;

    Ret := TFFmpegApi.avcodec_parameters_to_context(CodecContext, CodecPar);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Packet := TFFmpegApi.av_packet_alloc();
    Frame := TFFmpegApi.av_frame_alloc();
    if (Packet = nil) or (Frame = nil) then
    begin
      ErrorMessage := 'Failed to allocate packet or frame.';
      Exit;
    end;

    if FormatContext.duration > 0 then
      Info.DurationSec := FormatContext.duration / AV_TIME_BASE;
    Info.Width := CodecPar.width;
    Info.Height := CodecPar.height;
    Info.FpsText := RationalToText(Stream.avg_frame_rate);
    Info.Fps := RationalToDouble(Stream.avg_frame_rate);
    ReadAudioInfo(FormatContext, Info);

    if (Info.Width <= 0) or (Info.Height <= 0) then
    begin
      ErrorMessage := 'Video stream was found, but size could not be read.';
      Exit;
    end;

    if Info.Audio.Present then
    begin
      AudioStreamIndex := Info.Audio.StreamIndex;
      AudioStream := StreamAt(FormatContext, AudioStreamIndex);
      if not Assigned(AudioStream) then
        Info.Audio.OpenError := 'Audio stream pointer is nil.'
      else if not Assigned(AudioStream.codecpar) then
        Info.Audio.OpenError := 'Audio codec parameters pointer is nil.'
      else
      begin
        AudioCodecPar := AudioStream.codecpar;
        AudioCodec := TFFmpegApi.avcodec_find_decoder(AudioCodecPar.codec_id);
        if not Assigned(AudioCodec) then
          Info.Audio.OpenError := Format('Audio decoder was not found. codec_id=%d', [AudioCodecPar.codec_id])
        else
        begin
          AudioCodecContext := TFFmpegApi.avcodec_alloc_context3(AudioCodec);
          if not Assigned(AudioCodecContext) then
            Info.Audio.OpenError := 'Audio avcodec_alloc_context3 failed.'
          else
          begin
            Ret := TFFmpegApi.avcodec_parameters_to_context(AudioCodecContext, AudioCodecPar);
            if Ret < 0 then
              Info.Audio.OpenError := 'Audio avcodec_parameters_to_context failed: ' + TFFmpegApi.ErrorText(Ret)
            else
            begin
              Ret := TFFmpegApi.avcodec_open2(AudioCodecContext, AudioCodec, nil);
              if Ret < 0 then
                Info.Audio.OpenError := 'Audio avcodec_open2 failed: ' + TFFmpegApi.ErrorText(Ret)
              else
              begin
                AudioFrame := TFFmpegApi.av_frame_alloc();
                if not Assigned(AudioFrame) then
                  Info.Audio.OpenError := 'Audio av_frame_alloc failed.'
                else
                begin
                  if AudioCodecPar.ch_layout.nb_channels > 0 then
                    Ret := TFFmpegApi.av_channel_layout_copy(@InLayout, @AudioCodecPar.ch_layout)
                  else
                  begin
                    TFFmpegApi.av_channel_layout_default(@InLayout, AUDIO_OUTPUT_CHANNELS);
                    Ret := 0;
                  end;

                  if Ret < 0 then
                    Info.Audio.OpenError := 'av_channel_layout_copy failed: ' + TFFmpegApi.ErrorText(Ret)
                  else
                  begin
                    TFFmpegApi.av_channel_layout_default(@OutLayout, AUDIO_OUTPUT_CHANNELS);
                    SwrRet := TFFmpegApi.swr_alloc_set_opts2(@SwrContext, @OutLayout, AV_SAMPLE_FMT_S16,
                      AUDIO_OUTPUT_SAMPLE_RATE, @InLayout, AudioCodecPar.format, AudioCodecPar.sample_rate, 0, nil);
                    if (SwrRet < 0) or not Assigned(SwrContext) then
                    begin
                      Info.Audio.OpenError := Format('swr_alloc_set_opts2 failed: %s rate=%d fmt=%d channels=%d',
                        [TFFmpegApi.ErrorText(SwrRet), AudioCodecPar.sample_rate, AudioCodecPar.format,
                         AudioCodecPar.ch_layout.nb_channels]);
                    end
                    else if TFFmpegApi.swr_init(SwrContext) < 0 then
                    begin
                      TFFmpegApi.swr_free(@SwrContext);
                      SwrContext := nil;
                      Info.Audio.OpenError := Format('swr_init failed. rate=%d fmt=%d channels=%d',
                        [AudioCodecPar.sample_rate, AudioCodecPar.format, AudioCodecPar.ch_layout.nb_channels]);
                    end;
                  end;
                end;
              end;
            end;
          end;
        end;
      end;
    end;

    FFileName := FileName;
    FFormatContext := FormatContext;
    FCodecContext := CodecContext;
    FStream := Stream;
    FStreamIndex := StreamIndex;
    FAudioCodecContext := AudioCodecContext;
    FAudioStream := AudioStream;
    FAudioStreamIndex := AudioStreamIndex;
    FAudioFrame := AudioFrame;
    FSwrContext := SwrContext;
    FPacket := Packet;
    FFrame := Frame;
    FInfo := Info;

    FormatContext := nil;
    CodecContext := nil;
    AudioCodecContext := nil;
    Packet := nil;
    Frame := nil;
    AudioFrame := nil;
    SwrContext := nil;
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;

  if Assigned(Frame) then
    TFFmpegApi.av_frame_free(@Frame);
  if Assigned(Packet) then
    TFFmpegApi.av_packet_free(@Packet);
  if Assigned(SwrContext) then
    TFFmpegApi.swr_free(@SwrContext);
  if Assigned(AudioFrame) then
    TFFmpegApi.av_frame_free(@AudioFrame);
  if Assigned(AudioCodecContext) then
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
  if Assigned(CodecContext) then
    TFFmpegApi.avcodec_free_context(@CodecContext);
  if Assigned(FormatContext) then
    TFFmpegApi.avformat_close_input(@FormatContext);
end;

// 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
function TFFmpegDecoder.DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  TargetTs: Int64;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToBitmap(Frame, Bitmap);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  TargetTs: Int64;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
              FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードする
function TFFmpegDecoder.DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          DecodeAudioPacket(Packet);
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBitmap(Frame, Bitmap);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    Stopwatch := TStopwatch.StartNew;
    if TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 then
    begin
      CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
        FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
      Stopwatch.Stop;
      UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
      PositionMs := StreamTimestampToMs(Stream, Frame.pts);
      Result := True;
      Exit;
    end;

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          DecodeAudioPacket(Packet);
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
            FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// waveOutで再生完了したPCMバッファを解放する
procedure TFFmpegDecoder.CleanupAudioBuffers;
var
  I: Integer;
  Buffer: PAudioWaveBuffer;
begin
  if FAudioBuffers = nil then
    Exit;

  for I := FAudioBuffers.Count - 1 downto 0 do
  begin
    Buffer := FAudioBuffers[I];
    if (FWaveOut = 0) or ((Buffer.Header.dwFlags and WHDR_DONE) <> 0) then
    begin
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(I);
    end;
  end;

  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファをwaveOutへ渡す
procedure TFFmpegDecoder.QueueAudioPcm(const Pcm: TBytes);
var
  Buffer: PAudioWaveBuffer;
begin
  if (not FAudioPlaybackActive) or (FWaveOut = 0) or (Length(Pcm) = 0) then
    Exit;

  CleanupAudioBuffers;

  New(Buffer);
  FillChar(Buffer^, SizeOf(Buffer^), 0);
  Buffer.Size := Length(Pcm);
  GetMem(Buffer.Data, Buffer.Size);
  Move(Pcm[0], Buffer.Data^, Buffer.Size);
  Buffer.Header.lpData := PAnsiChar(Buffer.Data);
  Buffer.Header.dwBufferLength := Buffer.Size;

  if waveOutPrepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  if waveOutWrite(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  FAudioBuffers.Add(Buffer);
  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファから音量確認用の統計を更新する
procedure TFFmpegDecoder.UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
var
  QueuedBuffers: Integer;
begin
  if FAudioBuffers <> nil then
    QueuedBuffers := FAudioBuffers.Count
  else
    QueuedBuffers := 0;
  FFmpegDecodeStats.UpdateAudioPlaybackStats(FAudioStats, Pcm, SampleCount, PtsMs, QueuedBuffers);
end;

// 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
procedure TFFmpegDecoder.DecodeAudioPacket(Packet: Pointer);
var
  AudioCodecContext: PAVCodecContext;
  AudioFrame: PAVFrame;
  AudioStream: PAVStream;
  Ret: Integer;
  OutData: array[0..0] of PByte;
  OutSamples: Integer;
  ConvertedSamples: Integer;
  Pcm: TBytes;
  PtsMs: Integer;
  Stopwatch: TStopwatch;
begin
  if (not FAudioPlaybackActive) or (Packet = nil) then
    Exit;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  AudioFrame := PAVFrame(FAudioFrame);
  AudioStream := PAVStream(FAudioStream);
  if (AudioCodecContext = nil) or (AudioFrame = nil) or (AudioStream = nil) or (FSwrContext = nil) then
    Exit;

  Stopwatch := TStopwatch.StartNew;
  try
    Inc(FAudioStats.AudioPackets);
    Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, PAVPacket(Packet));
    if Ret < 0 then
    begin
      Inc(FAudioStats.SendErrors);
      Exit;
    end;

    while TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0 do
    begin
      if FInfo.Audio.SampleRate > 0 then
        OutSamples := Ceil(AudioFrame.nb_samples * AUDIO_OUTPUT_SAMPLE_RATE / FInfo.Audio.SampleRate) + 256
      else
        OutSamples := AudioFrame.nb_samples + 256;

      SetLength(Pcm, OutSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
      OutData[0] := @Pcm[0];
      ConvertedSamples := TFFmpegApi.swr_convert(PSwrContext(FSwrContext), @OutData[0], OutSamples,
        @AudioFrame.data[0], AudioFrame.nb_samples);
      if ConvertedSamples <= 0 then
      begin
        Inc(FAudioStats.ConvertErrors);
        Continue;
      end;

      SetLength(Pcm, ConvertedSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
      PtsMs := StreamTimestampToMs(AudioStream, AudioFrame.pts);
      UpdateAudioStats(Pcm, ConvertedSamples, PtsMs);
      QueueAudioPcm(Pcm);
    end;
  finally
    Stopwatch.Stop;
    UpdateAudioLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
  end;
end;

// 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
function TFFmpegDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  AudioCodecContext: PAVCodecContext;
  Packet: PAVPacket;
  AudioFrame: PAVFrame;
  Ret: Integer;
  OutData: array[0..0] of PByte;
  OutSamples: Integer;
  ConvertedSamples: Integer;
  ConvertedBytes: Integer;
  OldBytes: Integer;

  procedure AppendDecodedAudioFrame;
  begin
    if FInfo.Audio.SampleRate > 0 then
      OutSamples := Ceil(AudioFrame.nb_samples * AUDIO_OUTPUT_SAMPLE_RATE / FInfo.Audio.SampleRate) + 256
    else
      OutSamples := AudioFrame.nb_samples + 256;

    OldBytes := Length(Pcm);
    SetLength(Pcm, OldBytes + OutSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
    OutData[0] := @Pcm[OldBytes];
    ConvertedSamples := TFFmpegApi.swr_convert(PSwrContext(FSwrContext), @OutData[0], OutSamples,
      @AudioFrame.data[0], AudioFrame.nb_samples);

    if ConvertedSamples <= 0 then
    begin
      SetLength(Pcm, OldBytes);
      Exit;
    end;

    ConvertedBytes := ConvertedSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt);
    SetLength(Pcm, OldBytes + ConvertedBytes);
    Inc(SampleCount, ConvertedSamples);
  end;

begin
  ErrorMessage := '';
  Finished := False;
  Result := False;

  if TargetSampleCount <= SampleCount then
  begin
    Result := True;
    Exit;
  end;

  FormatContext := PAVFormatContext(FFormatContext);
  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  Packet := PAVPacket(FPacket);
  AudioFrame := PAVFrame(FAudioFrame);

  if (not FInfo.Audio.Present) or (AudioCodecContext = nil) or (Packet = nil) or
     (AudioFrame = nil) or (FSwrContext = nil) or (FormatContext = nil) then
  begin
    ErrorMessage := 'Audio decoder is not open. ' + FInfo.Audio.OpenError;
    Exit;
  end;

  try
    while (SampleCount < TargetSampleCount) and (TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0) do
    begin
      try
        if Packet.stream_index <> FAudioStreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, Packet);
        if Ret < 0 then
          Continue;

        while (SampleCount < TargetSampleCount) and (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    if SampleCount < TargetSampleCount then
    begin
      Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, nil);
      if Ret >= 0 then
        while (SampleCount < TargetSampleCount) and (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      Finished := True;
    end;

    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 一時デコーダで動画情報だけを読む
class function TFFmpegDecoder.ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder;
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

// 一時デコーダで指定位置のフレームだけを読む
class function TFFmpegDecoder.DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder;
  Info: TVideoInfo;
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
    if Result then
      Result := Decoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

end.
