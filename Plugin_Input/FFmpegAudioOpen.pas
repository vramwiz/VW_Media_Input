unit FFmpegAudioOpen;

interface

uses
  FFmpegApi, FFmpegDecoderTypes;

procedure OpenAudioDecoder(FormatContext: PAVFormatContext; var Info: TVideoInfo;
  out AudioCodecContext: PAVCodecContext; out AudioStream: PAVStream;
  out AudioStreamIndex: Integer; out AudioFrame: PAVFrame; out SwrContext: PSwrContext);

implementation

uses
  System.SysUtils;

procedure ReleaseAudioOpenResources(var AudioCodecContext: PAVCodecContext; var AudioFrame: PAVFrame;
  var SwrContext: PSwrContext);
begin
  if Assigned(SwrContext) then
  begin
    TFFmpegApi.swr_free(@SwrContext);
    SwrContext := nil;
  end;

  if Assigned(AudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@AudioFrame);
    AudioFrame := nil;
  end;

  if Assigned(AudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
    AudioCodecContext := nil;
  end;
end;

function PrepareAudioResampler(AudioCodecPar: PAVCodecParameters; out SwrContext: PSwrContext;
  out ErrorMessage: string): Boolean;
var
  InLayout: TAVChannelLayout;
  OutLayout: TAVChannelLayout;
  Ret: Integer;
begin
  Result := False;
  SwrContext := nil;
  ErrorMessage := '';
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);

  if AudioCodecPar.ch_layout.nb_channels > 0 then
    Ret := TFFmpegApi.av_channel_layout_copy(@InLayout, @AudioCodecPar.ch_layout)
  else
  begin
    TFFmpegApi.av_channel_layout_default(@InLayout, AUDIO_OUTPUT_CHANNELS);
    Ret := 0;
  end;

  if Ret < 0 then
  begin
    ErrorMessage := 'av_channel_layout_copy failed: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  try
    TFFmpegApi.av_channel_layout_default(@OutLayout, AUDIO_OUTPUT_CHANNELS);
    Ret := TFFmpegApi.swr_alloc_set_opts2(@SwrContext, @OutLayout, AV_SAMPLE_FMT_S16,
      AUDIO_OUTPUT_SAMPLE_RATE, @InLayout, AudioCodecPar.format, AudioCodecPar.sample_rate, 0, nil);
    if (Ret < 0) or not Assigned(SwrContext) then
    begin
      ErrorMessage := Format('swr_alloc_set_opts2 failed: %s rate=%d fmt=%d channels=%d',
        [TFFmpegApi.ErrorText(Ret), AudioCodecPar.sample_rate, AudioCodecPar.format,
         AudioCodecPar.ch_layout.nb_channels]);
      Exit;
    end;

    Ret := TFFmpegApi.swr_init(SwrContext);
    if Ret < 0 then
    begin
      TFFmpegApi.swr_free(@SwrContext);
      SwrContext := nil;
      ErrorMessage := Format('swr_init failed: %s rate=%d fmt=%d channels=%d',
        [TFFmpegApi.ErrorText(Ret), AudioCodecPar.sample_rate, AudioCodecPar.format,
         AudioCodecPar.ch_layout.nb_channels]);
      Exit;
    end;

    Result := True;
  finally
    TFFmpegApi.av_channel_layout_uninit(@OutLayout);
    TFFmpegApi.av_channel_layout_uninit(@InLayout);
  end;
end;

procedure OpenAudioDecoder(FormatContext: PAVFormatContext; var Info: TVideoInfo;
  out AudioCodecContext: PAVCodecContext; out AudioStream: PAVStream;
  out AudioStreamIndex: Integer; out AudioFrame: PAVFrame; out SwrContext: PSwrContext);
var
  AudioCodec: PAVCodec;
  AudioCodecPar: PAVCodecParameters;
  Ret: Integer;
begin
  AudioCodecContext := nil;
  AudioStream := nil;
  AudioStreamIndex := -1;
  AudioFrame := nil;
  SwrContext := nil;

  if not Info.Audio.Present then
    Exit;

  AudioStreamIndex := Info.Audio.StreamIndex;
  AudioStream := StreamAt(FormatContext, AudioStreamIndex);
  if not Assigned(AudioStream) then
  begin
    Info.Audio.OpenError := 'Audio stream pointer is nil.';
    AudioStreamIndex := -1;
    Exit;
  end;

  AudioCodecPar := AudioStream.codecpar;
  if not Assigned(AudioCodecPar) then
  begin
    Info.Audio.OpenError := 'Audio codec parameters pointer is nil.';
    AudioStream := nil;
    AudioStreamIndex := -1;
    Exit;
  end;

  AudioCodec := TFFmpegApi.avcodec_find_decoder(AudioCodecPar.codec_id);
  if not Assigned(AudioCodec) then
  begin
    Info.Audio.OpenError := Format('Audio decoder was not found. codec_id=%d', [AudioCodecPar.codec_id]);
    AudioStream := nil;
    AudioStreamIndex := -1;
    Exit;
  end;

  AudioCodecContext := TFFmpegApi.avcodec_alloc_context3(AudioCodec);
  if not Assigned(AudioCodecContext) then
  begin
    Info.Audio.OpenError := 'Audio avcodec_alloc_context3 failed.';
    AudioStream := nil;
    AudioStreamIndex := -1;
    Exit;
  end;

  Ret := TFFmpegApi.avcodec_parameters_to_context(AudioCodecContext, AudioCodecPar);
  if Ret < 0 then
    Info.Audio.OpenError := 'Audio avcodec_parameters_to_context failed: ' + TFFmpegApi.ErrorText(Ret);

  if Info.Audio.OpenError = '' then
  begin
    Ret := TFFmpegApi.avcodec_open2(AudioCodecContext, AudioCodec, nil);
    if Ret < 0 then
      Info.Audio.OpenError := 'Audio avcodec_open2 failed: ' + TFFmpegApi.ErrorText(Ret);
  end;

  if Info.Audio.OpenError = '' then
  begin
    AudioFrame := TFFmpegApi.av_frame_alloc();
    if not Assigned(AudioFrame) then
      Info.Audio.OpenError := 'Audio av_frame_alloc failed.';
  end;

  if Info.Audio.OpenError = '' then
    PrepareAudioResampler(AudioCodecPar, SwrContext, Info.Audio.OpenError);

  if Info.Audio.OpenError <> '' then
  begin
    ReleaseAudioOpenResources(AudioCodecContext, AudioFrame, SwrContext);
    AudioStream := nil;
    AudioStreamIndex := -1;
  end;
end;

end.
