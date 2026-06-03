unit FFmpegFrameConvert;

interface

uses
  Vcl.Graphics, FFmpegApi;

// AVFrameをAviUtl2向け32bit BGRxバッファへ変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrameをAviUtl2向けYUY2バッファへ変換する。
procedure CopyFrameToYuy2Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrameをデバッグ表示用TBitmapへ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);

implementation

uses
  System.SysUtils;

// 変換元フレームと出力バッファの基本条件を確認する。
procedure EnsureFrameAndBuffer(Frame: PAVFrame; Buffer: Pointer);
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');
  if Buffer = nil then
    raise Exception.Create('Destination buffer is nil.');
end;

// sws_scale用コンテキストを入力/出力形式ごとに再利用する。
procedure EnsureSwsContext(
  Frame: PAVFrame;
  DstFormat: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
begin
  if Assigned(ScaleContext) and
     ((CachedSrcWidth <> Frame.width) or
      (CachedSrcHeight <> Frame.height) or
      (CachedSrcFormat <> Frame.format) or
      (CachedDstFormat <> DstFormat)) then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(ScaleContext));
    ScaleContext := nil;
  end;

  if not Assigned(ScaleContext) then
  begin
    ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
      Frame.width, Frame.height, DstFormat, SWS_BILINEAR, nil, nil, nil);
    CachedSrcWidth := Frame.width;
    CachedSrcHeight := Frame.height;
    CachedSrcFormat := Frame.format;
    CachedDstFormat := DstFormat;
  end;

  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');
end;

// AVFrameをAviUtl2向け32bit BGRxバッファへ変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData: array[0..3] of PByte; // sws_scaleへ渡す出力プレーン
  DstLinesize: array[0..3] of Integer; // sws_scaleへ渡す出力ラインサイズ
  DstFormat: Integer; // FFmpegの出力ピクセル形式
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width * 4;
  DstFormat := AV_PIX_FMT_BGRA;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  // 正のBITMAPINFOHEADER高さに合わせてBGRxはボトムアップで渡す。
  DstData[0] := PByte(NativeUInt(Buffer) + NativeUInt((Frame.height - 1) * BufferStride));
  DstLinesize[0] := -BufferStride;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrameをAviUtl2向けYUY2バッファへ変換する。
procedure CopyFrameToYuy2Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData: array[0..3] of PByte; // sws_scaleへ渡す出力プレーン
  DstLinesize: array[0..3] of Integer; // sws_scaleへ渡す出力ラインサイズ
  DstFormat: Integer; // FFmpegの出力ピクセル形式
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width * 2;
  DstFormat := AV_PIX_FMT_YUYV422;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  // AviUtl2のYUY2入力は表示順の先頭行から渡す。
  DstData[0] := PByte(Buffer);
  DstLinesize[0] := BufferStride;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrameをデバッグ表示用TBitmapへ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);
var
  ScaleContext: PSwsContext; // Bitmap変換専用の一時swsコンテキスト
  DstData: array[0..3] of PByte; // sws_scaleへ渡すBitmap側プレーン
  DstLinesize: array[0..3] of Integer; // Bitmap側ラインサイズ
  Stride: NativeInt; // BitmapのScanLine間隔
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');

  Bitmap.PixelFormat := pf24bit;
  Bitmap.SetSize(Frame.width, Frame.height);

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := Bitmap.ScanLine[0];
  if Frame.height > 1 then
    Stride := NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0])
  else
    Stride := ((Frame.width * 3 + 3) div 4) * 4;
  DstLinesize[0] := Integer(Stride);

  ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
    Frame.width, Frame.height, AV_PIX_FMT_BGR24, SWS_BILINEAR, nil, nil, nil);
  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');
  try
    if TFFmpegApi.sws_scale(ScaleContext, @Frame.data[0], @Frame.linesize[0], 0,
      Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
      raise Exception.Create('sws_scale failed.');
  finally
    TFFmpegApi.sws_freeContext(ScaleContext);
  end;
end;

end.
