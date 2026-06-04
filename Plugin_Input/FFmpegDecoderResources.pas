unit FFmpegDecoderResources;

interface

procedure ReleaseDecoderResources(
  var DirectSwsContext: Pointer;
  var DirectSwsSrcWidth: Integer;
  var DirectSwsSrcHeight: Integer;
  var DirectSwsSrcFormat: Integer;
  var DirectSwsDstFormat: Integer;
  var Packet: Pointer;
  var Frame: Pointer;
  var TransferFrame: Pointer;
  var AudioFrame: Pointer;
  var SwrContext: Pointer;
  var AudioCodecContext: Pointer;
  var CodecContext: Pointer;
  var QsvDeviceContext: Pointer;
  var FormatContext: Pointer
);

implementation

uses
  FFmpegApi;

procedure ReleaseDecoderResources(
  var DirectSwsContext: Pointer;
  var DirectSwsSrcWidth: Integer;
  var DirectSwsSrcHeight: Integer;
  var DirectSwsSrcFormat: Integer;
  var DirectSwsDstFormat: Integer;
  var Packet: Pointer;
  var Frame: Pointer;
  var TransferFrame: Pointer;
  var AudioFrame: Pointer;
  var SwrContext: Pointer;
  var AudioCodecContext: Pointer;
  var CodecContext: Pointer;
  var QsvDeviceContext: Pointer;
  var FormatContext: Pointer
);
var
  TypedPacket            : PAVPacket;
  TypedFrame             : PAVFrame;
  TypedTransferFrame     : PAVFrame;
  TypedAudioFrame        : PAVFrame;
  TypedSwrContext        : PSwrContext;
  TypedAudioCodecContext : PAVCodecContext;
  TypedCodecContext      : PAVCodecContext;
  TypedQsvDeviceContext  : PAVBufferRef;
  TypedFormatContext     : PAVFormatContext;
begin
  if DirectSwsContext <> nil then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(DirectSwsContext));
    DirectSwsContext := nil;
  end;
  DirectSwsSrcWidth := 0;
  DirectSwsSrcHeight := 0;
  DirectSwsSrcFormat := 0;
  DirectSwsDstFormat := 0;

  TypedPacket := PAVPacket(Packet);
  if Assigned(TypedPacket) then
  begin
    TFFmpegApi.av_packet_free(@TypedPacket);
    Packet := nil;
  end;

  TypedFrame := PAVFrame(Frame);
  if Assigned(TypedFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedFrame);
    Frame := nil;
  end;

  TypedTransferFrame := PAVFrame(TransferFrame);
  if Assigned(TypedTransferFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedTransferFrame);
    TransferFrame := nil;
  end;

  TypedAudioFrame := PAVFrame(AudioFrame);
  if Assigned(TypedAudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedAudioFrame);
    AudioFrame := nil;
  end;

  TypedSwrContext := PSwrContext(SwrContext);
  if Assigned(TypedSwrContext) then
  begin
    TFFmpegApi.swr_free(@TypedSwrContext);
    SwrContext := nil;
  end;

  TypedAudioCodecContext := PAVCodecContext(AudioCodecContext);
  if Assigned(TypedAudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@TypedAudioCodecContext);
    AudioCodecContext := nil;
  end;

  TypedCodecContext := PAVCodecContext(CodecContext);
  if Assigned(TypedCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@TypedCodecContext);
    CodecContext := nil;
  end;

  TypedQsvDeviceContext := PAVBufferRef(QsvDeviceContext);
  if Assigned(TypedQsvDeviceContext) then
  begin
    TFFmpegApi.av_buffer_unref(@TypedQsvDeviceContext);
    QsvDeviceContext := nil;
  end;

  TypedFormatContext := PAVFormatContext(FormatContext);
  if Assigned(TypedFormatContext) then
  begin
    TFFmpegApi.avformat_close_input(@TypedFormatContext);
    FormatContext := nil;
  end;
end;

end.
