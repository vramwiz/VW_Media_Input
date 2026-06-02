unit PluginAudioInputReader;

interface

uses
  Winapi.Windows, System.SysUtils, System.Math, AviUtl2InputTypes,
  FFmpegDecoderTypes, FFmpegDecoder;

type
  TPluginAudioInputReader = class
  private
    FDecoder: TFFmpegDecoder;
    FFormat: WAVEFORMATEX;
    FPcm: TBytes;
    FSampleCount: Integer;
    FDecodedSamples: Integer;
    FDecodeFinished: Boolean;
    FLastError: string;
    function GetFormatPtr: PWAVEFORMATEX;
    function GetHasAudio: Boolean;
  public
    destructor Destroy; override;
    function Open(const FileName: string; const VideoInfo: TVideoInfo; out ErrorMessage: string): Boolean;
    function ReadAudio(Start, SampleLength: Integer; Buffer: Pointer): Integer;
    property Format: WAVEFORMATEX read FFormat;
    property FormatPtr: PWAVEFORMATEX read GetFormatPtr;
    property HasAudio: Boolean read GetHasAudio;
    property SampleCount: Integer read FSampleCount;
    property LastError: string read FLastError;
  end;

implementation

function TPluginAudioInputReader.GetFormatPtr: PWAVEFORMATEX;
begin
  Result := @FFormat;
end;

function TPluginAudioInputReader.GetHasAudio: Boolean;
begin
  Result := FSampleCount > 0;
end;

destructor TPluginAudioInputReader.Destroy;
begin
  FDecoder.Free;
  FPcm := nil;
  inherited Destroy;
end;

function TPluginAudioInputReader.Open(const FileName: string; const VideoInfo: TVideoInfo; out ErrorMessage: string): Boolean;
var
  AudioInfo: TVideoInfo;
  AudioDurationSec: Double;
begin
  Result := False;
  ErrorMessage := '';
  FLastError := '';

  if (not VideoInfo.Audio.Present) or (VideoInfo.Audio.OpenError <> '') then
  begin
    ErrorMessage := VideoInfo.Audio.OpenError;
    FLastError := ErrorMessage;
    Exit;
  end;

  FDecoder := TFFmpegDecoder.Create;
  if not FDecoder.Open(FileName, AudioInfo, ErrorMessage) then
  begin
    FLastError := ErrorMessage;
    FreeAndNil(FDecoder);
    Exit;
  end;

  FFormat.wFormatTag := 1;
  FFormat.nChannels := 2;
  FFormat.nSamplesPerSec := 48000;
  FFormat.wBitsPerSample := 16;
  FFormat.nBlockAlign := FFormat.nChannels * FFormat.wBitsPerSample div 8;
  FFormat.nAvgBytesPerSec := FFormat.nSamplesPerSec * FFormat.nBlockAlign;
  FFormat.cbSize := 0;

  AudioDurationSec := VideoInfo.Audio.DurationSec;
  if AudioDurationSec <= 0 then
    AudioDurationSec := VideoInfo.DurationSec;
  if AudioDurationSec > 0 then
    FSampleCount := Max(1, Ceil(AudioDurationSec * FFormat.nSamplesPerSec));

  Result := FSampleCount > 0;
end;

function TPluginAudioInputReader.ReadAudio(Start, SampleLength: Integer; Buffer: Pointer): Integer;
var
  AvailableSamples: Integer;
  SamplesToCopy: Integer;
  SourceOffset: Integer;
  BytesToCopy: Integer;
begin
  Result := 0;
  if (Buffer = nil) or (SampleLength <= 0) or (FDecoder = nil) or (FSampleCount <= 0) then
    Exit;

  if Start < 0 then
    Start := 0;
  if Start >= FSampleCount then
    Exit;

  AvailableSamples := FSampleCount - Start;
  SamplesToCopy := Min(SampleLength, AvailableSamples);
  if (not FDecodeFinished) and (FDecodedSamples < Start + SamplesToCopy) then
  begin
    if not FDecoder.DecodeAudioPcm16Stereo48kUntil(Start + SamplesToCopy, FPcm,
      FDecodedSamples, FDecodeFinished, FLastError) then
      Exit;
    if FDecodeFinished and (FDecodedSamples < FSampleCount) then
      FSampleCount := FDecodedSamples;
  end;

  FillChar(Buffer^, SampleLength * FFormat.nBlockAlign, 0);
  if Start >= FDecodedSamples then
    Exit;

  SamplesToCopy := Min(SamplesToCopy, FDecodedSamples - Start);
  SourceOffset := Start * FFormat.nBlockAlign;
  BytesToCopy := SamplesToCopy * FFormat.nBlockAlign;
  if BytesToCopy > 0 then
    Move(FPcm[SourceOffset], Buffer^, BytesToCopy);

  Result := SamplesToCopy;
end;

end.
