library VW_Media_Input;

uses
  Winapi.Windows,
  System.SysUtils,
  PluginInputBase in 'Plugin_Input\PluginInputBase.pas',
  AviUtl2InputTypes in 'AviUtl\Input\AviUtl2InputTypes.pas',
  FFmpegApi in 'Plugin_Input\FFmpegApi.pas',
  FFmpegDecoderTypes in 'Plugin_Input\FFmpegDecoderTypes.pas',
  FFmpegAudioConvert in 'Plugin_Input\FFmpegAudioConvert.pas',
  FFmpegAudioOpen in 'Plugin_Input\FFmpegAudioOpen.pas',
  FFmpegDecodeStats in 'Plugin_Input\FFmpegDecodeStats.pas',
  FFmpegFrameConvert in 'Plugin_Input\FFmpegFrameConvert.pas',
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
var
  Plugin: TInputPluginTable = (
    flag: INPUT_PLUGIN_FLAG_VIDEO or INPUT_PLUGIN_FLAG_AUDIO;
    name: '動画入力';
    filefilter: 'Video files (*.mp4;*.mov;*.mkv;*.avi)'#0'*.mp4;*.mov;*.mkv;*.avi'#0;
    //filefilter: nil;
    information: '様々な動画形式をAviUtl2上で扱うための軽量プラグイン';
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


