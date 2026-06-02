unit FFmpegDecoderTypes;

interface

uses
  Winapi.MMSystem;

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

implementation

end.
