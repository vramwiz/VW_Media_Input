# VW_Media_Input 引き継ぎメモ

## 目的

`VW_Media_Input` は AviUtl2 用の入力プラグインとして、FFmpeg 8.1 系 DLL を使って動画/音声ファイルを読み込むための開発場所。

入力プラグインの土台として、`D:\DelphiProg\test\Syncroh2` の `Syncroh2_Input_Base.dpr` と関連ユニットをコピーして作成した。

プロジェクト名:

- `VW_Media_Input`

開発フォルダ:

- `D:\DelphiProg\test\VW_Media_Input`

## コピー元

入力プラグインの基本構造:

- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dpr`
- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dproj`
- `Plugin_Input\PluginInputBase.pas`
- `AviUtl\Input\AviUtl2InputTypes.pas`
- `AviUtl\Render\AviUtl2Render.pas`
- `AviUtl\SharedMemory\SharedMemoryManager.pas`
- 必要な `Lib\...` ユニット

FFmpeg 検証コード:

- `D:\DelphiProg\test\FFmpeg\04\FFmpegDecoder.pas`

FFmpeg 8.1 系 DLL:

- `avutil-60.dll`
- `avcodec-62.dll`
- `avformat-62.dll`
- `swscale-9.dll`
- `swresample-6.dll`

## 現在の状態

2026-06-02 時点:

- `VW_Media_Input.dpr` / `VW_Media_Input.dproj` を作成済み。
- `Syncroh2_Input_Base` 由来のプロジェクト名を `VW_Media_Input` に置換済み。
- `FFmpegDecoder.pas` はコピー済みだが、入力プラグイン処理にはまだ接続していない。
- Win64 Debug ビルド成功。
  - 警告 1
  - エラー 0
  - 警告は `PluginInputBase.pas` の元ベース由来。

現在のプラグイン実装は、まだ `Syncroh2_Input_Base` のダミー入力に近い。

- `PluginInputOpen` は FFmpeg で実ファイルを開いていない。
- ファイル名からサイズ、時間、fps を読む旧テスト処理が残っている。
- `PluginInputReadVideo` は実動画デコードをしていない。
- `func_read_audio` は `0` を返すだけ。
- `INPUT_PLUGIN_FLAG_AUDIO` / `INPUT_INFO_FLAG_AUDIO` はまだ使っていない。

## 現在のファイルフィルター

現状では実デコード未接続のため、フィルターは動画系だけにしている。

- `*.mp4`
- `*.mov`
- `*.mkv`
- `*.avi`

注意:

- フィルターに表示されるだけで、現時点では実際の動画デコード対応はまだ未実装。
- 次の作業で `PluginInputBase.pas` と `FFmpegDecoder.pas` を接続する必要がある。

## 将来対応

まずは動画ファイル対応を優先する。

段階案:

1. `PluginInputOpen` で `TFFmpegDecoder.Open` を呼び、動画情報を取得する。
2. `PluginInputGetInfo` に幅、高さ、fps、フレーム数、画像フォーマットを設定する。
3. `PluginInputReadVideo` で指定フレームをデコードして AviUtl2 のバッファへ返す。
4. Bitmap 依存を減らし、AviUtl2 が要求する生バッファへ直接書く方向に寄せる。
5. その後、音声付き動画の `func_read_audio` 対応を検討する。

mp3 について:

- 将来的には FFmpeg 経由で対応したい。
- ただし mp3 は音声のみ入力なので、`INPUT_PLUGIN_FLAG_AUDIO`、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` の実装が必要。
- 動画対応が安定してから追加する。

wav について:

- wav は AviUtl2 標準機能で対応できる可能性が高い。
- そのため、このプラグインで優先して処理する必要はないかもしれない。
- 必要性が出た場合だけ対応を検討する。

## FFmpeg 04 からの注意

`D:\DelphiProg\test\FFmpeg\04` では、FFmpeg 8.1 移行と負荷測定を実施済み。

分かったこと:

- 音声デコード負荷は小さい。
- 主な負荷は FFmpeg の映像デコード本体。
- `sws_scale + TBitmap` 変換も平均数 ms 程度の負荷がある。
- `ImagePreview` への表示コピーは大きな負荷ではなかった。

現在コピーした `FFmpegDecoder.pas` は、負荷測定のため一時的にコメントアウトされた箇所を含む可能性がある。

通常の映像表示/変換へ戻す場合は、以下を確認する。

- `FFmpegDecoder.pas` の `CopyFrameToBitmap(Frame, Bitmap)` 呼び出し
- `Unit9.pas` 側の `ImagePreview.Picture.Bitmap.Assign(Bitmap)` はこのプラグインには不要

プラグインでは `TBitmap` 表示ではなく、最終的には AviUtl2 の `buf` へ直接出力する設計を目指す。
