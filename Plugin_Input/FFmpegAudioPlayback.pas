unit FFmpegAudioPlayback;

interface

uses
  Winapi.MMSystem, System.Generics.Collections, System.SysUtils,
  FFmpegApi, FFmpegDecoderTypes;

function StartAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  var AudioStats: TAudioPlaybackStats;
  const Info: TVideoInfo;
  AudioCodecContext: Pointer;
  AudioStream: Pointer;
  SwrContext: Pointer;
  out ErrorMessage: string
): Boolean;

procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  var AudioStats: TAudioPlaybackStats
);

implementation

procedure CleanupAudioBuffers(
  WaveOut: HWAVEOUT;
  AudioBuffers: TList<PAudioWaveBuffer>;
  var AudioStats: TAudioPlaybackStats
);
var
  I: Integer;
  Buffer: PAudioWaveBuffer;
begin
  if AudioBuffers = nil then
    Exit;

  for I := AudioBuffers.Count - 1 downto 0 do
  begin
    Buffer := AudioBuffers[I];
    if (WaveOut = 0) or ((Buffer.Header.dwFlags and WHDR_DONE) <> 0) then
    begin
      if WaveOut <> 0 then
        waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      AudioBuffers.Delete(I);
    end;
  end;

  AudioStats.QueuedBuffers := AudioBuffers.Count;
end;

function StartAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  var AudioStats: TAudioPlaybackStats;
  const Info: TVideoInfo;
  AudioCodecContext: Pointer;
  AudioStream: Pointer;
  SwrContext: Pointer;
  out ErrorMessage: string
): Boolean;
var
  WaveFormat: TWaveFormatEx;
  Ret: MMRESULT;
begin
  ErrorMessage := '';
  Result := False;

  StopAudioPlayback(WaveOut, AudioPlaybackActive, AudioBuffers, AudioStats);

  if (not Info.Audio.Present) or (AudioCodecContext = nil) or
     (AudioStream = nil) or (SwrContext = nil) then
  begin
    ErrorMessage := Format('Audio decoder is not open. present=%s codec=%s stream=%s swr=%s %s',
      [BoolToStr(Info.Audio.Present, True),
       BoolToStr(AudioCodecContext <> nil, True),
       BoolToStr(AudioStream <> nil, True),
       BoolToStr(SwrContext <> nil, True),
       Info.Audio.OpenError]);
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := AUDIO_OUTPUT_CHANNELS;
  WaveFormat.nSamplesPerSec := AUDIO_OUTPUT_SAMPLE_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := WaveFormat.nChannels * WaveFormat.wBitsPerSample div 8;
  WaveFormat.nAvgBytesPerSec := WaveFormat.nSamplesPerSec * WaveFormat.nBlockAlign;

  Ret := waveOutOpen(@WaveOut, WAVE_MAPPER, @WaveFormat, 0, 0, CALLBACK_NULL);
  if Ret <> MMSYSERR_NOERROR then
  begin
    WaveOut := 0;
    ErrorMessage := Format('waveOutOpen failed: %d', [Ret]);
    Exit;
  end;

  FillChar(AudioStats, SizeOf(AudioStats), 0);
  AudioStats.LastPtsMs := -1;
  AudioPlaybackActive := True;
  Result := True;
end;

procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  var AudioStats: TAudioPlaybackStats
);
var
  Buffer: PAudioWaveBuffer;
begin
  AudioPlaybackActive := False;

  if WaveOut <> 0 then
    waveOutReset(WaveOut);

  if AudioBuffers <> nil then
  begin
    while AudioBuffers.Count > 0 do
    begin
      Buffer := AudioBuffers[AudioBuffers.Count - 1];
      if WaveOut <> 0 then
        waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      AudioBuffers.Delete(AudioBuffers.Count - 1);
    end;
  end;

  if WaveOut <> 0 then
  begin
    waveOutClose(WaveOut);
    WaveOut := 0;
  end;

  AudioStats.QueuedBuffers := 0;
end;

end.
