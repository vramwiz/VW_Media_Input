unit FFmpegDecoderSeekYuy2;

// 指定位置へseekし、映像フレームをYUY2バッファへ直接変換する。
// Debug時は失敗理由とdecode/transfer/convertの遅い段階を詳しくログへ記録する。

interface

uses
  FFmpegDecoderContext;

function DecodeFrameToYuy2(
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
  DECODE_TRACE_ENABLED = True; // Debug時だけデコードログを出す
  YUY2_SLOW_TOTAL_MS  = 16.0; // 1frame処理全体を遅いとみなすしきい値
  YUY2_SLOW_STAGE_MS  = 8.0;  // 個別stageを遅いとみなすしきい値
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
  if TotalMs < YUY2_SLOW_TOTAL_MS then
    Exit;

  Result := 'total';
  MaxStageMs := YUY2_SLOW_STAGE_MS;
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

function DecodeFrameToYuy2(
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
  LastPacketSendRet: Integer;
  LastDrainRet: Integer;
  LastReceiveRet: Integer;
  LastFramePts: Int64;
  LastFrameFmt: Integer;
  SlowStage: string;
{$ENDIF}
  DidTransfer: Boolean;
  TransferErrorMessage: string;

  function FinishFrame: Boolean;
  begin
    Result := False;
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
    CopyFrameToYuy2Buffer(ConvertSourceFrame, Buffer, BufferStride,
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
        SeekElapsedMs, ReadElapsedMs, DecodeElapsedMs, TransferElapsedMs, ConvertElapsedMs);
    end;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      DecodeTrace(Format(
        'seek_decode_yuy2 file="%s" decoder="%s" qsv=%s pos_ms=%d ' +
        'target_ts=%d frame_pts=%d read_packets=%d video_packets=%d ' +
        'decoded_frames=%d src_fmt=%d dst_fmt=%d hw_transfer=%s ' +
        'slow_stage="%s" elapsed_ms=%.3f seek_ms=%.3f read_ms=%.3f decode_ms=%.3f ' +
        'transfer_ms=%.3f convert_ms=%.3f',
        [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
         PositionMs, TargetTs, Frame.pts, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
          ConvertSourceFrame.format, Context.DirectSwsDstFormat,
          BoolToStr(DidTransfer, True), SlowStage,
          TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs, ReadElapsedMs, DecodeElapsedMs,
          TransferElapsedMs, ConvertElapsedMs]));
      if SlowStage <> '' then
        DecodeTrace(Format(
          'seek_decode_yuy2_slow file="%s" decoder="%s" qsv=%s stage="%s" ' +
          'pos_ms=%d target_ts=%d frame_pts=%d elapsed_ms=%.3f seek_ms=%.3f ' +
          'read_ms=%.3f decode_ms=%.3f transfer_ms=%.3f convert_ms=%.3f read_packets=%d ' +
          'video_packets=%d decoded_frames=%d',
          [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
           SlowStage, PositionMs, TargetTs, Frame.pts,
           TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs, ReadElapsedMs,
           DecodeElapsedMs, TransferElapsedMs,
           ConvertElapsedMs, ReadPacketCount, VideoPacketCount, DecodedFrameCount]));
    end;
{$ENDIF}
    Result := True;
  end;

  function ReceiveTargetFrame: Boolean;
  begin
    Result := False;
    while True do
    begin
      Ret := TFFmpegApi.avcodec_receive_frame(CodecContext, Frame);
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        LastReceiveRet := Ret;
{$ENDIF}
      if Ret <> 0 then
        Break;
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
      begin
        Inc(DecodedFrameCount);
        LastFramePts := Frame.pts;
        LastFrameFmt := Frame.format;
      end;
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
        Result := FinishFrame;
        Exit;
      end;
    end;
  end;
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
      SeekElapsedMs := 0;
      ReadElapsedMs := 0;
      DecodeElapsedMs := 0;
      TransferElapsedMs := 0;
      ConvertElapsedMs := 0;
      LastPacketSendRet := 0;
      LastReceiveRet := 0;
      LastFramePts := AV_NOPTS_VALUE;
      LastFrameFmt := -1;
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
{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          LastPacketSendRet := Ret;
{$ENDIF}
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

        if ReceiveTargetFrame then
        begin
          Result := True;
          Exit;
        end;
{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED and Stopwatch.IsRunning then
        begin
          Stopwatch.Stop;
          DecodeElapsedMs := DecodeElapsedMs + Stopwatch.Elapsed.TotalMilliseconds;
        end;
{$ENDIF}
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      Stopwatch := TStopwatch.StartNew;
{$ENDIF}
    Ret := TFFmpegApi.avcodec_send_packet(CodecContext, nil);
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      LastDrainRet := Ret;
{$ENDIF}
    if Ret >= 0 then
    begin
      if ReceiveTargetFrame then
      begin
        Result := True;
        Exit;
      end;
    end;
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED and Stopwatch.IsRunning then
    begin
      Stopwatch.Stop;
      DecodeElapsedMs := DecodeElapsedMs + Stopwatch.Elapsed.TotalMilliseconds;
    end;
{$ENDIF}

{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      TotalStopwatch.Stop;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      DecodeTrace(Format(
        'seek_decode_yuy2_failed file="%s" decoder="%s" qsv=%s pos_ms=%d ' +
        'target_ts=%d read_packets=%d video_packets=%d decoded_frames=%d ' +
        'last_pts=%d last_fmt=%d packet_send_ret=%d packet_send_err="%s" ' +
        'drain_ret=%d drain_err="%s" receive_ret=%d receive_err="%s" ' +
        'elapsed_ms=%.3f seek_ms=%.3f read_ms=%.3f decode_ms=%.3f',
        [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
         PositionMs, TargetTs, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
         LastFramePts, LastFrameFmt, LastPacketSendRet, TFFmpegApi.ErrorText(LastPacketSendRet),
         LastDrainRet, TFFmpegApi.ErrorText(LastDrainRet),
         LastReceiveRet, TFFmpegApi.ErrorText(LastReceiveRet),
         TotalStopwatch.Elapsed.TotalMilliseconds, SeekElapsedMs, ReadElapsedMs,
         DecodeElapsedMs]));
{$ENDIF}
    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
