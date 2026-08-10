unit FFmpegDecoderSeekBgrx32;

// 指定位置へseekし、映像フレームをBGRx32バッファへ直接変換する。
// QSV利用時は必要に応じてHW frameをCPUへ転送してから変換する。

interface

uses
  FFmpegDecoderContext;

function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.Diagnostics, System.SysUtils, Winapi.Windows,
  FFmpegApi, FFmpegDecodeStats, FFmpegFrameConvert, FFmpegQsvDecode, FFmpegStreamInfo;

const
{$IFDEF DEBUG}
  DECODE_TRACE_ENABLED = True;  // Debug時だけデコードログを出す
  BGRX_SLOW_TOTAL_MS   = 16.0;  // 1frame処理全体を遅いとみなすしきい値
  BGRX_SLOW_STAGE_MS   = 8.0;   // 個別stageを遅いとみなすしきい値
{$ELSE}
  DECODE_TRACE_ENABLED = False; // Releaseではログ文字列生成を避ける
{$ENDIF}

// Debug時のデコードログをTEMPへ追記する。
procedure DecodeTrace(const Msg: string);
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
  if not DECODE_TRACE_ENABLED then
    Exit;

  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [FFmpegDecoder] ' + Msg;
  OutputDebugString(PChar(Line));
  LogFileName := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VW_Media_Input_decode.log';
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

{$IFDEF DEBUG}
function DetectSlowStage(TotalMs, SeekMs, ReadMs, DecodeMs, TransferMs, ConvertMs: Double): string;
var
  MaxStageMs: Double;
begin
  Result := '';
  if TotalMs < BGRX_SLOW_TOTAL_MS then
    Exit;

  Result := 'total';
  MaxStageMs := BGRX_SLOW_STAGE_MS;
  if SeekMs >= MaxStageMs then
  begin
    Result := 'seek';
    MaxStageMs := SeekMs;
  end;
  if ReadMs >= MaxStageMs then
  begin
    Result := 'read';
    MaxStageMs := ReadMs;
  end;
  if DecodeMs >= MaxStageMs then
  begin
    Result := 'decode';
    MaxStageMs := DecodeMs;
  end;
  if TransferMs >= MaxStageMs then
  begin
    Result := 'transfer';
    MaxStageMs := TransferMs;
  end;
  if ConvertMs >= MaxStageMs then
    Result := 'convert';
end;
{$ENDIF}

function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  ConvertSourceFrame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  TargetTs: Int64;
  MaxPostSeekPacketTs: Int64;
  QsvTimestampTolerance: Int64;
  DiscardedQsvFrameCount: Integer;
{$IFDEF DEBUG}
  Stopwatch: TStopwatch;
  SeekStopwatch: TStopwatch;
  ReadStopwatch: TStopwatch;
  ConvertStopwatch: TStopwatch;
  TransferStopwatch: TStopwatch;
  TotalStopwatch: TStopwatch;
  DecodeElapsedMs: Double;
  SeekElapsedMs: Double;
  ReadElapsedMs: Double;
  TransferElapsedMs: Double;
  ConvertElapsedMs: Double;
  ReadPacketCount: Integer;
  VideoPacketCount: Integer;
  DecodedFrameCount: Integer;
  SlowStage: string;
{$ENDIF}
  DidTransfer: Boolean;
  TransferErrorMessage: string;
begin
  ErrorMessage := '';
  Result := False;

  if Context = nil then
  begin
    ErrorMessage := 'Decoder context is nil.';
    Exit;
  end;

  FormatContext := PAVFormatContext(Context.FormatContext);
  CodecContext := PAVCodecContext(Context.CodecContext);
  Packet := PAVPacket(Context.Packet);
  Frame := PAVFrame(Context.Frame);
  Stream := PAVStream(Context.Stream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      ReadPacketCount := 0;
      VideoPacketCount := 0;
      DecodedFrameCount := 0;
      ReadElapsedMs := 0;
      DecodeElapsedMs := 0;
      TransferElapsedMs := 0;
      SlowStage := '';
    end;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      TotalStopwatch := TStopwatch.StartNew;
{$ENDIF}
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    MaxPostSeekPacketTs := AV_NOPTS_VALUE;
    QsvTimestampTolerance := QsvSeekTimestampTolerance(Stream);
    DiscardedQsvFrameCount := 0;
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      SeekStopwatch := TStopwatch.StartNew;
{$ENDIF}
    Ret := TFFmpegApi.av_seek_frame(FormatContext, Context.StreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      SeekStopwatch.Stop;
      SeekElapsedMs := SeekStopwatch.Elapsed.TotalMilliseconds;
    end;
{$ENDIF}
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if Context.AudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(Context.AudioCodecContext));

    while True do
    begin
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        ReadStopwatch := TStopwatch.StartNew;
{$ENDIF}
      Ret := TFFmpegApi.av_read_frame(FormatContext, Packet);
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
      begin
        ReadStopwatch.Stop;
        ReadElapsedMs := ReadElapsedMs + ReadStopwatch.Elapsed.TotalMilliseconds;
      end;
{$ENDIF}
      if Ret < 0 then
        Break;
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        Inc(ReadPacketCount);
{$ENDIF}
      try
        if Packet.stream_index = Context.StreamIndex then
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
            Inc(VideoPacketCount);
{$ENDIF}
        end;

        if Packet.stream_index <> Context.StreamIndex then
          Continue;

        UpdateQsvSeekPacketTimestamp(Packet, MaxPostSeekPacketTs);

{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          Stopwatch := TStopwatch.StartNew;
{$ENDIF}
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
          begin
            Stopwatch.Stop;
            DecodeElapsedMs := DecodeElapsedMs + Stopwatch.Elapsed.TotalMilliseconds;
          end;
{$ENDIF}
          Continue;
        end;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
            Inc(DecodedFrameCount);
{$ENDIF}
          if IsStaleQsvSeekFrame(Context.VideoUsesQsv, Frame.pts,
            MaxPostSeekPacketTs, QsvTimestampTolerance) then
          begin
            Inc(DiscardedQsvFrameCount);
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
              DecodeTrace(Format(
                'qsv_seek_stale_discard file="%s" frame_pts=%d target_ts=%d ' +
                'max_packet_ts=%d tolerance_ts=%d discarded=%d',
                [Context.FileName, Frame.pts, TargetTs, MaxPostSeekPacketTs,
                 QsvTimestampTolerance, DiscardedQsvFrameCount]));
{$ENDIF}
            Continue;
          end;
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
            begin
              Stopwatch.Stop;
              DecodeElapsedMs := DecodeElapsedMs + Stopwatch.Elapsed.TotalMilliseconds;
            end;
{$ENDIF}
            ConvertSourceFrame := Frame;
            DidTransfer := False;
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
              TransferStopwatch := TStopwatch.StartNew;
{$ENDIF}
            if not TransferFrameToCpuIfNeeded(Frame, PAVFrame(Context.TransferFrame),
              ConvertSourceFrame, DidTransfer, TransferErrorMessage) then
            begin
              ErrorMessage := 'Failed to transfer video frame: ' + TransferErrorMessage;
              Exit;
            end;
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
            begin
              TransferStopwatch.Stop;
              if DidTransfer then
                TransferElapsedMs := TransferElapsedMs + TransferStopwatch.Elapsed.TotalMilliseconds;
              ConvertStopwatch := TStopwatch.StartNew;
            end;
{$ENDIF}
            CopyFrameToBgrx32Buffer(ConvertSourceFrame, Buffer, BufferStride,
              Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
              Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
            begin
              ConvertStopwatch.Stop;
              ConvertElapsedMs := ConvertStopwatch.Elapsed.TotalMilliseconds;
              TotalStopwatch.Stop;
              FFmpegDecodeStats.UpdateVideoStageStats(Context.DecodeStats,
                TotalStopwatch.Elapsed.TotalMilliseconds, DecodeElapsedMs, TransferElapsedMs,
                ConvertElapsedMs);
              SlowStage := DetectSlowStage(TotalStopwatch.Elapsed.TotalMilliseconds,
                SeekElapsedMs, ReadElapsedMs, DecodeElapsedMs, TransferElapsedMs,
                ConvertElapsedMs);
            end;
{$ENDIF}
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
            begin
              DecodeTrace(Format(
                'seek_decode file="%s" decoder="%s" qsv=%s pos_ms=%d ' +
                'target_ts=%d frame_pts=%d read_packets=%d video_packets=%d ' +
                'decoded_frames=%d src_fmt=%d dst_fmt=%d slow_stage="%s" elapsed_ms=%.3f ' +
                'seek_ms=%.3f read_ms=%.3f decode_ms=%.3f transfer_ms=%.3f convert_ms=%.3f',
                [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
                 PositionMs, TargetTs, Frame.pts, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
                 Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat, SlowStage,
                 TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs, ReadElapsedMs,
                 DecodeElapsedMs,
                 TransferElapsedMs, ConvertElapsedMs]));
              if SlowStage <> '' then
                DecodeTrace(Format(
                  'seek_decode_slow file="%s" decoder="%s" qsv=%s stage="%s" ' +
                  'pos_ms=%d target_ts=%d frame_pts=%d elapsed_ms=%.3f seek_ms=%.3f ' +
                  'read_ms=%.3f decode_ms=%.3f transfer_ms=%.3f convert_ms=%.3f ' +
                  'read_packets=%d video_packets=%d decoded_frames=%d',
                  [Context.FileName, Context.VideoDecoderName,
                   BoolToStr(Context.VideoUsesQsv, True), SlowStage, PositionMs, TargetTs,
                   Frame.pts, TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs,
                   ReadElapsedMs, DecodeElapsedMs, TransferElapsedMs, ConvertElapsedMs,
                   ReadPacketCount, VideoPacketCount, DecodedFrameCount]));
            end;
{$ENDIF}
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      TotalStopwatch.Stop;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      DecodeTrace(Format(
        'seek_decode_failed file="%s" pos_ms=%d target_ts=%d read_packets=%d ' +
        'video_packets=%d decoded_frames=%d elapsed_ms=%.3f seek_ms=%.3f read_ms=%.3f',
        [Context.FileName, PositionMs, TargetTs, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
         TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs, ReadElapsedMs]));
{$ENDIF}
    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
