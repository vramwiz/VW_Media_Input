unit FFmpegApi;

interface

uses
  Winapi.Windows, System.SysUtils;

type
  TAVMediaType = Integer;

  TAVRational = record
    num: Integer;
    den: Integer;
  end;

  PAVCodecParameters = ^TAVCodecParameters;
  PAVChannelLayout = ^TAVChannelLayout;
  TAVChannelLayout = record
    order: Integer;
    nb_channels: Integer;
    u: UInt64;
    opaque: Pointer;
  end;

  TAVCodecParameters = record
    codec_type: TAVMediaType;
    codec_id: Integer;
    codec_tag: Cardinal;
    extradata: PByte;
    extradata_size: Integer;
    coded_side_data: Pointer;
    nb_coded_side_data: Integer;
    format: Integer;
    bit_rate: Int64;
    bits_per_coded_sample: Integer;
    bits_per_raw_sample: Integer;
    profile: Integer;
    level: Integer;
    width: Integer;
    height: Integer;
    sample_aspect_ratio: TAVRational;
    framerate: TAVRational;
    field_order: Integer;
    color_range: Integer;
    color_primaries: Integer;
    color_trc: Integer;
    color_space: Integer;
    chroma_location: Integer;
    video_delay: Integer;
    ch_layout: TAVChannelLayout;
    sample_rate: Integer;
    block_align: Integer;
    frame_size: Integer;
    initial_padding: Integer;
    trailing_padding: Integer;
    seek_preroll: Integer;
  end;

  PAVStream = ^TAVStream;
  PPAVStream = ^PAVStream;
  TAVStream = record
    av_class: Pointer;
    index: Integer;
    id: Integer;
    codecpar: PAVCodecParameters;
    priv_data: Pointer;
    time_base: TAVRational;
    start_time: Int64;
    duration: Int64;
    nb_frames: Int64;
    disposition: Integer;
    discard: Integer;
    sample_aspect_ratio: TAVRational;
    metadata: Pointer;
    avg_frame_rate: TAVRational;
    attached_pic: array[0..103] of Byte;
    event_flags: Integer;
    r_frame_rate: TAVRational;
    pts_wrap_bits: Integer;
  end;

  PAVFormatContext = ^TAVFormatContext;
  PPAVFormatContext = ^PAVFormatContext;
  TAVFormatContext = record
    av_class: Pointer;
    iformat: Pointer;
    oformat: Pointer;
    priv_data: Pointer;
    pb: Pointer;
    ctx_flags: Integer;
    nb_streams: Cardinal;
    streams: PPAVStream;
    nb_stream_groups: Cardinal;
    stream_groups: Pointer;
    nb_chapters: Cardinal;
    chapters: Pointer;
    url: PAnsiChar;
    start_time: Int64;
    duration: Int64;
  end;

  PAVCodec = Pointer;
  PAVCodecContext = Pointer;
  PPAVCodecContext = ^PAVCodecContext;
  PSwsContext = Pointer;
  PSwrContext = Pointer;
  PPSwrContext = ^PSwrContext;

  PAVPacket = ^TAVPacket;
  PPAVPacket = ^PAVPacket;
  TAVPacket = record
    buf: Pointer;
    pts: Int64;
    dts: Int64;
    data: PByte;
    size: Integer;
    stream_index: Integer;
    flags: Integer;
    side_data: Pointer;
    side_data_elems: Integer;
    duration: Int64;
    pos: Int64;
    opaque: Pointer;
    opaque_ref: Pointer;
    time_base: TAVRational;
  end;

  PAVFrame = ^TAVFrame;
  PPAVFrame = ^PAVFrame;
  TAVFrame = record
    data: array[0..7] of PByte;
    linesize: array[0..7] of Integer;
    extended_data: Pointer;
    width: Integer;
    height: Integer;
    nb_samples: Integer;
    format: Integer;
    pict_type: Integer;
    sample_aspect_ratio: TAVRational;
    pts: Int64;
  end;

  Tavformat_open_input = function(ps: PPAVFormatContext; url: PAnsiChar; fmt: Pointer; options: Pointer): Integer; cdecl;
  Tavformat_find_stream_info = function(ic: PAVFormatContext; options: Pointer): Integer; cdecl;
  Tavformat_close_input = procedure(ps: PPAVFormatContext); cdecl;
  Tavformat_network_init = function: Integer; cdecl;
  Tav_find_best_stream = function(ic: PAVFormatContext; media_type: Integer; wanted_stream_nb: Integer; related_stream: Integer; decoder_ret: Pointer; flags: Integer): Integer; cdecl;
  Tav_read_frame = function(s: PAVFormatContext; pkt: PAVPacket): Integer; cdecl;
  Tav_seek_frame = function(s: PAVFormatContext; stream_index: Integer; timestamp: Int64; flags: Integer): Integer; cdecl;

  Tavcodec_find_decoder = function(id: Integer): PAVCodec; cdecl;
  Tavcodec_alloc_context3 = function(codec: PAVCodec): PAVCodecContext; cdecl;
  Tavcodec_parameters_to_context = function(codecContext: PAVCodecContext; codecpar: PAVCodecParameters): Integer; cdecl;
  Tavcodec_open2 = function(codecContext: PAVCodecContext; codec: PAVCodec; options: Pointer): Integer; cdecl;
  Tavcodec_free_context = procedure(codecContext: PPAVCodecContext); cdecl;
  Tavcodec_send_packet = function(codecContext: PAVCodecContext; packet: PAVPacket): Integer; cdecl;
  Tavcodec_receive_frame = function(codecContext: PAVCodecContext; frame: PAVFrame): Integer; cdecl;
  Tavcodec_flush_buffers = procedure(codecContext: PAVCodecContext); cdecl;
  Tav_packet_alloc = function: PAVPacket; cdecl;
  Tav_packet_free = procedure(packet: PPAVPacket); cdecl;
  Tav_packet_unref = procedure(packet: PAVPacket); cdecl;

  Tav_frame_alloc = function: PAVFrame; cdecl;
  Tav_frame_free = procedure(frame: PPAVFrame); cdecl;
  Tav_strerror = function(errnum: Integer; errbuf: PAnsiChar; errbuf_size: NativeUInt): Integer; cdecl;
  Tav_get_sample_fmt_name = function(sample_fmt: Integer): PAnsiChar; cdecl;

  Tsws_getContext = function(srcW, srcH, srcFormat, dstW, dstH, dstFormat, flags: Integer; srcFilter, dstFilter, param: Pointer): PSwsContext; cdecl;
  Tsws_scale = function(context: PSwsContext; srcSlice, srcStride: Pointer; srcSliceY, srcSliceH: Integer; dst, dstStride: Pointer): Integer; cdecl;
  Tsws_freeContext = procedure(context: PSwsContext); cdecl;

  Tav_channel_layout_default = procedure(ch_layout: PAVChannelLayout; nb_channels: Integer); cdecl;
  Tav_channel_layout_copy = function(dst: PAVChannelLayout; const src: PAVChannelLayout): Integer; cdecl;
  Tav_channel_layout_uninit = procedure(ch_layout: PAVChannelLayout); cdecl;

  Tswr_alloc_set_opts2 = function(ps: PPSwrContext; const out_ch_layout: PAVChannelLayout; out_sample_fmt: Integer; out_sample_rate: Integer;
    const in_ch_layout: PAVChannelLayout; in_sample_fmt: Integer; in_sample_rate: Integer; log_offset: Integer; log_ctx: Pointer): Integer; cdecl;
  Tswr_init = function(s: PSwrContext): Integer; cdecl;
  Tswr_convert = function(s: PSwrContext; out_arg: Pointer; out_count: Integer; in_arg: Pointer; in_count: Integer): Integer; cdecl;
  Tswr_free = procedure(s: PPSwrContext); cdecl;

const
  AVMEDIA_TYPE_VIDEO = 0;
  AVMEDIA_TYPE_AUDIO = 1;
  AV_TIME_BASE = 1000000;
  AVSEEK_FLAG_BACKWARD = 1;
  AV_PIX_FMT_BGR24 = 3;
  AV_PIX_FMT_BGRA = 28;
  SWS_BILINEAR = 2;
  AV_NOPTS_VALUE = -9223372036854775808;
  AV_SAMPLE_FMT_S16 = 1;
  AUDIO_OUTPUT_SAMPLE_RATE = 48000;
  AUDIO_OUTPUT_CHANNELS = 2;

type
  TFFmpegApi = class
  public
    class var FLoaded: Boolean; // FFmpeg DLLロード済みフラグ
    class var FAvUtil: HMODULE; // avutil DLLハンドル
    class var FAvCodec: HMODULE; // avcodec DLLハンドル
    class var FAvFormat: HMODULE; // avformat DLLハンドル
    class var FSwResample: HMODULE; // swresample DLLハンドル
    class var FSwScale: HMODULE; // swscale DLLハンドル
    class var avformat_open_input: Tavformat_open_input; // 入力ファイルを開く関数
    class var avformat_find_stream_info: Tavformat_find_stream_info; // ストリーム情報を読む関数
    class var avformat_close_input: Tavformat_close_input; // 入力コンテキストを閉じる関数
    class var avformat_network_init: Tavformat_network_init; // FFmpegネットワーク機能初期化関数
    class var av_find_best_stream: Tav_find_best_stream; // 最適な映像ストリームを探す関数
    class var av_read_frame: Tav_read_frame; // 次のパケットを読む関数
    class var av_seek_frame: Tav_seek_frame; // 指定位置へシークする関数
    class var avcodec_find_decoder: Tavcodec_find_decoder; // コーデックIDからデコーダを探す関数
    class var avcodec_alloc_context3: Tavcodec_alloc_context3; // デコードコンテキストを確保する関数
    class var avcodec_parameters_to_context: Tavcodec_parameters_to_context; // ストリーム情報をデコードコンテキストへコピーする関数
    class var avcodec_open2: Tavcodec_open2; // デコーダを開く関数
    class var avcodec_free_context: Tavcodec_free_context; // デコードコンテキストを解放する関数
    class var avcodec_send_packet: Tavcodec_send_packet; // パケットをデコーダへ渡す関数
    class var avcodec_receive_frame: Tavcodec_receive_frame; // デコード済みフレームを受け取る関数
    class var avcodec_flush_buffers: Tavcodec_flush_buffers; // シーク後にデコーダ内部バッファを捨てる関数
    class var av_packet_alloc: Tav_packet_alloc; // AVPacketを確保する関数
    class var av_packet_free: Tav_packet_free; // AVPacketを解放する関数
    class var av_packet_unref: Tav_packet_unref; // AVPacketの参照を解放する関数
    class var av_frame_alloc: Tav_frame_alloc; // AVFrameを確保する関数
    class var av_frame_free: Tav_frame_free; // AVFrameを解放する関数
    class var av_strerror: Tav_strerror; // FFmpegエラーコードを文字列化する関数
    class var av_get_sample_fmt_name: Tav_get_sample_fmt_name; // サンプル形式名を取得する関数
    class var av_channel_layout_default: Tav_channel_layout_default; // 標準チャンネルレイアウトを作る関数
    class var av_channel_layout_copy: Tav_channel_layout_copy; // チャンネルレイアウトをコピーする関数
    class var av_channel_layout_uninit: Tav_channel_layout_uninit; // チャンネルレイアウトを解放する関数
    class var sws_getContext: Tsws_getContext; // 色変換コンテキストを作る関数
    class var sws_scale: Tsws_scale; // フレームをBGRへ変換する関数
    class var sws_freeContext: Tsws_freeContext; // 色変換コンテキストを解放する関数
    class var swr_alloc_set_opts2: Tswr_alloc_set_opts2; // 音声変換コンテキストを作る関数
    class var swr_init: Tswr_init; // 音声変換コンテキストを初期化する関数
    class var swr_convert: Tswr_convert; // 音声フレームをPCMへ変換する関数
    class var swr_free: Tswr_free; // 音声変換コンテキストを解放する関数
    // この入力プラグインが置かれているフォルダを取得する
    class function ModuleDirectory: string; static;
    // 指定DLLを実行ファイルフォルダからロードする
    class function LoadDll(const DllPath, DllName: string): HMODULE; static;
    // DLLから指定関数を取得する
    class function LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer; static;
    // 必要なFFmpeg DLLと関数ポインタを初期化する
    class procedure EnsureLoaded; static;
    // FFmpegエラーコードを表示用文字列に変換する
    class function ErrorText(Code: Integer): string; static;
  end;
function RationalToDouble(const Value: TAVRational): Double;
function RationalToText(const Value: TAVRational): string;
function StreamAt(FormatContext: PAVFormatContext; StreamIndex: Integer): PAVStream;
function StreamTimestampFromMs(Stream: PAVStream; PositionMs: Integer): Int64;
function StreamTimestampToMs(Stream: PAVStream; Timestamp: Int64): Integer;
function SampleFormatName(SampleFormat: Integer): string;
implementation

class function TFFmpegApi.ModuleDirectory: string;
var
  ModuleFileName: array[0..MAX_PATH - 1] of Char;
  Len: DWORD;
begin
  Len := GetModuleFileName(HInstance, ModuleFileName, Length(ModuleFileName));
  if Len > 0 then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(string(ModuleFileName)))
  else
    Result := ExtractFilePath(ParamStr(0));
end;

// 指定DLLを実行ファイルフォルダからロードする
class function TFFmpegApi.LoadDll(const DllPath, DllName: string): HMODULE;
var
  FullName: string;
  ErrorCode: Cardinal;
begin
  FullName := DllPath + DllName;
  Result := LoadLibrary(PChar(FullName));
  if Result = 0 then
  begin
    ErrorCode := GetLastError;
    raise Exception.CreateFmt('Failed to load %s. Path=%s WindowsError=%d %s',
      [DllName, FullName, ErrorCode, SysErrorMessage(ErrorCode)]);
  end;
end;

// DLLから指定関数を取得する
class function TFFmpegApi.LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer;
begin
  Result := GetProcAddress(Module, ProcName);
  if Result = nil then
    raise Exception.CreateFmt('FFmpeg function not found: %s', [string(ProcName)]);
end;

// 必要なFFmpeg DLLと関数ポインタを初期化する
class procedure TFFmpegApi.EnsureLoaded;
var
  DllPath: string;
begin
  if FLoaded then
    Exit;

  DllPath := ModuleDirectory;
  SetDllDirectory(PChar(DllPath));

  FAvUtil := LoadDll(DllPath, 'avutil-60.dll');
  FSwResample := LoadDll(DllPath, 'swresample-6.dll');
  FSwScale := LoadDll(DllPath, 'swscale-9.dll');
  FAvCodec := LoadDll(DllPath, 'avcodec-62.dll');
  FAvFormat := LoadDll(DllPath, 'avformat-62.dll');

  av_strerror := Tav_strerror(LoadProc(FAvUtil, 'av_strerror'));
  av_get_sample_fmt_name := Tav_get_sample_fmt_name(LoadProc(FAvUtil, 'av_get_sample_fmt_name'));
  av_frame_alloc := Tav_frame_alloc(LoadProc(FAvUtil, 'av_frame_alloc'));
  av_frame_free := Tav_frame_free(LoadProc(FAvUtil, 'av_frame_free'));
  av_channel_layout_default := Tav_channel_layout_default(LoadProc(FAvUtil, 'av_channel_layout_default'));
  av_channel_layout_copy := Tav_channel_layout_copy(LoadProc(FAvUtil, 'av_channel_layout_copy'));
  av_channel_layout_uninit := Tav_channel_layout_uninit(LoadProc(FAvUtil, 'av_channel_layout_uninit'));

  avformat_open_input := Tavformat_open_input(LoadProc(FAvFormat, 'avformat_open_input'));
  avformat_find_stream_info := Tavformat_find_stream_info(LoadProc(FAvFormat, 'avformat_find_stream_info'));
  avformat_close_input := Tavformat_close_input(LoadProc(FAvFormat, 'avformat_close_input'));
  avformat_network_init := Tavformat_network_init(LoadProc(FAvFormat, 'avformat_network_init'));
  av_find_best_stream := Tav_find_best_stream(LoadProc(FAvFormat, 'av_find_best_stream'));
  av_read_frame := Tav_read_frame(LoadProc(FAvFormat, 'av_read_frame'));
  av_seek_frame := Tav_seek_frame(LoadProc(FAvFormat, 'av_seek_frame'));

  avcodec_find_decoder := Tavcodec_find_decoder(LoadProc(FAvCodec, 'avcodec_find_decoder'));
  avcodec_alloc_context3 := Tavcodec_alloc_context3(LoadProc(FAvCodec, 'avcodec_alloc_context3'));
  avcodec_parameters_to_context := Tavcodec_parameters_to_context(LoadProc(FAvCodec, 'avcodec_parameters_to_context'));
  avcodec_open2 := Tavcodec_open2(LoadProc(FAvCodec, 'avcodec_open2'));
  avcodec_free_context := Tavcodec_free_context(LoadProc(FAvCodec, 'avcodec_free_context'));
  avcodec_send_packet := Tavcodec_send_packet(LoadProc(FAvCodec, 'avcodec_send_packet'));
  avcodec_receive_frame := Tavcodec_receive_frame(LoadProc(FAvCodec, 'avcodec_receive_frame'));
  avcodec_flush_buffers := Tavcodec_flush_buffers(LoadProc(FAvCodec, 'avcodec_flush_buffers'));
  av_packet_alloc := Tav_packet_alloc(LoadProc(FAvCodec, 'av_packet_alloc'));
  av_packet_free := Tav_packet_free(LoadProc(FAvCodec, 'av_packet_free'));
  av_packet_unref := Tav_packet_unref(LoadProc(FAvCodec, 'av_packet_unref'));

  sws_getContext := Tsws_getContext(LoadProc(FSwScale, 'sws_getContext'));
  sws_scale := Tsws_scale(LoadProc(FSwScale, 'sws_scale'));
  sws_freeContext := Tsws_freeContext(LoadProc(FSwScale, 'sws_freeContext'));

  swr_alloc_set_opts2 := Tswr_alloc_set_opts2(LoadProc(FSwResample, 'swr_alloc_set_opts2'));
  swr_init := Tswr_init(LoadProc(FSwResample, 'swr_init'));
  swr_convert := Tswr_convert(LoadProc(FSwResample, 'swr_convert'));
  swr_free := Tswr_free(LoadProc(FSwResample, 'swr_free'));

  avformat_network_init;
  FLoaded := True;
end;

// FFmpegエラーコードを表示用文字列に変換する
class function TFFmpegApi.ErrorText(Code: Integer): string;
var
  Buffer: array[0..255] of AnsiChar;
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  if Assigned(av_strerror) and (av_strerror(Code, Buffer, SizeOf(Buffer)) = 0) then
    Result := string(AnsiString(Buffer))
  else
    Result := Format('FFmpeg error %d', [Code]);
end;

// FFmpegの分数値を実数に変換する
function RationalToDouble(const Value: TAVRational): Double;
begin
  if Value.den = 0 then
    Result := 0
  else
    Result := Value.num / Value.den;
end;

// FFmpegの分数値を文字列に変換する
function RationalToText(const Value: TAVRational): string;
begin
  if Value.den = 0 then
    Result := ''
  else
    Result := Format('%d/%d', [Value.num, Value.den]);
end;

// フォーマットコンテキストから指定ストリームを取り出す
function StreamAt(FormatContext: PAVFormatContext; StreamIndex: Integer): PAVStream;
begin
  Result := PAVStream(PPointer(NativeUInt(FormatContext.streams) + NativeUInt(StreamIndex) * SizeOf(Pointer))^);
end;

// ミリ秒位置をストリーム時間軸のPTSへ変換する
function StreamTimestampFromMs(Stream: PAVStream; PositionMs: Integer): Int64;
begin
  if (Stream.time_base.num <= 0) or (Stream.time_base.den <= 0) then
    Result := 0
  else
    Result := Round((PositionMs / 1000.0) * Stream.time_base.den / Stream.time_base.num);
end;

// ストリーム時間軸のPTSをミリ秒位置へ変換する
function StreamTimestampToMs(Stream: PAVStream; Timestamp: Int64): Integer;
begin
  if (Timestamp = AV_NOPTS_VALUE) or (Stream.time_base.num <= 0) or (Stream.time_base.den <= 0) then
    Result := -1
  else
    Result := Round(Timestamp * 1000.0 * Stream.time_base.num / Stream.time_base.den);
end;

// FFmpegのサンプル形式番号を表示用文字列に変換する
function SampleFormatName(SampleFormat: Integer): string;
var
  Name: PAnsiChar;
begin
  Result := Format('fmt %d', [SampleFormat]);
  if Assigned(TFFmpegApi.av_get_sample_fmt_name) then
  begin
    Name := TFFmpegApi.av_get_sample_fmt_name(SampleFormat);
    if Name <> nil then
      Result := string(AnsiString(Name));
  end;
end;

end.
