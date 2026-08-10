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
- `Plugin_Input\FFmpegDecoder.pas` はコピー済みだが、入力プラグイン処理にはまだ接続していない。
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

## ビルド方法

Delphi 37.0 の環境変数を読み込んでから MSBuild で Win64 Debug をビルドする。

PowerShell から実行する場合:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

cmd から実行する場合:

```bat
"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

2026-06-02 時点では、この手順で Win64 Debug ビルド成功。

- 警告 0
- エラー 0
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` へ `.aui2` と FFmpeg DLL をコピーする。

## 現在のファイルフィルター

現状のフィルターは動画系に加えて音声系を含めている。
動画ファイルの手元サンプルが少ないため、追加分は FFmpeg に渡す仮対応として一通り入れている。

- `*.mp4`
- `*.mov`
- `*.mkv`
- `*.avi`
- `*.wmv`
- `*.asf`
- `*.webm`
- `*.mpg`
- `*.mpeg`
- `*.m2ts`
- `*.ts`
- `*.m4v`
- `*.mp3`
- `*.wav`
- `*.m4a`
- `*.aac`
- `*.wma`
- `*.flac`
- `*.ogg`
- `*.opus`

注意:

- 動画ファイルは FFmpeg 経由で映像情報、映像フレーム、音声情報を返す。
- `*.wmv` / `*.asf` / `*.webm` / `*.mpg` / `*.mpeg` / `*.m2ts` / `*.ts` / `*.m4v` はフィルター追加による仮対応で、実ファイル確認は未実施。
- `*.mp3` / `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` は音声専用入力として扱い、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` 経路で PCM16 stereo 48kHz を返す。
- スピーカーが無いため mp3 の聴感確認は未実施だが、AviUtl2 上では問題ないように見える。

## 将来対応

まずは動画ファイル対応を優先する。

段階案:

1. `PluginInputOpen` で `TFFmpegDecoder.Open` を呼び、動画情報を取得する。
2. `PluginInputGetInfo` に幅、高さ、fps、フレーム数、画像フォーマットを設定する。
3. `PluginInputReadVideo` で指定フレームをデコードして AviUtl2 のバッファへ返す。
4. Bitmap 依存を減らし、AviUtl2 が要求する生バッファへ直接書く方向に寄せる。
5. その後、音声付き動画の `func_read_audio` 対応を検討する。

mp3 について:

- FFmpeg 経由で音声専用入力として対応済み。
- 映像ストリームが無い場合でも、音声ストリームが開ければ `TFFmpegDecoder.Open` は成功する。
- 音声のみなので `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` は返さず、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` を使う。
- スピーカーが無いため聴感確認は未実施。波形/メーターなどでの確認は今後行う。

音声形式について:

- `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` をフィルターへ追加済み。
- 基本的には mp3 と同じ音声専用入力経路で扱う。
- FFmpeg が開ける音声ストリームなら PCM16 stereo 48kHz として返せる可能性が高い。
- `*.wav` は AviUtl2 標準入力で扱える可能性が高いため、`VW_Media_Input.dpr` の `MEDIA_FILE_FILTER` 定数でコメント切り替えできるようにしている。
  - `MEDIA_FILE_FILTER_WITH_WAV`: wav も FFmpeg 経由で扱う。
  - `MEDIA_FILE_FILTER_WITHOUT_WAV`: wav はこのプラグインのフィルターから外し、標準入力へ任せる。
- 実ファイル確認は今後行う。

## FFmpeg 04 からの注意

`D:\DelphiProg\test\FFmpeg\04` では、FFmpeg 8.1 移行と負荷測定を実施済み。

分かったこと:

- 音声デコード負荷は小さい。
- 主な負荷は FFmpeg の映像デコード本体。
- `sws_scale + TBitmap` 変換も平均数 ms 程度の負荷がある。
- `ImagePreview` への表示コピーは大きな負荷ではなかった。

現在コピーした `Plugin_Input\FFmpegDecoder.pas` は、負荷測定のため一時的にコメントアウトされた箇所を含む可能性がある。

通常の映像表示/変換へ戻す場合は、以下を確認する。

- `Plugin_Input\FFmpegDecoder.pas` の `CopyFrameToBitmap(Frame, Bitmap)` 呼び出し
- `Unit9.pas` 側の `ImagePreview.Picture.Bitmap.Assign(Bitmap)` はこのプラグインには不要

プラグインでは `TBitmap` 表示ではなく、最終的には AviUtl2 の `buf` へ直接出力する設計を目指す。

## 現在のユニット構成

2026-06-02 時点の主なユニット構成:

### 入口

- `VW_Media_Input.dpr`
  - AviUtl2 入力プラグインの exported function を持つ。
  - `PluginInputBase.pas` の関数へ処理を委譲する。

### AviUtl2 入力プラグイン側

- `Plugin_Input\PluginInputBase.pas`
  - AviUtl2 から呼ばれる入力処理本体。
  - `PluginInputOpen` / `PluginInputGetInfo` / `PluginInputReadVideo` / `PluginInputReadAudio` を実装する。
  - 映像は `TFFmpegDecoder` へ委譲する。
  - 音声は `TPluginAudioInputReader` へ委譲する。
  - AviUtl2 へ返すフレームキャッシュ、BITMAPINFOHEADER、フレーム番号管理を持つ。

- `Plugin_Input\PluginAudioInputReader.pas`
  - AviUtl2 の `func_read_audio` 用の読み取り処理。
  - 音声用に別の `TFFmpegDecoder` を開き、PCM16 stereo 48kHz を必要分だけ順次デコードする。
  - `WAVEFORMATEX`、PCM キャッシュ、デコード済みサンプル数を管理する。

### FFmpeg デコーダ本体

- `Plugin_Input\FFmpegDecoder.pas`
  - FFmpeg デコードの中心ユニット。
  - ファイル open / close、映像デコード、音声デコード、シーク、順方向読み取りを担当する。
  - FFmpeg の低レベル API 定義、型定義、フレーム変換、統計計算は別ユニットへ分離済み。
  - 今後肥大化しやすいので、追加機能はできるだけ `Plugin_Input\FFmpeg*.pas` に逃がす方針。

### FFmpeg 周辺ユニット

- `Plugin_Input\FFmpegApi.pas`
  - FFmpeg の record / pointer 型、定数、関数ポインタ型を定義する。
  - FFmpeg DLL のロード、関数取得、`TFFmpegApi.EnsureLoaded`、`ErrorText` を持つ。
  - `RationalToDouble`、`StreamAt`、`StreamTimestampToMs` などの低レベル補助関数もここに置く。

- `Plugin_Input\FFmpegDecoderTypes.pas`
  - デコーダ公開情報と統計用の型定義。
  - `TVideoInfo`、`TAudioInfo`、`TAudioPlaybackStats`、`TDecodeLoadStats`、`TAudioWaveBuffer` を持つ。

- `Plugin_Input\FFmpegFrameConvert.pas`
  - `AVFrame` から出力バッファへの変換処理。
  - `CopyFrameToBgrx32Buffer` は AviUtl2 の 32bit BGRx バッファへ直接書き込む。
  - `CopyFrameToBitmap` は一時確認用/互換用の `TBitmap` 変換。

- `Plugin_Input\FFmpegStreamInfo.pas`
  - ストリーム情報読み取り。
  - 現在は音声ストリーム情報を `TVideoInfo.Audio` に反映する `ReadAudioInfo` を持つ。

- `Plugin_Input\FFmpegDecodeStats.pas`
  - 映像/音声の負荷統計と、PCM 音量確認用統計の計算。
  - `Plugin_Input\FFmpegDecoder.pas` 側は統計 record を持ち、このユニットの関数へ更新処理を委譲する。

### AviUtl2 型ユニット

- `AviUtl\Input\AviUtl2InputTypes.pas`
  - AviUtl2 入力プラグイン用の構造体、フラグ、関数型。

- `AviUtl2InputTypes.pas` 以外の `AviUtl` 配下ユニットと `Lib` 配下ユニットは未使用確認後に削除済み。

### 分割方針

- `Plugin_Input\FFmpegDecoder.pas` には「開く、閉じる、読む、シークする」というデコードの流れを残す。
- FFmpeg API 定義や DLL ロードは `FFmpegApi.pas` に置く。
- AviUtl2 側の都合は `PluginInputBase.pas` / `PluginAudioInputReader.pas` に寄せる。
- 変換、統計、ストリーム情報などの純粋な補助処理は `Plugin_Input\FFmpeg*.pas` へ分ける。
- 新しくまとまった責務が増えた場合は、ルートではなく `Plugin_Input` 配下へ新規ユニットを作る。

## 2026-06-02 mp3 対応状況

mp3 対応の入口を追加した。

変更内容:

- `VW_Media_Input.dpr`
  - プラグイン名を `動画/音声入力` に変更。
  - ファイルフィルターに `*.mp3` を追加。
  - 情報文言を動画/音声向けに変更。
- `Plugin_Input\FFmpegDecoder.pas`
  - 映像ストリームが無いファイルでも、音声ストリームが開ければ `Open` 成功にするよう変更。
  - mp3 のような音声専用入力では、映像デコーダを作らず音声デコーダだけを開く。
- `Plugin_Input\PluginInputBase.pas`
  - `HasVideo` を追加。
  - 音声専用ファイルでは `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` を返さず、`INPUT_INFO_FLAG_AUDIO` / `audio_format` / `audio_n` だけ返す。
  - `PluginInputReadVideo` は映像が無い場合 `0` を返す。
  - `PluginInputReadAudio` は既存の `TPluginAudioInputReader` 経由で PCM16 stereo 48kHz を返す。

ビルド確認:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

結果:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` と FFmpeg DLL を配置済み。

動作確認メモ:

- スピーカーが無いため、実際に音が鳴るかの聴感確認は未実施。
- ただし AviUtl2 上では問題ないように見える。
- 現時点では「mp3 を音声専用入力として開き、音声情報と PCM 読み出し経路を返す」ところまで対応済みと見る。

今後確認したいこと:

- スピーカーまたは波形/メーターで、実際に音声が正しく読めているか確認する。
- 長い mp3 でシークやランダムアクセス要求が来た場合の挙動を確認する。
- 必要なら `func_read_audio` の要求位置が戻るケースに備えて、音声デコードキャッシュ/再オープン/シーク対応を強化する。

## 2026-06-02 リリース用 zip

Win64 Debug ビルド後に、AviUtl2 へ配置済みのプラグインフォルダを zip 化した。
zip 作成処理は `Setup\make_release_zip.bat` にバッチ化した。

作成元:

- `C:\ProgramData\aviutl2\Plugin\VW_Media_Input`

作成先:

- `D:\DelphiProg\test\VW_Media_Input\Setup\VW_Media_Input.zip`

GitHub Releases:

- `https://github.com/vramwiz/VW_Media_Input/releases/tag/v1.0.0`

作成コマンド:

```bat
Setup\make_release_zip.bat
```

zip 内容:

- `VW_Media_Input\VW_Media_Input.aui2`
- `VW_Media_Input\avutil-60.dll`
- `VW_Media_Input\avcodec-62.dll`
- `VW_Media_Input\avformat-62.dll`
- `VW_Media_Input\swscale-9.dll`
- `VW_Media_Input\swresample-6.dll`

メモ:

- zip は `VW_Media_Input` フォルダごと含めている。
- zip ファイル名は日付を付けず、常に `VW_Media_Input.zip` とする。
- 展開先は `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` を想定する。
- zip の配置場所は `releases` ではなく `Setup` フォルダとする。
- 現時点の zip は Debug ビルド由来。正式配布時は Release ビルドで作り直すか検討する。

## 2026-06-03 YUY2 映像出力テスト

aviutl2 への映像渡しを 32bit BGRx から YUY2 に切り替えられるようにした。

切替位置:

- `Plugin_Input\PluginInputBase.pas`
- `USE_YUY2_VIDEO_OUTPUT = True`

戻し方:

- `USE_YUY2_VIDEO_OUTPUT = False` にすると従来の 32bit BGRx / `BI_RGB` 出力に戻る。

YUY2 有効時:

- `BITMAPINFOHEADER.biCompression = 'YUY2'`
- `BITMAPINFOHEADER.biBitCount = 16`
- `biSizeImage = width * height * 2`
- デコードログには `seek_decode_yuy2` / `next_decode_yuy2` が出る。

ログクリア:

- Debugビルドでは `Plugin_Input\PluginInputBase.pas` の `CLEAR_DECODE_TRACE_ON_OPEN = True` により、入力を開くたびに `%TEMP%\VW_Media_Input_decode.log` を作り直す。
- 過去ログを残して比較したい場合は `CLEAR_DECODE_TRACE_ON_OPEN = False` にする。
- クリアされたログの先頭には `log_clear file="..."` が出る。

狙い:

- aviutl2 へ渡す映像バッファ量を 32bit の半分にして、コピー量と変換後バッファ量を減らす。

注意:

- 色味、上下方向、aviutl2 側での YUY2 受け取りが問題ないかを実機で確認する。
- 問題が出た場合は `USE_YUY2_VIDEO_OUTPUT = False` で即座に従来経路へ戻せる。

上下方向修正:

- AviUtl2上でYUY2出力が上下逆になったため、`CopyFrameToYuy2Buffer` はトップダウン書き込みに変更した。
- BGRx32経路は従来どおりボトムアップのまま。

整理:

- 文字化けコメント行の影響で `FFmpegFrameConvert.pas` のYUY2実装が重複し、BGRx側へ誤ってトップダウン指定が入っていた。
- `FFmpegFrameConvert.pas` を整理し直し、`CopyFrameToBgrx32Buffer` と `CopyFrameToYuy2Buffer` を1実装ずつにした。
- 現在は BGRx32 = ボトムアップ、YUY2 = トップダウン。

## 2026-06-03 Debug専用ログ/計測の整理

Releaseビルドおよび `DECODE_TRACE_ENABLED = False` 時に、ログ用の重い処理が残らないよう整理した。

対象:

- `DecodeTrace(Format(...))` の文字列生成
- `read_packets` / `video_packets` / `decoded_frames` のログ用カウント
- `TStopwatch` によるログ用時間計測
- `UpdateVideoLoadStats` のログ/確認用更新

方針:

- `{$IFDEF DEBUG}` でDebugビルド時のみログ処理を含める。
- Debugビルド内でも `DECODE_TRACE_ENABLED = False` なら `Format(...)` や `TStopwatch.StartNew` を実行しない。
- Releaseビルドではログ用処理をコンパイル対象から外す。

ビルド確認:

- Win64 Release: 成功。
- Win64 Debug: `Win64\Debug_check` 出力で成功。

## 関連ユニットの目的

YUY2入力高速化とデバッグログ整理に関係するユニット:

- `Plugin_Input\PluginInputBase.pas`
  - AviUtl2入力プラグインとしてのopen/get_info/read_video/read_audioを担当する。
  - `USE_YUY2_VIDEO_OUTPUT` でAviUtl2へ返す映像形式をYUY2/BGRx32で切り替える。
  - Debug時のログクリア、`read_video` 経路ログ、共有フレームキャッシュを管理する。
- `Plugin_Input\FFmpegDecoder.pas`
  - FFmpegのopen/seek/next decodeを担当する。
  - AviUtl2向けの直接出力経路としてBGRx32/YUY2の両方を持つ。
  - Debug時のみデコード時間、変換時間、packet/frame数をログへ出す。
- `Plugin_Input\FFmpegFrameConvert.pas`
  - `sws_scale` によるAVFrameから出力バッファへのピクセル形式変換を担当する。
  - BGRx32は正の`BITMAPINFOHEADER.biHeight`向けにボトムアップで渡す。
  - YUY2はAviUtl2上で正しい上下方向になるようトップダウンで渡す。
- `Plugin_Input\FFmpegApi.pas`
  - FFmpeg DLL関数と必要な定数の宣言を担当する。
  - YUY2出力用に `AV_PIX_FMT_YUYV422 = 1` を定義する。

## 2026-06-03 デコード速度調査メモ

目的:

- `VW_Media_Output` 側の `get_video` が支配的に遅いため、`VW_Media_Input` 側の映像読み込み経路を確認した。
- 数フレーム先読みが有効か、または色変換・出力形式の変更が効くかを比較した。

前提:

- テスト出力ログ: `D:\VoiceroidProj\main_14\59\proj14_59_01_test.mp4.perf.log`
- 入力詳細ログ: `%TEMP%\VW_Media_Input_decode.log`
- 主な素材は `src_fmt=0`、`dst_fmt=28`。
- `src_fmt=0` は FFmpeg の `AV_PIX_FMT_YUV420P` 相当と考えられる。
- `dst_fmt=28` は `AV_PIX_FMT_BGRA`。

確認できたこと:

- `read_video` はほぼ `route=forward` / `gap=1` だった。
- `seek` は少数で、今回の遅さの主因ではなかった。
- 数フレーム先読みは今回のエンコード用途では優先度が低い。
- `next_decode` の時間はほぼ `convert_ms` と一致しており、主因は FFmpeg デコードそのものではなく `sws_scale` による `YUV420P -> BGRA/BGRx32` 変換。

試した変更:

- 映像読み込み中に音声パケットを `DecodeAudioPacket` しないようにした。
  - `get_video avg` が約 `21.082ms -> 19.607ms` まで改善した実行があり、効果あり。
- `USE_YUY2_VIDEO_OUTPUT=True` / YUY2 出力。
  - バッファ量は半分になるが、`sws_scale` の YUY2 変換が重く、BGRx32 より遅かった。
- `SWS_BILINEAR -> SWS_FAST_BILINEAR`。
  - 効果なし。むしろわずかに悪化したため不採用。
- BGR24 出力。
  - `image_size` は BGRx32 より小さくなるが、変換時間・全体時間は改善しなかった。
  - BGRx32 と同等かやや悪い。

代表値:

- YUY2:
  - `next_decode_yuy2 avg` 約 `5.703ms`
  - `read_video forward avg` 約 `6.114ms`
- BGRx32:
  - `next_decode avg` 約 `4.965ms` から `5.1ms` 前後
  - `read_video forward avg` 約 `5.4ms` 前後
- BGR24:
  - `next_decode_bgr24 avg` 約 `5.115ms`
  - `read_video forward avg` 約 `5.533ms`

現時点の結論:

- 採用候補は BGRx32。
- `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_BGRX32` を現状の基準とする。
- YUY2、BGR24、`SWS_FAST_BILINEAR` は今回の素材・環境では不採用。
- 先読みは今回のログでは効果が薄そうなので実装しない。

次に試す候補:

- `sws_scale` を避ける方向を検討する。
- 入力フレームが `YUV420P` で来ているため、AviUtl2 側が `I420` / `IYUV` / `YV12` / `NV12` などの YUV420 系 FourCC を受けられるか試す。
- 最初に試すなら、元の `YUV420P` に近い `I420` が軽そう。
- `NV12` は出力エンコード側に近いが、Y/U/V から UV インターリーブへの詰め替えが必要。

## 2026-06-04 YC48 直接出力テスト

`sws_scale` による `YUV420P -> BGRx32` 変換を避けるため、AviUtl2 寄りの `YC48` 出力を試す。

変更内容:

- `Plugin_Input\PluginInputBase.pas`
  - `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YC48` に変更。
  - AviUtl2 へ `biCompression = 'YC48'`、`biBitCount = 48`、`biSizeImage = width * height * 6` を返す。
- `Plugin_Input\FFmpegFrameConvert.pas`
  - `YUV420P -> YC48` の自前変換で、Y/Cb/Cr の値変換を初期化時のルックアップテーブル化。
  - フレームごとの除算を避け、`sws_scale` を使わない経路の負荷を下げる。

狙い:

- AviUtl2 が対応している `YC48` 形式へ寄せる。
- RGB変換を避け、FFmpegデコード後の変換コストを下げる。

確認ポイント:

- AviUtl2上で正しく表示されるか。
- 色味が大きく崩れないか。
- `%TEMP%\VW_Media_Input_decode.log` の `next_decode_yc48` / `read_video forward` が BGRx32 より改善するか。

戻し方:

- `Plugin_Input\PluginInputBase.pas` の `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_BGRX32` に戻す。

結果:

- 貼り付けログ 25 フレーム分では `next_decode_yc48 convert_ms avg` 約 `14.901ms`。
- `read_video forward avg` 約 `15.452ms`。
- BGRx32 の約 5ms 前後より大幅に遅い。
- `image_size=12441600` で 1920x1080 の 48bit 出力になり、書き込み量が大きすぎる。
- YC48 は今回の高速化目的では不採用。

## 2026-06-04 I420 直接出力テスト

YC48 が遅かったため、さらに踏み込んで `I420` 直接出力を試す。

変更内容:

- `Plugin_Input\PluginInputBase.pas`
  - `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_I420` に変更。
  - AviUtl2 へ `biCompression = 'I420'`、`biBitCount = 12` を返す。

狙い:

- 入力フレームが `AV_PIX_FMT_YUV420P` の場合、`sws_scale` を使わず Y/U/V plane コピーだけにする。
- 1920x1080 なら出力サイズは約 3.1MB になり、BGRx32 の約 8.3MB、YC48 の約 12.4MB より小さい。

注意:

- `AviUtl2InputTypes.pas` のコメント上は `I420` が対応形式として明記されていないため、AviUtl2 が受け付けるかは実機確認が必要。
- 表示不可、黒画面、色崩れが出る可能性がある。

確認ポイント:

- AviUtl2上で開けるか。
- 映像が正しい向き・色で表示されるか。
- `%TEMP%\VW_Media_Input_decode.log` の `next_decode_i420` / `read_video forward` が BGRx32 より改善するか。

ビルド状況:

- Win64 Debug のコンパイル自体は成功。
- post-build の `.dll -> .aui2` コピーで、`C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` が使用中のため失敗。
- AviUtl2 などがプラグインを掴んでいる可能性があるため、対象アプリを閉じてから再ビルドする。

結果:

- AviUtl2 上で「このファイルは対応していません」と表示され、入力形式として受け付けられなかった。
- `AviUtl2InputTypes.pas` のコメント上も `I420` は対応形式に明記されていないため、I420 直接出力は不採用。
- いったん `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_BGRX32` へ戻す。

## 2026-06-04 08検証結果を入力プラグインへ反映

`D:\DelphiProg\test\FFmpeg\08` で確認した QSV decode 周りを、入力プラグイン本体へ戻した。

反映した内容:

- `Plugin_Input\FFmpegQsvDecode.pas` を追加。
  - H.264/HEVC/MPEG2/MJPEG/VP8/VP9/AV1 の codec id から `*_qsv` decoder名を選ぶ。
  - QSV device contextを作る。
  - `AV_PIX_FMT_QSV` のHW frameが返った場合だけCPU側frameへ転送する。
- `Plugin_Input\FFmpegApi.pas`
  - `avcodec_find_decoder_by_name`
  - `av_hwdevice_ctx_create`
  - `av_hwframe_transfer_data`
  - `av_buffer_unref`
  - `av_frame_unref`
  - `AV_PIX_FMT_NV12 = 23`
  - `AV_PIX_FMT_QSV = 114`
  - `AV_HWDEVICE_TYPE_QSV = 5`
  を追加。
- `Plugin_Input\FFmpegDecoder.pas`
  - 映像open時にQSV decoderを優先して試す。
  - 失敗時はsoftware decoderへfallbackする。
  - 実際に開いたdecoder名とQSV使用有無をログへ出す。
  - QSV HW frame転送に備えて `FTransferFrame` と `FQsvDeviceContext` を管理する。
  - BGRx32/YUY2/I420 の順方向デコードログを `decode_ms`、`transfer_ms`、`convert_ms` に分離する。
- `Plugin_Input\FFmpegDecoderTypes.pas` / `Plugin_Input\FFmpegDecodeStats.pas`
  - 映像処理時間を total/decode/transfer/convert で分けて保持・更新できるようにした。
- `VW_Media_Input.dpr` / `VW_Media_Input.dproj`
  - `FFmpegQsvDecode.pas` を登録。

08で確認済みの結果:

```text
QSV decoder:
decoder="h264_qsv" qsv=True
src_fmt=23 dst_fmt=0
transfer_ms=0.000

I420/QSV:
elapsed  avg=0.743 ms
decode   avg=0.332 ms
transfer avg=0.000 ms
convert  avg=0.339 ms

BGRx32/QSV:
elapsed  avg=3.672 ms
decode   avg=0.370 ms
transfer avg=0.000 ms
convert  avg=3.229 ms

YUY2/QSV:
elapsed  avg=2.374 ms
decode   avg=0.412 ms
transfer avg=0.000 ms
convert  avg=1.883 ms
```

現在の本体側判断:

- QSV decodeは本体へ反映済み。
- I420変換メソッドとログは本体へ反映済み。
- ただし AviUtl2 への直接出力形式は `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_BGRX32` のまま維持する。
- 理由は、AviUtl2上でI420直接出力が「このファイルは対応していません」となり、入力形式として受け付けられなかったため。
- したがって本体の現実的な採用状態は「QSV decode + BGRx32出力」。
- I420は、AviUtl2側で受けられる形式が見つかった場合や、別経路でYUV420を渡せる場合の本命候補として残す。

ビルド確認:

- Win64 Debug ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` へコピー成功。
- Win64 Release ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` へコピー成功。

DLL確認:

- `C:\ProgramData\aviutl2\Plugin\VW_Media_Input`
  - `avcodec-62.dll`
  - `avformat-62.dll`
  - `avutil-60.dll`
  - `swresample-6.dll`
  - `swscale-9.dll`
  が配置済み。

次の確認:

- AviUtl2で同じ素材を開く。
- `%TEMP%\VW_Media_Input_decode.log` に `video_decoder ... decoder="h264_qsv" qsv=True` が出るか確認する。
- `read_video` と `next_decode` の平均を、QSV反映前のBGRx32基準値と比較する。

## 2026-06-04 AviUtl2終了時にプロセスが残る件の暫定対応

QSV反映後、AviUtl2終了時にプロセスが残ることがあるとの報告。

確認した疑い:

- `PluginInputClose` では、デコーダを即解放せず `ReusableDecoder` に退避していた。
- QSV反映後は、デコーダが `FQsvDeviceContext` やFFmpeg/QSV内部リソースを保持する。
- そのため、入力ハンドルclose後もQSV decoder/contextが残り、AviUtl2終了時のプロセス残留につながる可能性がある。

対応:

- `Plugin_Input\PluginInputBase.pas`
  - `ENABLE_REUSABLE_DECODER = False` を追加。
  - 再利用デコーダの取得・保存をこの定数で抑止。
  - `PluginInputClose` 時に `TFFmpegDecoder.Free` が実行され、QSV/FFmpegリソースを即解放するようにした。

影響:

- 同じファイルを閉じてすぐ開き直す時のデコーダ再利用は無効。
- フレーム共有キャッシュはそのまま。
- 通常のデコード速度にはほぼ影響しない想定。

ビルド確認:

- Win64 Debug ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `.aui2` コピー成功。
- Win64 Release ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `.aui2` コピー成功。

次の確認:

- AviUtl2で素材を開く。
- 速度ログが引き続き `decoder="h264_qsv" qsv=True` になるか確認する。
- AviUtl2終了後にプロセスが残らないか確認する。
- まだ残る場合は、次に `TFFmpegDecoder.Close` に詳細なcloseログを追加し、どの解放段階で止まるかを見る。

追記:

- 試行回数は少ないが、毎回発生していたAviUtl2プロセス残留が現時点では出ていない。
- `%TEMP%\VW_Media_Input_decode.log` は更新されており、ログ機能は有効。
- 今回のログ:
  - `log_clear`
  - `video_decoder ... decoder="h264_qsv" qsv=True`
  - `open ok ... reused=False`
  が出ている。
- `reused=False` なので、`ENABLE_REUSABLE_DECODER = False` による再利用デコーダ抑止は効いている。

2026-06-04 10:12 Debug実行ログ集計:

```text
next_decode count=892
elapsed  avg=8.664 ms  min=3.164  max=23.753
decode   avg=0.738 ms  min=0.118  max=3.592
transfer avg=0.000 ms  min=0.000  max=0.000
convert  avg=7.781 ms  min=2.783  max=22.647
```

補足:

- 本体側は `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_BGRX32` のため、QSV decode後にNV12 -> BGRA変換が入る。
- そのため、08のI420出力テストより `convert_ms` は重い。
- ただし `decoder="h264_qsv" qsv=True` は確認できている。

## 2026-06-04 YUY2直接出力の再試行

QSV decode後の本体側BGRx32出力では `NV12 -> BGRA` 変換が重いため、AviUtl2へ別形式で渡せるか再確認する。

AviUtl2 SDKコメント上の対応形式:

- `RGB24`
- `RGBA32`
- `PA64`
- `HF64`
- `YUY2`
- `YC48`

試行順:

- まず `YUY2`。
  - SDKコメントに対応形式として明記されている。
  - 既存実装があり、切り替えだけで試せる。
- `I420` は以前「このファイルは対応していません」となったため、再試行優先度は低い。
- `NV12` はQSV decoderの出力に近く高速化余地は大きいが、SDKコメントに対応形式として明記されていない。
  - 試すなら、まず「AviUtl2がNV12 FourCCを受け付けるか」を見るための追加実装が必要。

変更:

- `Plugin_Input\PluginInputBase.pas`
  - `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YUY2` に変更。

ビルド確認:

- Win64 Debug ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `.aui2` コピー成功。
- Win64 Release ビルド成功。
  - エラー 0。
  - ヒント 2。
  - post-buildで `.aui2` コピー成功。

次の確認:

- AviUtl2で同じ素材を開けるか。
- 色、上下方向が正しいか。
- 終了時にプロセスが残らないか。
- `%TEMP%\VW_Media_Input_decode.log` の `next_decode_yuy2` と `read_video` を集計する。

結果:

- AviUtl2で出力処理を実行。
- ログ上は `decoder="h264_qsv" qsv=True`。
- `next_decode_yuy2` が出ている。
- `image_size=4147200`
  - 1920x1080 YUY2。
  - BGRx32の `8294400` から半分になっている。

2026-06-04 10:18 Debug実行ログ集計:

```text
next_decode_yuy2 count=892
elapsed  avg=3.647 ms  min=1.715  max=10.876
decode   avg=0.581 ms  min=0.107  max=2.071
transfer avg=0.000 ms  min=0.000  max=0.000
convert  avg=2.949 ms  min=1.496  max=9.313

read_video forward count=892
elapsed    avg=4.306 ms  min=2.193  max=17.333
image_size avg=4147200
```

BGRx32/QSV直近値との比較:

```text
BGRx32/QSV:
next_decode elapsed avg=8.664 ms
convert     avg=7.781 ms
read_video  avgは約8ms台
image_size  8294400

YUY2/QSV:
next_decode elapsed avg=3.647 ms
convert     avg=2.949 ms
read_video  avg=4.306 ms
image_size  4147200
```

判断:

- YUY2は本体側で明確に速い。
- AviUtl2 SDKコメント上も対応形式として明記されているため、現時点の本体採用候補は `YUY2` が有力。
- ただし色味、上下方向、終了時プロセス残留が出ないかをもう少し確認する。
- 問題なければ `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YUY2` を本採用候補にする。

## 2026-06-04 デコード高速化はいったん完成

ユーザー判断として、デコード高速化はこの状態でいったん完成とする。

採用状態:

- QSV decodeを優先使用。
  - 対応decoderが開けない場合はsoftware decoderへfallback。
- AviUtl2へ返す映像形式は `YUY2`。
  - `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YUY2`
- 終了時プロセス残留対策として、再利用デコーダは無効。
  - `ENABLE_REUSABLE_DECODER = False`
- I420変換経路は残すが、AviUtl2直接出力では不採用。
  - 理由: AviUtl2がI420入力形式を受け付けなかった。
- BGRx32経路はfallback/比較用として残す。

確定理由:

- `decoder="h264_qsv" qsv=True` を確認済み。
- YUY2はAviUtl2 SDKコメント上の対応形式に含まれる。
- YUY2はBGRx32より明確に速い。
- 1920x1080で返すバッファサイズが `8294400 -> 4147200` に減る。
- 以前毎回発生していたAviUtl2終了時のプロセス残留が、再利用デコーダ無効化後は現時点で再現していない。

代表値:

```text
BGRx32/QSV:
next_decode elapsed avg=8.664 ms
convert     avg=7.781 ms
image_size  8294400

YUY2/QSV:
next_decode elapsed avg=3.647 ms
convert     avg=2.949 ms
read_video  avg=4.306 ms
image_size  4147200
```

今後の扱い:

- デコード周りは大きく触らない。
- 次に触る場合は、バグ修正または環境差対策に限定する。
- 追加実験候補だったNV12は保留。
  - QSVのNV12に近いため理論上は魅力があるが、AviUtl2 SDKコメントに対応形式として明記されていない。
  - 現時点ではYUY2の安定性と効果を優先する。

## 2026-06-04 FFmpegDecoder 分散方針

ここから先の `FFmpegDecoder` 分散は、視認性を落としすぎないために小さい段階で進める。

方針:

- 分散先ユニット名は `FFmpegDecoderxx` 形式に統一し、`FFmpegDecoder` のサブユニットであることを明確にする。
- `TFFmpegDecoder` 自身を外部ユニットへ渡すのではなく、内包状態をまとめる `TFFmpegDecoderContext` を用意し、必要な処理へ Context を渡す方向にする。
- 最初から全フィールドを大きく移動しない。まずは既に切り出した処理や、所有権が分かりやすい処理から Context 化する。
- `TFFmpegDecoder` の公開 API は維持し、外部呼び出し側への影響を出さない。
- デコード種類ごとの大きい実装は、将来的に `FFmpegDecoderNextRead` や `FFmpegDecoderSeekRead` などへ段階的に逃がす。
- 1回の修正では必要最小限に留め、都度 Release / Win64 ビルドで確認する。

実施:

- 既存の分散ユニット名を `FFmpegDecoderAudioPlayback` / `FFmpegDecoderAudioRead` へ変更した。
- `TFFmpegDecoderContext` を追加した。
- まずは `FFmpegDecoderAudioRead` と `FFmpegDecoderResources` の引数束を Context 受け取りへ変更した。
- `TFFmpegDecoder` 本体のフィールド移動はまだ行わず、`CreateContextSnapshot` / `ApplyContextResources` で橋渡しする段階に留めた。
- 次段階として `TFFmpegDecoder` が `FContext` を所有する形へ変更した。
  - `SyncContextFromFields` / `SyncFieldsFromContext` で既存フィールドとの同期を行う。
  - まだ巨大なデコードメソッド群のフィールド参照は置換しない。
  - `_PasCoreCompile` は成功。通常BuildはPostBuild時に配置先 `VW_Media_Input.aui2` が使用中でコピー失敗する場合がある。
- `FFmpegDecoderAudioPlayback` も Context 受け取りへ変更した。
- 将来のデコード種類別ユニット移動に備え、Context に `FileName` / `VideoDecoderName` / `VideoUsesQsv` も追加した。
- `DecodeNextFrameToYc48Optional` を `FFmpegDecoderNextYc48` へ分離した。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - Context に `DecodeStats` を追加し、サブユニット側で統計更新できるようにした。
  - `_PasCoreCompile` は成功。
- `DecodeNextFrameToI420Optional` を `FFmpegDecoderNextI420` へ分離した。
  - QSV frame transfer と stage統計を含むため、`FFmpegDecoderNextYc48` より複雑な分離例になった。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- 慎重ルートとして、現行採用のYUY2より先に `DecodeNextFrameToBgr24Optional` を `FFmpegDecoderNextBgr24` へ分離した。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- 現行採用経路の `DecodeNextFrameToYuy2Optional` を `FFmpegDecoderNextYuy2` へ分離した。
  - `FFmpegDecoderNextI420` と同じQSV frame transfer + stage統計の構成。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- fallback/比較用の `DecodeNextFrameToBgrx32Optional` を `FFmpegDecoderNextBgrx32` へ分離した。
  - QSV frame transfer + stage統計の構成。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- seek系の第一段階として `DecodeFrameToYc48` を `FFmpegDecoderSeekYc48` へ分離した。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- `DecodeFrameToI420` を `FFmpegDecoderSeekI420` へ分離した。
  - `DecodeFrameToYc48` と同じseek系の構成で、変換先だけをI420として分けた。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- `DecodeFrameToBgr24` を `FFmpegDecoderSeekBgr24` へ分離した。
  - seek系の比較/補助経路として、現行採用のYUY2より先に分離した。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- 現行採用経路の `DecodeFrameToYuy2` を `FFmpegDecoderSeekYuy2` へ分離した。
  - seek系のYUY2変換処理を Context 受け取りのサブユニットへ移した。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。
- fallback/比較用の `DecodeFrameToBgrx32` を `FFmpegDecoderSeekBgrx32` へ分離した。
  - QSV frame transfer + stage統計の構成。
  - `TFFmpegDecoder` 側は Context 同期後にサブユニットへ委譲するだけにした。
  - `_PasCoreCompile` は成功。

## 2026-06-05 デコード方式の設定画面

ハードウェアデコードが環境によってソフトウェアデコードより遅くなる可能性があるため、入力プラグインの設定画面から映像デコード方式を選べるようにした。

追加内容:

- `Plugin_Input\PluginInputSettings.pas` を追加。
  - `func_config(hwnd, dll_hinst)` から呼ぶ WinAPI の小さなモーダル設定画面を持つ。
  - 設定は `.aui2` と同じフォルダの `VW_Media_Input.ini` に保存する。
- `Plugin_Input\PluginInputBase.pas`
  - `PluginInputConfig` を MessageBox から設定画面呼び出しへ変更。
- `Plugin_Input\FFmpegDecoder.pas`
  - open時に設定値を読み、QSVを使うかソフトウェアに固定するかを切り替える。
  - `video_decoder` / `qsv_fallback` ログに `decode_mode=...` を追加。
- `VW_Media_Input.dpr` / `.dproj`
  - `PluginInputSettings.pas` を登録。

設定値:

```ini
[VW_Media_Input]
VideoDecoderMode=auto
```

選択肢:

- `auto`
  - QSVを優先して試し、失敗した場合はソフトウェアデコードへfallbackする。
  - 既定値。
- `qsv`
  - QSV固定。
  - QSV decoderやdeviceが開けない場合はopen失敗にする。
- `software`
  - QSVを試さず、FFmpegの通常decoderを使う。

確認:

- Win64 Debug Build 成功。
  - post-buildで `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` へコピー成功。
- Win64 Release Build 成功。
- 最後にDebug版を再ビルドして配置済み。

今後の比較方法:

- 同じmp4を `auto` / `software` で読み込み、`%TEMP%\VW_Media_Input_decode.log` の以下を比較する。
  - `decode_mode`
  - `decode_backend`
  - `gpu_inferred`
  - `decoder`
  - `decode_ms`
  - `transfer_ms`
  - `convert_ms`
  - `read_video elapsed_ms`

## 2026-06-05 GeForce搭載環境での処理落ち調査方針

GeForce搭載PCで、入力プラグインのハードウェアデコードがソフトウェアデコードより遅くなる現象が出ている。

重要な前提:

- 現在の `VW_Media_Input` は NVIDIA/NVDEC デコードを実装していない。
- ハードウェアデコードとして使うのは QSV、つまり Intel Quick Sync。
- GeForceを搭載していても、入力プラグインのデコードで GeForce を直接使っているわけではない。
- GeForceエンコードが遅い/速い問題は `VW_Media_Output` 側の問題で、入力デコードとは分けて比較する。

想定される原因:

- AviUtl2 が Windows/NVIDIA の設定で高パフォーマンスGPU、つまりGeForce側に割り当てられている。
- 入力デコードは Intel QSV、表示/出力/他処理は GeForce 側になり、iGPU/dGPU/CPU 間の転送や同期で不利になる。
- ノートPCの電源設定、GPU切替、ドライバ、Control Center設定で、QSVやメモリ帯域の挙動が変わる。
- QSV decode自体ではなく、`NV12 -> YUY2` の `convert_ms` が重くなっている。

ログ強化:

- `video_decoder` ログに以下を追加した。
  - `decode_backend=qsv/software`
  - `gpu_inferred="Intel Quick Sync"` または `"none"`
  - `nvidia_nvdec_supported=False`
- `qsv_fallback` ログに以下を追加した。
  - `attempted_backend=qsv`
  - `attempted_gpu="Intel Quick Sync"`
  - `nvidia_nvdec_supported=False`

ログの読み方:

```text
decode_backend=qsv gpu_inferred="Intel Quick Sync"
```

Intel QSVでデコードしている。GeForce/NVDECは使っていない。

```text
decode_backend=software gpu_inferred="none"
```

CPUデコード。GPUデコードは使っていない。

```text
nvidia_nvdec_supported=False
```

この入力プラグインではNVDECデコードを実装していない、という意味。

調査手順:

1. 設定画面で `auto` にして同じmp4を読む。
2. 設定画面で `software` にして同じmp4を読む。
3. Windowsのグラフィック設定またはNVIDIAコントロールパネルで、AviUtl2を Intel 側/GeForce 側に切り替えて同じmp4を読む。
4. `%TEMP%\VW_Media_Input_decode.log` の以下を比較する。
   - `decode_backend`
   - `gpu_inferred`
   - `decode_ms`
   - `transfer_ms`
   - `convert_ms`
   - `read_video elapsed_ms`

判断:

- `decode_backend=qsv` で `convert_ms` が重い場合は、QSV後のYUY2変換またはメモリ/電源/GPU切替が怪しい。
- `decode_backend=software` の方が速い場合は、その環境では設定を `software` にする。
- GeForceエンコードを使うべきかどうかは、入力側ログでは判断しない。
  - 出力側で、同じプロジェクトを CPUエンコード / NVENC / QSVエンコード で別途比較する。
  - 入力側のおすすめ設定と出力側のおすすめ設定は別々に決める。

## 2026-06-05 QSVかくつき調査用Debugログ

ソフトウェアデコードでは一部mp4のかくつきが抑えられるが、ハードウェアデコード(QSV)ではかくつくケースがあるため、Debugビルド限定で追加ログを入れた。

追加内容:

- `Plugin_Input\PluginInputBase.pas`
  - `read_video_request` を追加。
    - AviUtl2からの要求フレーム、前回要求フレーム、要求間隔、直近デコード済みフレームを出す。
  - `read_video_slow` を追加。
    - `read_video` が16ms以上、または対象fpsの1フレーム時間以上かかった場合に出す。
  - `close_summary` を追加。
    - close時に `read_video` 回数、slow回数、平均/最大、decoder側のdecode/transfer/convert平均/最大を出す。
- `Plugin_Input\FFmpegDecoderNextYuy2.pas`
  - `next_decode_yuy2` に `hw_transfer` と `slow_stage` を追加。
  - 16ms以上のYUY2順方向デコードでは `next_decode_yuy2_slow` を出す。
- `Plugin_Input\FFmpegDecoderSeekYuy2.pas`
  - `seek_decode_yuy2` に `hw_transfer` と `slow_stage` を追加。
  - 16ms以上のYUY2 seekデコードでは `seek_decode_yuy2_slow` を出す。

ログの見方:

- `read_video_slow` が出るフレームを探す。
- 直後または直前の `next_decode_yuy2_slow` / `seek_decode_yuy2_slow` を見る。
- `stage="decode"` ならQSVデコード待ちが怪しい。
- `stage="transfer"` ならHW frame転送が怪しい。
- `stage="convert"` ならQSV後のYUY2変換、メモリ帯域、GPU切替/同期が怪しい。
- `read_video_request interval_ms` が大きい場合は、入力プラグイン外側(AviUtl2側処理や出力側)で詰まっている可能性も見る。

ビルド確認:

- Win64 Debug `_PasCoreCompile` 成功。
- Win64 Release `_PasCoreCompile` 成功。
- Win64 Debug `Build` はコンパイル本体成功。
  - post-build の `.dll -> .aui2` コピーで、配置済み `VW_Media_Input.aui2` が使用中のため失敗。
  - AviUtl2を閉じてから再Buildすればコピーできる想定。

## 2026-06-05 QSVかくつき再現ログからの原因

AviUtl2側で、ハードウェアデコード(QSV)使用時に1フレームの処理に間に合わず、カーソルが数フレーム飛ぶ現象をDebugログで確認した。

結論:

- QSVの通常の順方向デコード自体は速い。
- ただし、素材切り替え、open直後、初回seek、seek後decodeで300-400ms級の待ちが出る。
- 24fps素材では1フレーム約41.7msなので、300-400ms待つと数フレーム飛ぶ。
- そのため、AviUtl2のプレビュー中に別mp4のQSV open/初回seekが同期的に走ると、現在再生中の素材の次フレーム要求が飛ばされる。
- ソフトウェアデコードでかくつきが抑えられるのは、このQSV初動待ちが出にくいためと考えられる。

代表ログ:

```text
seek_decode_yuy2_slow ... qsv=True stage="decode" elapsed_ms=361.070 decode_ms=357.685 transfer_ms=0.000 convert_ms=1.120
read_video_slow ... frame=53 last=-1 gap=54 route=seek elapsed_ms=365.326 frame_budget_ms=41.667

seek_decode_yuy2_slow ... qsv=True stage="decode" elapsed_ms=319.407 decode_ms=318.249 transfer_ms=0.000 convert_ms=0.816
read_video_slow ... frame=0 last=-1 gap=1 route=seek elapsed_ms=320.239 frame_budget_ms=41.667

seek_decode_yuy2_slow ... qsv=True stage="decode" elapsed_ms=412.723 decode_ms=411.397 transfer_ms=0.000 convert_ms=0.775
read_video_slow ... frame=0 last=-1 gap=1 route=seek elapsed_ms=413.718 frame_budget_ms=41.667
```

重要な読み取り:

- `stage="decode"` なので、遅いのはQSV decode側。
- `transfer_ms=0.000` なので、HW frame転送待ちではない。
- `convert_ms` は約1ms前後なので、YUY2変換が主因ではない。
- `decode_backend=qsv gpu_inferred="Intel Quick Sync"` なので、GeForce/NVDECではなくIntel QSV。

カーソル飛びの具体例:

```text
20:18:20.726 read_video_request ... 3Gk5BysREY.mp4 frame=48
20:18:20.732 log_keep ... jS8BKu5LD0.mp4
20:18:20.961 video_decoder ... jS8BKu5LD0.mp4 decode_backend=qsv
20:18:20.962 open ok ... jS8BKu5LD0.mp4
20:18:20.986 read_video_request ... 3Gk5BysREY.mp4 frame=53 request_gap=5
```

この間に、再生中だった `3Gk5BysREY.mp4` の要求が `frame=48 -> frame=53` に飛んでいる。
`frame=53` の `read_video` 自体は約10msで、24fpsの1フレーム予算内に収まっている。
したがって、直接の問題はそのフレームの変換処理ではなく、直前に別素材のQSV open/初回処理が走ってAviUtl2側の再生タイミングが崩れたことと見る。

現時点の判断:

- プレビュー安定性を優先する場合は `VideoDecoderMode=software` が有力。

### QSV明示指定の厳格化（2026-08-10）

- 設定画面のQSV項目を `QSVを使う（失敗時もソフトウェアへ切り替えない）` と明記した。
- `VideoDecoderMode=qsv` は自動選択から独立した経路でQSVを初期化する。
  - QSV非対応、QSVデコーダ未検出、デバイス作成失敗、デコーダopen失敗のいずれでもsoftwareへフォールバックしない。
  - 失敗時は `qsv_required_failed ... fallback_allowed=False` をDebugログへ出す。
- デコーダ確定ログへ `strict_qsv=True/False` を追加した。`decode_mode=qsv` の成功時は必ず `decode_backend=qsv strict_qsv=True qsv=True` になる。

### QSV繰り返し再生時の別フレーム混入対策（2026-08-10）

- QSVで後方シークを繰り返すと、`avcodec_flush_buffers` 後にもシーク前の非同期フレームが返る現象を確認した。
  - 例: `戦闘_03.mp4` のframe 1へ戻した直後、frame 3で終端付近の約4.96秒、次のframe 4で0秒が返っていた。
- デコーダを新規作成して交換する方式では別フレーム混入を防止できたが、素材ごとに約0.35～0.44秒、seek全体で約0.69～0.87秒かかり、2回目以降の再生停止を悪化させたため採用しない。
- seek後に実際にQSVへ送ったpacketの最大PTS/DTSを記録し、それより3フレーム相当以上未来のPTSを持つ出力だけをseek前の残留フレームとして破棄する。
  - デコーダは維持して `avcodec_flush_buffers` を行うため、QSV初期化の繰り返しを避けられる。
  - 破棄時は `qsv_seek_stale_discard ...` をDebugログへ出す。
  - 共有正確フレームキャッシュの動作は変更しない。
- `戦闘_03.mp4` を `0 -> 116 -> 1 -> 3 -> 4 -> 6` の順で読む独立テストでは、旧終端側のPTS `59904 / 60416 / 60928` を破棄できた。
  - frame 1への後方seekは約36ms、続く順方向は約8～9ms。
  - 同じ並びの2巡目は正確フレームキャッシュが効き、約1.4～2.5msだった。
- QSVは単一素材の順方向デコードでは速いが、複数mp4が並ぶプロジェクトや素材切り替えが多い場面では初動待ちが不利。
- `auto` のままだとQSVが選ばれ、この環境ではカーソル飛びが再発する可能性がある。
- 今後対策するなら、QSVの初回seek/openが一定以上遅い環境や素材では自動的にsoftwareへ倒す、またはプレビュー用途ではsoftware推奨にする。

### 遠距離順方向要求とEOF drain対策（2026-08-10）

- キャッシュから外れた遠方フレームを最大120フレーム分順次デコードし、約175～479msかけて終端エラーになる例を確認した。
- 順方向decodeで追う上限を32フレームへ下げ、それより遠い要求は指定位置への正確seekを使う。
- demuxerがEOFを返した後にNULL packetを送ってデコーダをdrainし、QSVなどが内部に保持している遅延フレームを `source=drain` として返す。
- YUY2 / BGR24 / BGRX32 / I420 / YC48の順方向decode経路へ適用した。

### 情報取得だけの連続open向けメタデータキャッシュ（2026-08-10）

- 終盤で同じ `戦闘_01.mp4` が短時間に繰り返しopen/closeされ、映像を1枚も読まないまま毎回約320～361msのQSV初期化が発生していた。
- 未使用QSV decoder自体を再利用する試験では2回目以降のopenが約2～5msになったが、最後に保持した状態でDLLを解放するとプロセスが残留したため採用しない。
- codec/QSVを開かずcontainer情報だけを読む `ProbeVideoInfo` と、最大256ファイルのメタデータキャッシュを追加した。
  - 入力handleのopen時はメタデータだけを返し、共有正確フレームキャッシュにない最初の `read_video` でQSV decoderを遅延openする。
  - QSV decoderはhandleのclose時に必ず解放し、グローバルには保持しない。
- `戦闘_05.mp4` の独立試験:
  - 初回メタデータopen約78ms、2～4回目は約1.5～1.6ms。
  - 実デコード後の情報openも約1.3ms。
  - DLL解放は約0.85msで、テストプロセスは残留しなかった。
- durationとfpsから返すフレーム数は `Ceil` ではなく最寄り整数を使い、5.042秒/24fps素材を122枚と過大申告して終端frame 121がEOFになる問題を補正する。

### 添付画像付きMP3の音声再生修正（2026-08-10）

- MP3のカバー画像が映像ストリームとして検出され、`VideoDecoderMode=qsv` の場合に画像codecへ厳格QSVを要求して音声用入力のopenまで失敗していた。
- 音声入力用の `TPluginAudioInputReader` は `OpenAudioOnly` を使い、映像ストリームを一切初期化せず音声decoderだけを開く。
- `AV_DISPOSITION_ATTACHED_PIC` の付いたストリームは通常映像から除外し、カバー画像だけを持つMP3をAviUtl2へ音声専用素材として返す。
- 生成したDebug DLLを別プロセスから直接呼び出して確認した。
  - `インスト.mp3` / `合体.mp3` / `合体_2.mp3` はすべて `video=False`、`audio=True`。
  - 各ファイルで先頭4,800サンプルのPCM読み取りに成功し、closeも成功した。
  - ログ上は `width=0 height=0 frames=0 audio=True audio_err=""` となり、`qsv_required_failed` は発生しない。

### MP4初回デコード負荷向け永続正確フレームキャッシュ（2026-08-10）

- QSV遅延初期化と最初のseekで各MP4の最初の `read_video` に約0.5～0.7秒かかるため、AviUtl2へ一度返した正確な映像バッファをディスクへ永続化する。
- `Plugin_Input\PersistentFrameCache.pas` を追加した。
  - 保存先は `%LOCALAPPDATA%\VW_Media_Input\FrameCache`。
  - 保存は最大128フレームの専用キューとバックグラウンドスレッドで行い、安定している初回再生のデコードスレッドをディスク書き込みで止めない。
  - 待機メモリ削減目的で32フレームを試したが、約1.3秒分しか保持できず、各MP4のframe 0直後に多数のキャッシュ欠損が発生したため128フレームへ戻した。
  - ディスク上限は既存 `VideoFrameCacheMB` の4倍とし、現在の既定1,024MB設定では4GB。最終利用時刻によるLRUで古いファイルを削除する。
- キャッシュ一致条件:
  - 正規化した絶対パス。
  - 元ファイルサイズとWindowsの最終更新時刻。
  - フレーム番号、幅、高さ、AviUtl2出力形式、映像バッファサイズ。
  - キャッシュ形式versionと保存データの64bitハッシュ。
- ファイルサイズまたは更新時刻が変われば別キーになり、古いフレームは使用しない。
- 既存のメモリフレームキャッシュとメタデータキャッシュにもサイズ・更新時刻の一致判定を追加した。
- `VideoFrameCacheMB=0` の場合は永続キャッシュの読み書きも無効にする。
- 独立プロセスによる `やってくる.mp4` の確認:
  - frame 0は通常QSVデコード約540.8ms、別プロセスの永続キャッシュ約11.1ms。
  - frame 1は通常QSVデコード約475.9ms、別プロセスの永続キャッシュ約10.0ms。
  - frame 1の通常デコード結果とキャッシュ結果はSHA-256が完全一致した。
  - Debugログは `route=persistent_cache` となり、キャッシュhit時はQSV decoderをopenしない。
- AviUtl2終了時のプロセス残留対策:
  - 旧LRU整理は1ファイル削除するたびに全キャッシュを再走査しており、4GB到達後の終了を長引かせる可能性があった。
  - キャッシュ一覧を1回だけ走査して最終利用時刻順へ並べ、古いものをまとめて削除する方式へ変更した。
  - 最後の入力handleをcloseした時点で終了フラグを立て、LRU整理を途中中断して書き込みスレッドを停止・回収する。
  - 4GB超のキャッシュを持つ独立プロセスで未キャッシュframeをQSVデコード後、close約31～45msで終了し、プロセスが残留しないことを確認した。

## 2026-06-17 ProRes 4444 alpha 入力の初期対応

背景:

- `VW_Media_Output` 側で、透過保持用に `MOV / ProRes 4444 / PA64 -> yuva444p10le` の専用出力モードを追加した。
- Windows標準メディアプレーヤーでは ProRes 4444 alpha MOV を再生できないことがあるため、確認は `VW_Media_Input` でAviUtl2へ読み戻して行う必要がある。
- 通常素材の高速な `YUY2` 入力経路は維持し、alpha がありそうな素材だけ別の映像出力形式へ切り替える。

方針:

- FFmpeg の `AVCodecParameters.format` から pixel format 名を取得する。
- `yuva*` / `rgba` / `bgra` / `argb` / `abgr` / `gbrap*` / `ya*` を alpha あり候補として扱う。
- alpha あり候補のファイルだけ、AviUtl2へ `RGBA32` 相当として返す。
  - `BITMAPINFOHEADER.biBitCount = 32`
  - `BITMAPINFOHEADER.biCompression = BI_RGB`
  - デコードフレームは既存の `AV_PIX_FMT_BGRA` 変換経路を使う。
- alpha なし素材は従来どおり `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YUY2` のまま。

変更内容:

- `Plugin_Input\FFmpegApi.pas`
  - `av_get_pix_fmt_name` を追加。
  - `PixelFormatName` を追加。
- `Plugin_Input\FFmpegDecoderTypes.pas`
  - `TVideoInfo` に `PixelFormat` / `PixelFormatName` / `HasAlpha` を追加。
- `Plugin_Input\FFmpegDecoder.pas`
  - open時に pixel format 名と alpha 候補を判定。
  - Debugログ `video_decoder` に `pix_fmt="..." alpha=True/False` を追加。
- `Plugin_Input\PluginInputBase.pas`
  - ファイル単位の `VideoOutputFormat` を追加。
  - `VideoInfo.HasAlpha=True` のときだけ `VIDEO_OUTPUT_RGBA32` へ切り替える。
  - 通常素材は従来の `YUY2` 経路を維持する。
  - Debugログ `open ok` に `pix_fmt` / `alpha` / `output_format` を追加。

確認:

- Win64 Debug Build 成功。
  - 警告 2、エラー 0。
  - 既存のヒント系警告のみ。
  - post-buildで `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` へコピー成功。
- Win64 Release Build 成功。
  - 警告 1、エラー 0。
  - 既存の未使用 private method ヒントのみ。
  - post-buildで `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` へコピー成功。

次の実機確認:

- `VW_Media_Output` の `Alpha MOV / ProRes 4444` で出した `.mov` を AviUtl2 へ読み込む。
- `%TEMP%\VW_Media_Input_decode.log` で以下を確認する。
  - `pix_fmt="yuva..."` または alpha 付き形式になっているか。
  - `alpha=True` になっているか。
  - `output_format=5` になっているか。
- AviUtl2 上で背景を敷いて、透過部分が黒塗りではなく抜けて見えるか確認する。
- もし alpha が落ちる場合は、AviUtl2 が `BI_RGB 32bit` を alpha 付きとして扱っていない可能性があるため、次は `PA64` 入力返却への切り替えを検討する。

## 2026-08-09 重いMP4調査用Debugログ

特定のMP4だけ読み込み負荷が大きい原因を切り分けるため、Debugビルドのログを段階別に強化した。

追加した計測:

- ファイルopen
  - `api_load_ms`: FFmpeg DLLロード
  - `format_open_ms`: コンテナopen
  - `stream_info_ms`: ストリーム解析
  - `video_decoder_ms`: QSV/ソフトウェア映像デコーダ初期化
  - `audio_decoder_ms`: 音声デコーダ初期化
  - `audio_reader_open_ms`: AviUtl2音声読み取り専用デコーダの追加open
- 映像フレーム
  - `seek_ms`: `av_seek_frame`
  - `read_ms`: `av_read_frame`の累計
  - `decode_ms`: packet送信とframe受信
  - `transfer_ms`: QSV HW frameからCPUへの転送
  - `convert_ms`: YUY2/BGRx32への色変換
  - 16ms以上では最大の段階を`stage="seek|read|decode|transfer|convert|total"`として記録
- 音声
  - `decoded_before` / `decoded_after` / `decoded_added`: PCM追加デコード量
  - `pcm_bytes`: PCMキャッシュの使用バイト数
  - `cache_hit` / `finished` / `elapsed_ms` / `slow`

ログファイル:

```text
%TEMP%\VW_Media_Input_decode.log
```

主に確認する行:

- `open_summary`
- `open ok`
- `next_decode_yuy2_slow` / `seek_decode_yuy2_slow`
- `next_decode_slow` / `seek_decode_slow`
- `read_audio` / `read_audio_failed`
- `read_video_slow`
- `close_summary`

音声は要求位置まで先頭からPCMキャッシュを伸ばすため、長いMP4の途中を最初に要求した場合は
`decoded_added`、`pcm_bytes`、`elapsed_ms`が大きくなる可能性がある。

ビルド確認:

- Win64 Debug Build成功。警告1、エラー0。
- Win64 Release Build成功。警告1、エラー0。
- 最後にDebug版を再ビルドし、AviUtl2プラグインフォルダへ配置済み。

## 2026-08-09 2回目再生用のファイル別フレームキャッシュ

途中位置から2回目の再生を始めると、各MP4が`last_decoded=-1`の状態で途中フレームを要求され、
長いGOPを先頭側から再デコードしていた。従来の共有キャッシュは全素材合計16枚だけだったため、
1回目にAviUtl2へ返した正確なフレームが素材切り替えでほぼ消えていた。

変更内容:

- 共有16枚LRUを、ファイル別枚数を管理する可変キャッシュへ変更した。
- 1ファイルあたり最大64フレームを保持する。
- キャッシュ全体は既定1024MBまでとする。
- 全体上限へ達した場合は、最も多くフレームを持つファイルから古いフレームを破棄する。
  - 一つの素材が全キャッシュを独占せず、複数MP4のフレームを残すための方針。
- キャッシュにはAviUtl2へ実際に返した完成済みバッファを保存する。
  - 近似シークではなく、frame番号が完全一致した場合だけ`route=shared_cache`で返す。
  - キャッシュヒット時もデコーダ位置を偽って更新しない。
- Debugの`close_summary`へ以下を追加した。
  - `cache_file_frames`: 対象ファイルの保持枚数
  - `cache_total_mb`: 全ファイル合計の使用量
  - `cache_limit_mb`: 設定上限

キャッシュ上限は`.aui2`と同じ場所の`VW_Media_Input.ini`で手動変更できる。

```ini
[VW_Media_Input]
VideoFrameCacheMB=1024
```

- `0`: 共有フレームキャッシュを無効化
- 最大: `4096`MB
- 設定画面UIへの項目追加は未実施。

ビルド確認:

- Win64 Debug / ReleaseともBuild成功。警告1、エラー0。
- 最後にDebug版を再ビルドし、AviUtl2プラグインフォルダへ配置済み。
- 次の実機確認では1回目再生後の2回目途中再生で、`route=shared_cache`と
  close時キャッシュ統計を確認する。

## コメント記述ルール

基本方針:

- コメントは、処理を読めば分かることをなぞるのではなく、目的、責務、注意点、状態の意味を補うために書く。
- 古い仕様や現在の実装と食い違うコメントは、見つけた時点で更新する。
- 不要なコメントや重複したコメントを増やしすぎない。
- `var` ブロック内にローカル関数やローカル手続きを内包しない。
  - 補助処理が必要な場合は、同じ `implementation` 内の独立した関数/手続きとして切り出す。
  - この形を見つけた場合は、コメント追加だけで済ませず構造も直す。

ユニット先頭:

- 各ユニットの先頭には、そのユニットの目的や担当範囲を `//` コメントで記述する。
- 依存関係や「ここには書かない処理」が重要な場合は、その注意も先頭コメントに含める。

フィールド:

- フィールドの意味は、フィールド宣言の右側に 1 行コメントとして `//` で書く。
- 同じブロック内では、フィールド名の後ろに置く型区切りの `:` の X 座標を揃える。
- 同じブロック内では、`//` の X 座標を揃える。
- コメント本文の先頭に `file:` や `playback:` のような分類ラベルは付けない。
- コメント本文は、そのフィールド単体の意味を自然な日本語で書く。
- 同じクラス内で長い共通接頭辞を持つフィールドが並び、コメントや整列を読みにくくしている場合は、接頭辞を削ってよい。
  - 例: `FAutoCheckDarkStartMs` は、自動チェック専用 manager 内なら `FDarkStartMs` にしてよい。
  - ただし `property ... read/write ...` で外部公開名と対応している backing field は、無理に短縮しない。
  - この程度のフィールド名変更が必要なら、コメントだけで済ませずコードも追従する。
- 例:

```pascal
FVideoFile      : string;  // 現在開いている動画ファイル
FSeekPositionMs : Integer; // UI 側で保持する現在位置 ms
FSeekMaxMs      : Integer; // シーク可能な最大位置 ms
```

定数:

- 定数の意味は、定数宣言の右側に 1 行コメントとして `//` で書く。
- 同じ `const` ブロック内では、`=` の X 座標を揃える。
- 同じ `const` ブロック内では、`//` の X 座標を揃える。
- コメント本文は、その定数が判定や処理で何の基準になるかを自然な日本語で書く。
- 同じユニット内だけで使う定数は、長い共通接頭辞やユニット内の文脈で明らかな語を削ってよい。
  - 例: 自動チェック専用 manager 内なら `AUTO_CHECK_AUDIO_SILENCE_PEAK` は `SILENCE_PEAK` にしてよい。
  - 外部公開される定数や、他ユニットから参照される可能性がある定数では、意味が衝突しない名前を優先する。
  - この程度の定数名変更が必要なら、コメントだけで済ませずコードも追従する。
- 例:

```pascal
VIDEO_AUDIO_SYNC_LAG_MS       = 60;   // 音声同期のためにフレーム破棄を検討する遅れ幅 ms
VIDEO_DEFAULT_FRAME_DURATION  = 33;   // FPS 不明時に使う既定フレーム長 ms
VIDEO_END_TOLERANCE_MS        = 1500; // 終端付近として扱う残り時間 ms
```

プロパティ:

- `property` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。
- 112 文字を超える場合だけ、既存の Delphi コードの読みやすい位置で折り返す。

メソッド:

- メソッドの意味は、メソッド宣言または実装の上に 1 行コメントとして書く。
- `procedure` / `function` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。
- 112 文字を超える場合だけ、既存の Delphi コードの読みやすい位置で折り返す。
- 引数の意味が複雑な場合は、複数行コメントにしてよい。
- コメントと対象メソッドの間に空行は入れない。
- 例:

```pascal
// 指定位置へシークし、必要なら再生状態を復元する
procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
```

複雑な引数がある場合:

```pascal
// フレームを表示用 BGRX32 バッファへ直接デコードする
// Buffer       : 出力先バッファ先頭
// BufferStride : 1 行あたりのバイト数
function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
  out BufferStride: Integer; out ErrorMessage: string): Boolean;
```

空行:

- コメントと対象の宣言/実装の間には空行を入れない。
- コメントブロック内でも、意味の切れ目が明確に必要な場合以外は空行を入れない。

