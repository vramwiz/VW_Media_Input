unit FFmpegAudioRead;

interface

uses
  System.SysUtils, FFmpegApi;

function DecodeAudioPcm16Stereo48kUntil(
  FormatContext: PAVFormatContext;
  AudioCodecContext: PAVCodecContext;
  Packet: PAVPacket;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
  AudioPresent: Boolean;
  const AudioOpenError: string;
  AudioStreamIndex: Integer;
  SourceSampleRate: Integer;
  TargetSampleCount: Integer;
  var Pcm: TBytes;
  var SampleCount: Integer;
  out Finished: Boolean;
  out ErrorMessage: string
): Boolean;

implementation

uses
  FFmpegAudioConvert;

function DecodeAudioPcm16Stereo48kUntil(
  FormatContext: PAVFormatContext;
  AudioCodecContext: PAVCodecContext;
  Packet: PAVPacket;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
  AudioPresent: Boolean;
  const AudioOpenError: string;
  AudioStreamIndex: Integer;
  SourceSampleRate: Integer;
  TargetSampleCount: Integer;
  var Pcm: TBytes;
  var SampleCount: Integer;
  out Finished: Boolean;
  out ErrorMessage: string
): Boolean;
var
  Ret: Integer;
  Chunk: TBytes;
  ChunkSampleCount: Integer;
  OldBytes: Integer;

  procedure AppendDecodedAudioFrame;
  begin
    if not ConvertAudioFrameToPcm16Stereo48k(AudioFrame, SwrContext,
      SourceSampleRate, Chunk, ChunkSampleCount) then
      Exit;

    OldBytes := Length(Pcm);
    SetLength(Pcm, OldBytes + Length(Chunk));
    if Length(Chunk) > 0 then
      Move(Chunk[0], Pcm[OldBytes], Length(Chunk));
    Inc(SampleCount, ChunkSampleCount);
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

  if (not AudioPresent) or (AudioCodecContext = nil) or (Packet = nil) or
     (AudioFrame = nil) or (SwrContext = nil) or (FormatContext = nil) then
  begin
    ErrorMessage := 'Audio decoder is not open. ' + AudioOpenError;
    Exit;
  end;

  try
    while (SampleCount < TargetSampleCount) and
      (TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0) do
    begin
      try
        if Packet.stream_index <> AudioStreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, Packet);
        if Ret < 0 then
          Continue;

        while (SampleCount < TargetSampleCount) and
          (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    if SampleCount < TargetSampleCount then
    begin
      Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, nil);
      if Ret >= 0 then
        while (SampleCount < TargetSampleCount) and
          (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      Finished := True;
    end;

    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
