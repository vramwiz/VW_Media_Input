unit FFmpegDecoderContext;

// TFFmpegDecoderから段階的に切り出すためのresource保持コンテキスト。
// まだ所有権の橋渡し用途なので、実際の解放順序は既存decoder側の処理に合わせる。

interface

uses
  FFmpegDecoderTypes;

type
  TFFmpegDecoderContext = class
  public
    FileName           : string;           // 開いている入力ファイル名
    FormatContext      : Pointer;          // FFmpeg format context
    CodecContext       : Pointer;          // 映像decoder codec context
    Stream             : Pointer;          // 映像stream
    StreamIndex        : Integer;          // 映像stream index
    AudioCodecContext  : Pointer;          // 音声decoder codec context
    AudioStream        : Pointer;          // 音声stream
    AudioStreamIndex   : Integer;          // 音声stream index
    AudioFrame         : Pointer;          // 音声decode用frame
    SwrContext         : Pointer;          // 音声変換用swr context
    Packet             : Pointer;          // decodeに使う共有packet
    Frame              : Pointer;          // 映像decode用frame
    TransferFrame      : Pointer;          // HW frameをCPUへ転送するためのframe
    QsvDeviceContext   : Pointer;          // QSV decoder用device context
    DirectSwsContext   : Pointer;          // 直接変換経路のsws context
    DirectSwsSrcWidth  : Integer;          // 直接変換contextの入力幅
    DirectSwsSrcHeight : Integer;          // 直接変換contextの入力高さ
    DirectSwsSrcFormat : Integer;          // 直接変換contextの入力pixel format
    DirectSwsDstFormat : Integer;          // 直接変換contextの出力pixel format
    VideoDecoderName   : string;           // 実際に開いた映像decoder名
    VideoUsesQsv       : Boolean;          // 映像decoderがQSV経路か
    Info               : TVideoInfo;       // open時に取得した動画情報
    DecodeStats        : TDecodeLoadStats; // decode負荷統計
  end;

implementation

end.
