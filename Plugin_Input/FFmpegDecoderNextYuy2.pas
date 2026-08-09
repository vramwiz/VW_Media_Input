unit FFmpegDecoderNextYuy2;

// 現在位置から次の映像フレームを読み、必要に応じてYUY2へ直接変換する。
// Debug時はdecode/transfer/convertの遅い段階をログへ記録する。

interface

uses
  FFmpegDecoderContext;

function DecodeNextFrameToYuy2Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
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
function DetectSlowStage(TotalMs, ReadMs, DecodeMs, TransferMs, ConvertMs: Double): string;
var
  MaxStageMs: Double;
begin
  Result := '';
  if TotalMs < YUY2_SLOW_TOTAL_MS then
    Exit;

  Result := 'total';
  MaxStageMs := YUY2_SLOW_STAGE_MS;
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

function DecodeNextFrameToYuy2Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
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
{$IFDEF DEBUG}
  DecodeStopwatch: TStopwatch;
  ReadStopwatch: TStopwatch;
  TransferStopwatch: TStopwatch;
  ConvertStopwatch: TStopwatch;
  TotalStopwatch: TStopwatch;
  DecodeElapsedMs: Double;
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

  function FinishFrame(const SourceName: string): Boolean;
  begin
    Result := False;
    if ConvertFrame then
    begin
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
        ConvertElapsedMs := ConvertElapsedMs + ConvertStopwatch.Elapsed.TotalMilliseconds;
      end;
{$ENDIF}
    end;

{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      TotalStopwatch.Stop;
      FFmpegDecodeStats.UpdateVideoStageStats(Context.DecodeStats,
        TotalStopwatch.Elapsed.TotalMilliseconds, DecodeElapsedMs, TransferElapsedMs,
        ConvertElapsedMs);
      SlowStage := DetectSlowStage(TotalStopwatch.Elapsed.TotalMilliseconds,
        ReadElapsedMs, DecodeElapsedMs, TransferElapsedMs, ConvertElapsedMs);
    end;
{$ENDIF}
    PositionMs := StreamTimestampToMs(Stream, Frame.pts);
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      DecodeTrace(Format(
        'next_decode_yuy2 file="%s" decoder="%s" qsv=%s convert=%s source=%s ' +
        'pos_ms=%d frame_pts=%d read_packets=%d video_packets=%d ' +
        'decoded_frames=%d src_fmt=%d dst_fmt=%d hw_transfer=%s ' +
        'slow_stage="%s" elapsed_ms=%.3f read_ms=%.3f decode_ms=%.3f ' +
        'transfer_ms=%.3f convert_ms=%.3f',
        [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
         BoolToStr(ConvertFrame, True), SourceName, PositionMs, Frame.pts,
         ReadPacketCount, VideoPacketCount, DecodedFrameCount,
          Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat,
          BoolToStr(DidTransfer, True), SlowStage,
         TotalStopwatch.Elapsed.TotalMilliseconds, ReadElapsedMs, DecodeElapsedMs,
         TransferElapsedMs, ConvertElapsedMs]));
      if SlowStage <> '' then
        DecodeTrace(Format(
          'next_decode_yuy2_slow file="%s" decoder="%s" qsv=%s stage="%s" ' +
          'convert=%s source=%s pos_ms=%d elapsed_ms=%.3f read_ms=%.3f decode_ms=%.3f ' +
          'transfer_ms=%.3f convert_ms=%.3f read_packets=%d ' +
          'video_packets=%d decoded_frames=%d',
          [Context.FileName, Context.VideoDecoderName, BoolToStr(Context.VideoUsesQsv, True),
           SlowStage, BoolToStr(ConvertFrame, True), SourceName, PositionMs,
           TotalStopwatch.Elapsed.TotalMilliseconds, ReadElapsedMs, DecodeElapsedMs,
           TransferElapsedMs,
           ConvertElapsedMs, ReadPacketCount, VideoPacketCount, DecodedFrameCount]));
    end;
{$ENDIF}
    Result := True;
  end;

begin
  ErrorMessage := '';
  PositionMs := -1;
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
      ConvertElapsedMs := 0;
      SlowStage := '';
    end;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      TotalStopwatch := TStopwatch.StartNew;
      DecodeStopwatch := TStopwatch.StartNew;
    end;
{$ENDIF}
    if TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 then
    begin
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
      begin
        Inc(DecodedFrameCount);
        DecodeStopwatch.Stop;
        DecodeElapsedMs := DecodeElapsedMs + DecodeStopwatch.Elapsed.TotalMilliseconds;
      end;
{$ENDIF}
      Result := FinishFrame('buffered');
      Exit;
    end;

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
        if Packet.stream_index = Context.AudioStreamIndex then
        begin
          Continue;
        end;

        if Packet.stream_index <> Context.StreamIndex then
          Continue;
{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          Inc(VideoPacketCount);
{$ENDIF}

{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          DecodeStopwatch := TStopwatch.StartNew;
{$ENDIF}
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
          begin
            DecodeStopwatch.Stop;
            DecodeElapsedMs := DecodeElapsedMs + DecodeStopwatch.Elapsed.TotalMilliseconds;
          end;
{$ENDIF}
          Continue;
        end;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
          begin
            Inc(DecodedFrameCount);
            DecodeStopwatch.Stop;
            DecodeElapsedMs := DecodeElapsedMs + DecodeStopwatch.Elapsed.TotalMilliseconds;
          end;
{$ENDIF}
          Result := FinishFrame('packet');
          Exit;
        end;
{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
        begin
          DecodeStopwatch.Stop;
          DecodeElapsedMs := DecodeElapsedMs + DecodeStopwatch.Elapsed.TotalMilliseconds;
        end;
{$ENDIF}
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
        'next_decode_yuy2_failed file="%s" convert=%s read_packets=%d ' +
        'video_packets=%d decoded_frames=%d elapsed_ms=%.3f read_ms=%.3f decode_ms=%.3f',
        [Context.FileName, BoolToStr(ConvertFrame, True), ReadPacketCount, VideoPacketCount, DecodedFrameCount,
         TotalStopwatch.Elapsed.TotalMilliseconds, ReadElapsedMs, DecodeElapsedMs]));
{$ENDIF}
    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
