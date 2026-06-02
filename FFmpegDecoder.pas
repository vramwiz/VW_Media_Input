unit FFmpegDecoder;

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.SysUtils, System.Generics.Collections,
  System.Diagnostics, System.Math, Vcl.Graphics;

type
  PAudioWaveBuffer = ^TAudioWaveBuffer;
  TAudioWaveBuffer = record
    Header: TWaveHdr;
    Data: Pointer;
    Size: Integer;
  end;

  TAudioPlaybackStats = record
    AudioPackets: Int64; // 読み込んだ音声パケット数
    DecodedFrames: Int64; // デコード済み音声フレーム数
    DecodedSamples: Int64; // デコード済みサンプル数
    LastPtsMs: Integer; // 最後に読んだ音声PTS
    Peak: Integer; // 16bit PCMの最大振幅
    Rms: Double; // 16bit PCMのRMS値
    NonZeroPercent: Double; // 0以外のサンプル割合
    QueuedBuffers: Integer; // waveOutに渡して未完了のバッファ数
    SendErrors: Int64; // avcodec_send_packetの失敗回数
    ConvertErrors: Int64; // swr_convertの失敗回数
  end;

  TDecodeLoadStats = record
    VideoLastMs: Double; // 直近の映像デコード+色変換時間
    VideoAverageMs: Double; // 映像デコード+色変換時間の移動平均
    VideoMaxMs: Double; // 映像デコード+色変換時間の最大値
    VideoFrames: Int64; // 測定した映像フレーム数
    AudioLastMs: Double; // 直近の音声パケット処理時間
    AudioAverageMs: Double; // 音声パケット処理時間の移動平均
    AudioMaxMs: Double; // 音声パケット処理時間の最大値
    AudioPackets: Int64; // 測定した音声パケット数
  end;

  TAudioInfo = record
    Present: Boolean; // 音声ストリームが見つかったか
    StreamIndex: Integer; // 対象の音声ストリーム番号
    SampleRate: Integer; // サンプルレート
    Channels: Integer; // チャンネル数
    SampleFormat: Integer; // FFmpegのサンプル形式番号
    SampleFormatName: string; // FFmpegのサンプル形式名
    DurationSec: Double; // 音声ストリームの長さ
    OpenError: string; // 音声デコーダ準備時の診断メッセージ
  end;

  TVideoInfo = record
    Width: Integer; // 動画の幅
    Height: Integer; // 動画の高さ
    DurationSec: Double; // 動画の長さを秒で保持する
    FpsText: string; // FFmpegから読んだfpsの分数表記
    Fps: Double; // 再生タイマー用のfps実数値
    Audio: TAudioInfo; // 音声ストリームの基本情報
  end;

  EFFmpegDecoder = class(Exception);

  TFFmpegDecoder = class
  private
    FFileName: string; // 現在開いている動画ファイル名
    FFormatContext: Pointer; // avformatで開いた入力コンテキスト
    FCodecContext: Pointer; // avcodecで開いたデコードコンテキスト
    FStream: Pointer; // 対象の映像ストリーム
    FStreamIndex: Integer; // 対象の映像ストリーム番号
    FAudioCodecContext: Pointer; // 音声用デコードコンテキスト
    FAudioStream: Pointer; // 対象の音声ストリーム
    FAudioStreamIndex: Integer; // 対象の音声ストリーム番号
    FAudioFrame: Pointer; // 音声デコードに再利用するAVFrame
    FSwrContext: Pointer; // PCM変換用swresampleコンテキスト
    FWaveOut: HWAVEOUT; // デバッグ用音声出力
    FAudioPlaybackActive: Boolean; // 音声出力中かどうか
    FAudioBuffers: TList<PAudioWaveBuffer>; // waveOut完了待ちのPCMバッファ
    FAudioStats: TAudioPlaybackStats; // 音声デコード確認用の数値
    FDecodeStats: TDecodeLoadStats; // デコード負荷確認用の数値
    FPacket: Pointer; // 読み込みに再利用するAVPacket
    FFrame: Pointer; // デコードに再利用するAVFrame
    FInfo: TVideoInfo; // 現在開いている動画の基本情報
    // 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
    procedure DecodeAudioPacket(Packet: Pointer);
    // waveOutで再生完了したPCMバッファを解放する
    procedure CleanupAudioBuffers;
    // PCMバッファをwaveOutへ渡す
    procedure QueueAudioPcm(const Pcm: TBytes);
    // PCMバッファから音量確認用の統計を更新する
    procedure UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
    // 映像デコード負荷の統計を更新する
    procedure UpdateVideoLoadStats(ElapsedMs: Double);
    // 音声デコード負荷の統計を更新する
    procedure UpdateAudioLoadStats(ElapsedMs: Double);
  public
    // デコーダインスタンスを初期化する
    constructor Create;
    // 開いている動画を閉じてインスタンスを破棄する
    destructor Destroy; override;
    // 保持しているFFmpegリソースを解放する
    procedure Close;
    // 動画を開いてデコード可能な状態にする
    function Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
    function DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload;
    // 現在位置から次の映像フレームを順方向デコードする
    function DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を開始する
    function StartAudioPlayback(out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を停止する
    procedure StopAudioPlayback;
    // 一時デコーダで動画情報だけを読む
    class function ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean; static;
    // 一時デコーダで指定位置のフレームだけを読む
    class function DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload; static;
    property Info: TVideoInfo read FInfo;
    property AudioStats: TAudioPlaybackStats read FAudioStats;
    property DecodeStats: TDecodeLoadStats read FDecodeStats;
    property FileName: string read FFileName;
  end;

implementation

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
  SWS_BILINEAR = 2;
  AV_NOPTS_VALUE = -9223372036854775808;
  AV_SAMPLE_FMT_S16 = 1;
  AUDIO_OUTPUT_SAMPLE_RATE = 48000;
  AUDIO_OUTPUT_CHANNELS = 2;

type
  TFFmpegApi = class
  private
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
    // 指定DLLを実行ファイルフォルダからロードする
    class function LoadDll(const DllPath, DllName: string): HMODULE; static;
    // DLLから指定関数を取得する
    class function LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer; static;
  public
    // 必要なFFmpeg DLLと関数ポインタを初期化する
    class procedure EnsureLoaded; static;
    // FFmpegエラーコードを表示用文字列に変換する
    class function ErrorText(Code: Integer): string; static;
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
    raise EFFmpegDecoder.CreateFmt('Failed to load %s. Path=%s WindowsError=%d %s',
      [DllName, FullName, ErrorCode, SysErrorMessage(ErrorCode)]);
  end;
end;

// DLLから指定関数を取得する
class function TFFmpegApi.LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer;
begin
  Result := GetProcAddress(Module, ProcName);
  if Result = nil then
    raise EFFmpegDecoder.CreateFmt('FFmpeg function not found: %s', [string(ProcName)]);
end;

// 必要なFFmpeg DLLと関数ポインタを初期化する
class procedure TFFmpegApi.EnsureLoaded;
var
  DllPath: string;
begin
  if FLoaded then
    Exit;

  DllPath := ExtractFilePath(ParamStr(0));
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

// AVFrameをBGRのTBitmapへ変換する
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);
var
  ScaleContext: PSwsContext;
  DstData: array[0..3] of PByte;
  DstLinesize: array[0..3] of Integer;
  Stride: NativeInt;
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise EFFmpegDecoder.Create('Decoded frame has invalid size.');

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
    raise EFFmpegDecoder.Create('sws_getContext failed.');
  try
    if TFFmpegApi.sws_scale(ScaleContext, @Frame.data[0], @Frame.linesize[0], 0,
      Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
      raise EFFmpegDecoder.Create('sws_scale failed.');
  finally
    TFFmpegApi.sws_freeContext(ScaleContext);
  end;
end;

// デコーダインスタンスを初期化する
constructor TFFmpegDecoder.Create;
begin
  inherited Create;
  FStreamIndex := -1;
  FAudioStreamIndex := -1;
  FWaveOut := 0;
  FAudioBuffers := TList<PAudioWaveBuffer>.Create;
end;

// 開いている動画を閉じてインスタンスを破棄する
destructor TFFmpegDecoder.Destroy;
begin
  Close;
  FAudioBuffers.Free;
  inherited Destroy;
end;

// 保持しているFFmpegリソースを解放する
procedure TFFmpegDecoder.Close;
var
  CodecContext: PAVCodecContext;
  AudioCodecContext: PAVCodecContext;
  FormatContext: PAVFormatContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
begin
  StopAudioPlayback;

  Packet := PAVPacket(FPacket);
  if Assigned(Packet) then
  begin
    TFFmpegApi.av_packet_free(@Packet);
    FPacket := nil;
  end;

  Frame := PAVFrame(FFrame);
  if Assigned(Frame) then
  begin
    TFFmpegApi.av_frame_free(@Frame);
    FFrame := nil;
  end;

  AudioFrame := PAVFrame(FAudioFrame);
  if Assigned(AudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@AudioFrame);
    FAudioFrame := nil;
  end;

  SwrContext := PSwrContext(FSwrContext);
  if Assigned(SwrContext) then
  begin
    TFFmpegApi.swr_free(@SwrContext);
    FSwrContext := nil;
  end;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  if Assigned(AudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
    FAudioCodecContext := nil;
  end;

  CodecContext := PAVCodecContext(FCodecContext);
  if Assigned(CodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@CodecContext);
    FCodecContext := nil;
  end;

  FormatContext := PAVFormatContext(FFormatContext);
  if Assigned(FormatContext) then
  begin
    TFFmpegApi.avformat_close_input(@FormatContext);
    FFormatContext := nil;
  end;

  FFileName := '';
  FStream := nil;
  FStreamIndex := -1;
  FAudioStream := nil;
  FAudioStreamIndex := -1;
  FillChar(FInfo, SizeOf(FInfo), 0);
  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FillChar(FDecodeStats, SizeOf(FDecodeStats), 0);
  FAudioStats.LastPtsMs := -1;
end;

// 映像デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateVideoLoadStats(ElapsedMs: Double);
begin
  FDecodeStats.VideoLastMs := ElapsedMs;
  if FDecodeStats.VideoFrames = 0 then
    FDecodeStats.VideoAverageMs := ElapsedMs
  else
    FDecodeStats.VideoAverageMs := (FDecodeStats.VideoAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > FDecodeStats.VideoMaxMs then
    FDecodeStats.VideoMaxMs := ElapsedMs;
  Inc(FDecodeStats.VideoFrames);
end;

// 音声デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateAudioLoadStats(ElapsedMs: Double);
begin
  FDecodeStats.AudioLastMs := ElapsedMs;
  if FDecodeStats.AudioPackets = 0 then
    FDecodeStats.AudioAverageMs := ElapsedMs
  else
    FDecodeStats.AudioAverageMs := (FDecodeStats.AudioAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > FDecodeStats.AudioMaxMs then
    FDecodeStats.AudioMaxMs := ElapsedMs;
  Inc(FDecodeStats.AudioPackets);
end;

// デバッグ用の音声再生を開始する
function TFFmpegDecoder.StartAudioPlayback(out ErrorMessage: string): Boolean;
var
  WaveFormat: TWaveFormatEx;
  Ret: MMRESULT;
begin
  ErrorMessage := '';
  Result := False;

  StopAudioPlayback;

  if (not FInfo.Audio.Present) or (FAudioCodecContext = nil) or (FAudioStream = nil) or (FSwrContext = nil) then
  begin
    ErrorMessage := Format('Audio decoder is not open. present=%s codec=%s stream=%s swr=%s %s',
      [BoolToStr(FInfo.Audio.Present, True),
       BoolToStr(FAudioCodecContext <> nil, True),
       BoolToStr(FAudioStream <> nil, True),
       BoolToStr(FSwrContext <> nil, True),
       FInfo.Audio.OpenError]);
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := AUDIO_OUTPUT_CHANNELS;
  WaveFormat.nSamplesPerSec := AUDIO_OUTPUT_SAMPLE_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := WaveFormat.nChannels * WaveFormat.wBitsPerSample div 8;
  WaveFormat.nAvgBytesPerSec := WaveFormat.nSamplesPerSec * WaveFormat.nBlockAlign;

  Ret := waveOutOpen(@FWaveOut, WAVE_MAPPER, @WaveFormat, 0, 0, CALLBACK_NULL);
  if Ret <> MMSYSERR_NOERROR then
  begin
    FWaveOut := 0;
    ErrorMessage := Format('waveOutOpen failed: %d', [Ret]);
    Exit;
  end;

  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FAudioStats.LastPtsMs := -1;
  FAudioPlaybackActive := True;
  Result := True;
end;

// デバッグ用の音声再生を停止する
procedure TFFmpegDecoder.StopAudioPlayback;
var
  Buffer: PAudioWaveBuffer;
begin
  FAudioPlaybackActive := False;

  if FWaveOut <> 0 then
    waveOutReset(FWaveOut);

  if FAudioBuffers <> nil then
  begin
    while FAudioBuffers.Count > 0 do
    begin
      Buffer := FAudioBuffers[FAudioBuffers.Count - 1];
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(FAudioBuffers.Count - 1);
    end;
  end;

  if FWaveOut <> 0 then
  begin
    waveOutClose(FWaveOut);
    FWaveOut := 0;
  end;

  FAudioStats.QueuedBuffers := 0;
end;

// 動画を開いてデコード可能な状態にする
function TFFmpegDecoder.Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  AudioCodecContext: PAVCodecContext;
  Codec: PAVCodec;
  AudioCodec: PAVCodec;
  Packet: PAVPacket;
  Frame: PAVFrame;
  AudioFrame: PAVFrame;
  SwrContext: PSwrContext;
  Utf8FileName: UTF8String;
  Ret: Integer;
  StreamIndex: Integer;
  AudioStreamIndex: Integer;
  Stream: PAVStream;
  AudioStream: PAVStream;
  CodecPar: PAVCodecParameters;
  AudioCodecPar: PAVCodecParameters;
  InLayout: TAVChannelLayout;
  OutLayout: TAVChannelLayout;
  SwrRet: Integer;
begin
  Close;
  FillChar(Info, SizeOf(Info), 0);
  ErrorMessage := '';
  Result := False;
  FormatContext := nil;
  CodecContext := nil;
  AudioCodecContext := nil;
  Packet := nil;
  Frame := nil;
  AudioFrame := nil;
  SwrContext := nil;
  AudioStream := nil;
  AudioStreamIndex := -1;
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);

  try
    TFFmpegApi.EnsureLoaded;

    Utf8FileName := UTF8String(FileName);
    Ret := TFFmpegApi.avformat_open_input(@FormatContext, PAnsiChar(Utf8FileName), nil, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avformat_find_stream_info(FormatContext, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0);
    if StreamIndex < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(StreamIndex);
      Exit;
    end;

    Stream := StreamAt(FormatContext, StreamIndex);
    if not Assigned(Stream) then
    begin
      ErrorMessage := 'Video stream pointer is nil.';
      Exit;
    end;

    CodecPar := Stream.codecpar;
    if not Assigned(CodecPar) then
    begin
      ErrorMessage := 'Codec parameters pointer is nil.';
      Exit;
    end;

    Codec := TFFmpegApi.avcodec_find_decoder(CodecPar.codec_id);
    if not Assigned(Codec) then
    begin
      ErrorMessage := 'Decoder was not found.';
      Exit;
    end;

    CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
    if not Assigned(CodecContext) then
    begin
      ErrorMessage := 'avcodec_alloc_context3 failed.';
      Exit;
    end;

    Ret := TFFmpegApi.avcodec_parameters_to_context(CodecContext, CodecPar);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Packet := TFFmpegApi.av_packet_alloc();
    Frame := TFFmpegApi.av_frame_alloc();
    if (Packet = nil) or (Frame = nil) then
    begin
      ErrorMessage := 'Failed to allocate packet or frame.';
      Exit;
    end;

    if FormatContext.duration > 0 then
      Info.DurationSec := FormatContext.duration / AV_TIME_BASE;
    Info.Width := CodecPar.width;
    Info.Height := CodecPar.height;
    Info.FpsText := RationalToText(Stream.avg_frame_rate);
    Info.Fps := RationalToDouble(Stream.avg_frame_rate);
    ReadAudioInfo(FormatContext, Info);

    if (Info.Width <= 0) or (Info.Height <= 0) then
    begin
      ErrorMessage := 'Video stream was found, but size could not be read.';
      Exit;
    end;

    if Info.Audio.Present then
    begin
      AudioStreamIndex := Info.Audio.StreamIndex;
      AudioStream := StreamAt(FormatContext, AudioStreamIndex);
      if not Assigned(AudioStream) then
        Info.Audio.OpenError := 'Audio stream pointer is nil.'
      else if not Assigned(AudioStream.codecpar) then
        Info.Audio.OpenError := 'Audio codec parameters pointer is nil.'
      else
      begin
        AudioCodecPar := AudioStream.codecpar;
        AudioCodec := TFFmpegApi.avcodec_find_decoder(AudioCodecPar.codec_id);
        if not Assigned(AudioCodec) then
          Info.Audio.OpenError := Format('Audio decoder was not found. codec_id=%d', [AudioCodecPar.codec_id])
        else
        begin
          AudioCodecContext := TFFmpegApi.avcodec_alloc_context3(AudioCodec);
          if not Assigned(AudioCodecContext) then
            Info.Audio.OpenError := 'Audio avcodec_alloc_context3 failed.'
          else
          begin
            Ret := TFFmpegApi.avcodec_parameters_to_context(AudioCodecContext, AudioCodecPar);
            if Ret < 0 then
              Info.Audio.OpenError := 'Audio avcodec_parameters_to_context failed: ' + TFFmpegApi.ErrorText(Ret)
            else
            begin
              Ret := TFFmpegApi.avcodec_open2(AudioCodecContext, AudioCodec, nil);
              if Ret < 0 then
                Info.Audio.OpenError := 'Audio avcodec_open2 failed: ' + TFFmpegApi.ErrorText(Ret)
              else
              begin
                AudioFrame := TFFmpegApi.av_frame_alloc();
                if not Assigned(AudioFrame) then
                  Info.Audio.OpenError := 'Audio av_frame_alloc failed.'
                else
                begin
                  if AudioCodecPar.ch_layout.nb_channels > 0 then
                    Ret := TFFmpegApi.av_channel_layout_copy(@InLayout, @AudioCodecPar.ch_layout)
                  else
                  begin
                    TFFmpegApi.av_channel_layout_default(@InLayout, AUDIO_OUTPUT_CHANNELS);
                    Ret := 0;
                  end;

                  if Ret < 0 then
                    Info.Audio.OpenError := 'av_channel_layout_copy failed: ' + TFFmpegApi.ErrorText(Ret)
                  else
                  begin
                    TFFmpegApi.av_channel_layout_default(@OutLayout, AUDIO_OUTPUT_CHANNELS);
                    SwrRet := TFFmpegApi.swr_alloc_set_opts2(@SwrContext, @OutLayout, AV_SAMPLE_FMT_S16,
                      AUDIO_OUTPUT_SAMPLE_RATE, @InLayout, AudioCodecPar.format, AudioCodecPar.sample_rate, 0, nil);
                    if (SwrRet < 0) or not Assigned(SwrContext) then
                    begin
                      Info.Audio.OpenError := Format('swr_alloc_set_opts2 failed: %s rate=%d fmt=%d channels=%d',
                        [TFFmpegApi.ErrorText(SwrRet), AudioCodecPar.sample_rate, AudioCodecPar.format,
                         AudioCodecPar.ch_layout.nb_channels]);
                    end
                    else if TFFmpegApi.swr_init(SwrContext) < 0 then
                    begin
                      TFFmpegApi.swr_free(@SwrContext);
                      SwrContext := nil;
                      Info.Audio.OpenError := Format('swr_init failed. rate=%d fmt=%d channels=%d',
                        [AudioCodecPar.sample_rate, AudioCodecPar.format, AudioCodecPar.ch_layout.nb_channels]);
                    end;
                  end;
                end;
              end;
            end;
          end;
        end;
      end;
    end;

    FFileName := FileName;
    FFormatContext := FormatContext;
    FCodecContext := CodecContext;
    FStream := Stream;
    FStreamIndex := StreamIndex;
    FAudioCodecContext := AudioCodecContext;
    FAudioStream := AudioStream;
    FAudioStreamIndex := AudioStreamIndex;
    FAudioFrame := AudioFrame;
    FSwrContext := SwrContext;
    FPacket := Packet;
    FFrame := Frame;
    FInfo := Info;

    FormatContext := nil;
    CodecContext := nil;
    AudioCodecContext := nil;
    Packet := nil;
    Frame := nil;
    AudioFrame := nil;
    SwrContext := nil;
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;

  if Assigned(Frame) then
    TFFmpegApi.av_frame_free(@Frame);
  if Assigned(Packet) then
    TFFmpegApi.av_packet_free(@Packet);
  if Assigned(SwrContext) then
    TFFmpegApi.swr_free(@SwrContext);
  if Assigned(AudioFrame) then
    TFFmpegApi.av_frame_free(@AudioFrame);
  if Assigned(AudioCodecContext) then
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
  if Assigned(CodecContext) then
    TFFmpegApi.avcodec_free_context(@CodecContext);
  if Assigned(FormatContext) then
    TFFmpegApi.avformat_close_input(@FormatContext);
end;

// 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
function TFFmpegDecoder.DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  TargetTs: Int64;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            // 純粋な映像デコード負荷の切り分け用。BGR変換とTBitmap書き込みを止める。
            // CopyFrameToBitmap(Frame, Bitmap);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードする
function TFFmpegDecoder.DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  Stopwatch: TStopwatch;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          DecodeAudioPacket(Packet);
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          // 純粋な映像デコード負荷の切り分け用。BGR変換とTBitmap書き込みを止める。
          // CopyFrameToBitmap(Frame, Bitmap);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// waveOutで再生完了したPCMバッファを解放する
procedure TFFmpegDecoder.CleanupAudioBuffers;
var
  I: Integer;
  Buffer: PAudioWaveBuffer;
begin
  if FAudioBuffers = nil then
    Exit;

  for I := FAudioBuffers.Count - 1 downto 0 do
  begin
    Buffer := FAudioBuffers[I];
    if (FWaveOut = 0) or ((Buffer.Header.dwFlags and WHDR_DONE) <> 0) then
    begin
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(I);
    end;
  end;

  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファをwaveOutへ渡す
procedure TFFmpegDecoder.QueueAudioPcm(const Pcm: TBytes);
var
  Buffer: PAudioWaveBuffer;
begin
  if (not FAudioPlaybackActive) or (FWaveOut = 0) or (Length(Pcm) = 0) then
    Exit;

  CleanupAudioBuffers;

  New(Buffer);
  FillChar(Buffer^, SizeOf(Buffer^), 0);
  Buffer.Size := Length(Pcm);
  GetMem(Buffer.Data, Buffer.Size);
  Move(Pcm[0], Buffer.Data^, Buffer.Size);
  Buffer.Header.lpData := PAnsiChar(Buffer.Data);
  Buffer.Header.dwBufferLength := Buffer.Size;

  if waveOutPrepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  if waveOutWrite(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  FAudioBuffers.Add(Buffer);
  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファから音量確認用の統計を更新する
procedure TFFmpegDecoder.UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
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

  Inc(FAudioStats.DecodedFrames);
  Inc(FAudioStats.DecodedSamples, SampleCount);
  FAudioStats.LastPtsMs := PtsMs;
  FAudioStats.Peak := Peak;
  FAudioStats.Rms := Sqrt(SumSquares / TotalValues);
  FAudioStats.NonZeroPercent := NonZero * 100.0 / TotalValues;
  if FAudioBuffers <> nil then
    FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
procedure TFFmpegDecoder.DecodeAudioPacket(Packet: Pointer);
var
  AudioCodecContext: PAVCodecContext;
  AudioFrame: PAVFrame;
  AudioStream: PAVStream;
  Ret: Integer;
  OutData: array[0..0] of PByte;
  OutSamples: Integer;
  ConvertedSamples: Integer;
  Pcm: TBytes;
  PtsMs: Integer;
  Stopwatch: TStopwatch;
begin
  if (not FAudioPlaybackActive) or (Packet = nil) then
    Exit;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  AudioFrame := PAVFrame(FAudioFrame);
  AudioStream := PAVStream(FAudioStream);
  if (AudioCodecContext = nil) or (AudioFrame = nil) or (AudioStream = nil) or (FSwrContext = nil) then
    Exit;

  Stopwatch := TStopwatch.StartNew;
  try
    Inc(FAudioStats.AudioPackets);
    Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, PAVPacket(Packet));
    if Ret < 0 then
    begin
      Inc(FAudioStats.SendErrors);
      Exit;
    end;

    while TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0 do
    begin
      if FInfo.Audio.SampleRate > 0 then
        OutSamples := Ceil(AudioFrame.nb_samples * AUDIO_OUTPUT_SAMPLE_RATE / FInfo.Audio.SampleRate) + 256
      else
        OutSamples := AudioFrame.nb_samples + 256;

      SetLength(Pcm, OutSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
      OutData[0] := @Pcm[0];
      ConvertedSamples := TFFmpegApi.swr_convert(PSwrContext(FSwrContext), @OutData[0], OutSamples,
        @AudioFrame.data[0], AudioFrame.nb_samples);
      if ConvertedSamples <= 0 then
      begin
        Inc(FAudioStats.ConvertErrors);
        Continue;
      end;

      SetLength(Pcm, ConvertedSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
      PtsMs := StreamTimestampToMs(AudioStream, AudioFrame.pts);
      UpdateAudioStats(Pcm, ConvertedSamples, PtsMs);
      QueueAudioPcm(Pcm);
    end;
  finally
    Stopwatch.Stop;
    UpdateAudioLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
  end;
end;
// 一時デコーダで動画情報だけを読む
class function TFFmpegDecoder.ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder;
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

// 一時デコーダで指定位置のフレームだけを読む
class function TFFmpegDecoder.DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder;
  Info: TVideoInfo;
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
    if Result then
      Result := Decoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

end.




