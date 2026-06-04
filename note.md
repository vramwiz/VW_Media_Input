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

