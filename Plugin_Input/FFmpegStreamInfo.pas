unit FFmpegStreamInfo;

interface

uses
  FFmpegApi, FFmpegDecoderTypes;

procedure ReadAudioInfo(FormatContext: PAVFormatContext; var Info: TVideoInfo);

implementation

// 音声ストリームの基本情報を読む
procedure ReadAudioInfo(FormatContext: PAVFormatContext; var Info: TVideoInfo);
var
  StreamIndex: Integer;
  Stream: PAVStream;
  CodecPar: PAVCodecParameters;
begin
  StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0);
  if StreamIndex < 0 then
    Exit;

  Stream := StreamAt(FormatContext, StreamIndex);
  if not Assigned(Stream) or not Assigned(Stream.codecpar) then
    Exit;

  CodecPar := Stream.codecpar;
  Info.Audio.Present := True;
  Info.Audio.StreamIndex := StreamIndex;
  Info.Audio.SampleRate := CodecPar.sample_rate;
  Info.Audio.Channels := CodecPar.ch_layout.nb_channels;
  Info.Audio.SampleFormat := CodecPar.format;
  Info.Audio.SampleFormatName := SampleFormatName(CodecPar.format);

  if (Stream.duration > 0) and (Stream.time_base.num > 0) and (Stream.time_base.den > 0) then
    Info.Audio.DurationSec := Stream.duration * Stream.time_base.num / Stream.time_base.den
  else
    Info.Audio.DurationSec := Info.DurationSec;
end;

end.
