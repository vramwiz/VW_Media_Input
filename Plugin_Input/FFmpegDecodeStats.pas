unit FFmpegDecodeStats;

interface

uses
  System.SysUtils, FFmpegDecoderTypes;

procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);

implementation

uses
  System.Math;

procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  Stats.VideoLastMs := ElapsedMs;
  if Stats.VideoFrames = 0 then
    Stats.VideoAverageMs := ElapsedMs
  else
    Stats.VideoAverageMs := (Stats.VideoAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > Stats.VideoMaxMs then
    Stats.VideoMaxMs := ElapsedMs;
  Inc(Stats.VideoFrames);
end;

procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  Stats.AudioLastMs := ElapsedMs;
  if Stats.AudioPackets = 0 then
    Stats.AudioAverageMs := ElapsedMs
  else
    Stats.AudioAverageMs := (Stats.AudioAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > Stats.AudioMaxMs then
    Stats.AudioMaxMs := ElapsedMs;
  Inc(Stats.AudioPackets);
end;

procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);
var
  I: Integer;
  Value: SmallInt;
  AbsValue: Integer;
  Peak: Integer;
  NonZero: Integer;
  SumSquares: Double;
  TotalValues: Integer;
begin
  TotalValues := Length(Pcm) div SizeOf(SmallInt);
  if TotalValues <= 0 then
    Exit;

  Peak := 0;
  NonZero := 0;
  SumSquares := 0;
  for I := 0 to TotalValues - 1 do
  begin
    Value := PSmallInt(@Pcm[I * SizeOf(SmallInt)])^;
    AbsValue := Abs(Integer(Value));
    if AbsValue > Peak then
      Peak := AbsValue;
    if Value <> 0 then
      Inc(NonZero);
    SumSquares := SumSquares + Value * Value;
  end;

  Inc(Stats.DecodedFrames);
  Inc(Stats.DecodedSamples, SampleCount);
  Stats.LastPtsMs := PtsMs;
  Stats.Peak := Peak;
  Stats.Rms := Sqrt(SumSquares / TotalValues);
  Stats.NonZeroPercent := NonZero * 100.0 / TotalValues;
  Stats.QueuedBuffers := QueuedBuffers;
end;

end.
