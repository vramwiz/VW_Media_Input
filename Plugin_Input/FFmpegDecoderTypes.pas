unit FFmpegDecoderTypes;

// デコーダ間で共有する音声buffer、統計、メディア情報の軽量な型を定義する。
// FFmpeg本体のresource所有権は持たず、状態を受け渡すためのrecordだけを置く。

interface

uses
  Winapi.MMSystem;

type
  PAudioWaveBuffer = ^TAudioWaveBuffer;
  TAudioWaveBuffer = record
    Header : TWaveHdr; // waveOutへ渡すbuffer header
    Data   : Pointer;  // PCMデータの先頭
    Size   : Integer;  // PCMデータのバイト数
  end;

  TAudioPlaybackStats = record
    AudioPackets   : Int64;   // 音声packetを処理した回数
    DecodedFrames  : Int64;   // 音声frameをdecodeした回数
    DecodedSamples : Int64;   // decode済みsample数
    LastPtsMs      : Integer; // 最後に処理した音声PTS ms
    Peak           : Integer; // PCM16の最大絶対振幅
    Rms            : Double;  // PCM16のRMS振幅
    NonZeroPercent : Double;  // 非ゼロsampleの割合
    QueuedBuffers  : Integer; // waveOutへqueue済みbuffer数
    SendErrors     : Int64;   // packet送信で発生したエラー回数
    ConvertErrors  : Int64;   // PCM変換で発生したエラー回数
  end;

  TDecodeLoadStats = record
    VideoLastMs            : Double; // 直近の映像処理合計時間
    VideoAverageMs         : Double; // 映像処理合計時間の移動平均
    VideoMaxMs             : Double; // 映像処理合計時間の最大値
    VideoFrames            : Int64;  // 映像統計を更新したフレーム数
    VideoDecodeLastMs      : Double; // 直近の映像decode時間
    VideoDecodeAverageMs   : Double; // 映像decode時間の移動平均
    VideoDecodeMaxMs       : Double; // 映像decode時間の最大値
    VideoConvertLastMs     : Double; // 直近の映像変換時間
    VideoConvertAverageMs  : Double; // 映像変換時間の移動平均
    VideoConvertMaxMs      : Double; // 映像変換時間の最大値
    VideoTransferLastMs    : Double; // 直近のHW frame転送時間
    VideoTransferAverageMs : Double; // HW frame転送時間の移動平均
    VideoTransferMaxMs     : Double; // HW frame転送時間の最大値
    AudioLastMs            : Double; // 直近の音声処理時間
    AudioAverageMs         : Double; // 音声処理時間の移動平均
    AudioMaxMs             : Double; // 音声処理時間の最大値
    AudioPackets           : Int64;  // 音声統計を更新したパケット数
  end;

  TAudioInfo = record
    Present          : Boolean; // 音声streamが存在し、入力として扱えるか
    StreamIndex      : Integer; // FFmpeg上の音声stream index
    SampleRate       : Integer; // 音声sample rate
    Channels         : Integer; // 音声channel数
    SampleFormat     : Integer; // FFmpeg sample format値
    SampleFormatName : string;  // FFmpeg sample format名
    DurationSec      : Double;  // 音声streamの推定長さ
    OpenError        : string;  // 音声open時の直近エラー
  end;

  TVideoInfo = record
    Width           : Integer;    // 映像幅
    Height          : Integer;    // 映像高さ
    DurationSec     : Double;     // 映像streamの推定長さ
    FpsText         : string;     // 表示用fps文字列
    Fps             : Double;     // 計算用fps
    PixelFormat     : Integer;    // FFmpeg pixel format値
    PixelFormatName : string;     // FFmpeg pixel format名
    HasAlpha        : Boolean;    // alpha channelを含むpixel formatか
    Audio           : TAudioInfo; // 同じファイルの音声情報
  end;

implementation

end.
