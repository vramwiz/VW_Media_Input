unit FFmpegQsvDecode;

interface

uses
  FFmpegApi;

const
  AV_CODEC_ID_MPEG2VIDEO = 2;   // MPEG-2 videoのFFmpeg codec id
  AV_CODEC_ID_MJPEG      = 7;   // MJPEGのFFmpeg codec id
  AV_CODEC_ID_H264       = 27;  // H.264のFFmpeg codec id
  AV_CODEC_ID_VP8        = 139; // VP8のFFmpeg codec id
  AV_CODEC_ID_VP9        = 167; // VP9のFFmpeg codec id
  AV_CODEC_ID_HEVC       = 173; // HEVC/H.265のFFmpeg codec id
  AV_CODEC_ID_AV1        = 225; // AV1のFFmpeg codec id

// codec idから対応するQSV decoder名を返す。
function QsvDecoderNameForCodecId(CodecId: Integer): AnsiString;
// QSV用のHW device contextを作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
// seek後に送ったpacketの最大timestampを更新する。
procedure UpdateQsvSeekPacketTimestamp(Packet: PAVPacket; var MaxTimestamp: Int64);
// QSVのフレーム並べ替えを許容するtimestamp幅を返す。
function QsvSeekTimestampTolerance(Stream: PAVStream): Int64;
// seek前の非同期出力が残っているかをpacket timestampとの対応で判定する。
function IsStaleQsvSeekFrame(VideoUsesQsv: Boolean; FramePts,
  MaxPacketTimestamp, TimestampTolerance: Int64): Boolean;
// QSV HW frameの場合だけCPU側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;

implementation

uses
  System.Math;

// codec idから対応するQSV decoder名を返す。
function QsvDecoderNameForCodecId(CodecId: Integer): AnsiString;
begin
  case CodecId of
    AV_CODEC_ID_H264:
      Result := 'h264_qsv';
    AV_CODEC_ID_HEVC:
      Result := 'hevc_qsv';
    AV_CODEC_ID_MPEG2VIDEO:
      Result := 'mpeg2_qsv';
    AV_CODEC_ID_MJPEG:
      Result := 'mjpeg_qsv';
    AV_CODEC_ID_VP8:
      Result := 'vp8_qsv';
    AV_CODEC_ID_VP9:
      Result := 'vp9_qsv';
    AV_CODEC_ID_AV1:
      Result := 'av1_qsv';
  else
    Result := '';
  end;
end;

// QSV用のHW device contextを作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
var
  Ret: Integer;
begin
  DeviceContext := nil;
  ErrorMessage := '';
  Ret := TFFmpegApi.av_hwdevice_ctx_create(@DeviceContext, AV_HWDEVICE_TYPE_QSV, nil, nil, 0);
  Result := Ret >= 0;
  if not Result then
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
end;

procedure UpdateQsvSeekPacketTimestamp(Packet: PAVPacket; var MaxTimestamp: Int64);
begin
  if Packet = nil then
    Exit;
  if (Packet.pts <> AV_NOPTS_VALUE) and
     ((MaxTimestamp = AV_NOPTS_VALUE) or (Packet.pts > MaxTimestamp)) then
    MaxTimestamp := Packet.pts;
  if (Packet.dts <> AV_NOPTS_VALUE) and
     ((MaxTimestamp = AV_NOPTS_VALUE) or (Packet.dts > MaxTimestamp)) then
    MaxTimestamp := Packet.dts;
end;

function QsvSeekTimestampTolerance(Stream: PAVStream): Int64;
var
  Fps: Double;
  ToleranceMs: Integer;
begin
  Result := 1;
  if Stream = nil then
    Exit;

  Fps := RationalToDouble(Stream.avg_frame_rate);
  if Fps > 0 then
    ToleranceMs := EnsureRange(Ceil(3000.0 / Fps), 40, 250)
  else
    ToleranceMs := 125;
  Result := Abs(StreamTimestampFromMs(Stream, ToleranceMs));
  if Result <= 0 then
    Result := 1;
end;

function IsStaleQsvSeekFrame(VideoUsesQsv: Boolean; FramePts,
  MaxPacketTimestamp, TimestampTolerance: Int64): Boolean;
begin
  Result := VideoUsesQsv and
    (FramePts <> AV_NOPTS_VALUE) and
    (MaxPacketTimestamp <> AV_NOPTS_VALUE) and
    (FramePts > MaxPacketTimestamp + TimestampTolerance);
end;

// QSV HW frameの場合だけCPU側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;
var
  Ret: Integer;
begin
  CpuFrame := SourceFrame;
  DidTransfer := False;
  ErrorMessage := '';
  Result := True;

  if SourceFrame = nil then
    Exit;

  if SourceFrame.format <> AV_PIX_FMT_QSV then
    Exit;

  if TransferFrame = nil then
  begin
    ErrorMessage := 'Transfer frame is nil.';
    Result := False;
    Exit;
  end;

  TFFmpegApi.av_frame_unref(TransferFrame);
  Ret := TFFmpegApi.av_hwframe_transfer_data(TransferFrame, SourceFrame, 0);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    Result := False;
    Exit;
  end;

  CpuFrame := TransferFrame;
  DidTransfer := True;
end;

end.
