library VW_Media_Input;

uses
  Winapi.Windows,
  System.SysUtils,
  PluginInputBase in 'Plugin_Input\PluginInputBase.pas',
  AviUtl2InputTypes in 'AviUtl\Input\AviUtl2InputTypes.pas',
  FFmpegApi in 'Plugin_Input\FFmpegApi.pas',
  FFmpegDecoderContext in 'Plugin_Input\FFmpegDecoderContext.pas',
  FFmpegDecoderTypes in 'Plugin_Input\FFmpegDecoderTypes.pas',
  FFmpegAudioConvert in 'Plugin_Input\FFmpegAudioConvert.pas',
  FFmpegAudioOpen in 'Plugin_Input\FFmpegAudioOpen.pas',
  FFmpegDecoderAudioPlayback in 'Plugin_Input\FFmpegDecoderAudioPlayback.pas',
  FFmpegDecoderAudioRead in 'Plugin_Input\FFmpegDecoderAudioRead.pas',
  FFmpegDecodeStats in 'Plugin_Input\FFmpegDecodeStats.pas',
  FFmpegDecoderNextBgr24 in 'Plugin_Input\FFmpegDecoderNextBgr24.pas',
  FFmpegDecoderNextBgrx32 in 'Plugin_Input\FFmpegDecoderNextBgrx32.pas',
  FFmpegDecoderNextI420 in 'Plugin_Input\FFmpegDecoderNextI420.pas',
  FFmpegDecoderNextYuy2 in 'Plugin_Input\FFmpegDecoderNextYuy2.pas',
  FFmpegDecoderNextYc48 in 'Plugin_Input\FFmpegDecoderNextYc48.pas',
  FFmpegDecoderResources in 'Plugin_Input\FFmpegDecoderResources.pas',
  FFmpegDecoderSeekBgr24 in 'Plugin_Input\FFmpegDecoderSeekBgr24.pas',
  FFmpegDecoderSeekBgrx32 in 'Plugin_Input\FFmpegDecoderSeekBgrx32.pas',
  FFmpegDecoderSeekI420 in 'Plugin_Input\FFmpegDecoderSeekI420.pas',
  FFmpegDecoderSeekYuy2 in 'Plugin_Input\FFmpegDecoderSeekYuy2.pas',
  FFmpegDecoderSeekYc48 in 'Plugin_Input\FFmpegDecoderSeekYc48.pas',
  FFmpegFrameConvert in 'Plugin_Input\FFmpegFrameConvert.pas',
  FFmpegQsvDecode in 'Plugin_Input\FFmpegQsvDecode.pas',
  FFmpegStreamInfo in 'Plugin_Input\FFmpegStreamInfo.pas',
  FFmpegDecoder in 'Plugin_Input\FFmpegDecoder.pas',
  PluginAudioInputReader in 'Plugin_Input\PluginAudioInputReader.pas';

//------------------------------------------------------------------------------
// ファイルを開く
//------------------------------------------------------------------------------
function func_open(fileName: LPCWSTR): INPUT_HANDLE; cdecl;
begin
  Result := PluginInputOpen(fileName);
end;

//------------------------------------------------------------------------------
// ファイルを閉じる
//------------------------------------------------------------------------------
function func_close(ih: INPUT_HANDLE): BOOL; cdecl;
begin
  Result := PluginInputClose(ih);
end;

//------------------------------------------------------------------------------
// 情報取得
//------------------------------------------------------------------------------
function func_info_get(ih: INPUT_HANDLE; info: PInputInfo): BOOL; cdecl;
begin
  Result := PluginInputGetInfo(ih,info);
end;

//------------------------------------------------------------------------------
// フレーム読み込み（共有メモリの内容を反映してから描画）
//------------------------------------------------------------------------------
function func_read_video(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer; cdecl;
begin
  Result := PluginInputReadVideo(ih,frame,buf);
end;

//------------------------------------------------------------------------------
// 音声
//------------------------------------------------------------------------------
function func_read_audio(ih: INPUT_HANDLE; start, length: Integer; buf: Pointer): Integer; cdecl;
begin
  Result := PluginInputReadAudio(ih,start,length,buf);
end;

//------------------------------------------------------------------------------
// 設定ダイアログ（確認用）
//------------------------------------------------------------------------------
function func_config(hwnd: HWND; hinst: HINST): BOOL; cdecl;
begin
  Result := PluginInputConfig(hwnd,hinst);
end;

//------------------------------------------------------------------------------
// プラグインテーブル
//------------------------------------------------------------------------------
const
  MEDIA_FILE_FILTER_WITH_WAV =
    'Media files (*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.asf;*.webm;*.mpg;*.mpeg;*.m2ts;*.ts;*.m4v;*.mp3;*.wav;*.m4a;*.aac;*.wma;*.flac;*.ogg;*.opus)'#0 +
    '*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.asf;*.webm;*.mpg;*.mpeg;*.m2ts;*.ts;*.m4v;*.mp3;*.wav;*.m4a;*.aac;*.wma;*.flac;*.ogg;*.opus'#0;
  MEDIA_FILE_FILTER_WITHOUT_WAV =
    'Media files (*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.asf;*.webm;*.mpg;*.mpeg;*.m2ts;*.ts;*.m4v;*.mp3;*.m4a;*.aac;*.wma;*.flac;*.ogg;*.opus)'#0 +
    '*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.asf;*.webm;*.mpg;*.mpeg;*.m2ts;*.ts;*.m4v;*.mp3;*.m4a;*.aac;*.wma;*.flac;*.ogg;*.opus'#0;

  // wav は AviUtl2 標準入力で扱える可能性が高い。
  // FFmpeg 経由で読ませたい場合は WITH_WAV、標準入力へ任せたい場合は WITHOUT_WAV に切り替える。
  MEDIA_FILE_FILTER = MEDIA_FILE_FILTER_WITH_WAV;
  //MEDIA_FILE_FILTER = MEDIA_FILE_FILTER_WITHOUT_WAV;

var
  Plugin: TInputPluginTable = (
    flag: INPUT_PLUGIN_FLAG_VIDEO or INPUT_PLUGIN_FLAG_AUDIO;
    name: '動画/音声入力';
    filefilter: MEDIA_FILE_FILTER;
    //filefilter: nil;
    information: '様々な動画/音声形式をAviUtl2上で扱うための軽量プラグイン';
    func_open: func_open;
    func_close: func_close;
    func_info_get: func_info_get;
    func_read_video: func_read_video;
    func_read_audio: func_read_audio;
    func_config: func_config;
    func_set_track: nil;
    func_time_to_frame: nil
  );

//------------------------------------------------------------------------------
function GetInputPluginTable: PInputPluginTable; cdecl;
begin
  Result := @Plugin;
end;

exports
  GetInputPluginTable name 'GetInputPluginTable';

begin
end.


