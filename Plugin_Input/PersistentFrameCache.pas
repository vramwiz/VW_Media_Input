unit PersistentFrameCache;

// AviUtl2へ返した正確な映像フレームをファイル同一性付きでディスクへ永続化する。
// 読み出しは呼び出しスレッドで行い、安定している初回再生を妨げないよう保存は専用スレッドで行う。

interface

type
  TPersistentFrameIdentity = record
    NormalizedPath : string; // 大文字小文字を無視して正規化した入力ファイルの絶対パス
    FileSize       : Int64;  // キャッシュ作成時の入力ファイルサイズ
    LastWriteTime  : Int64;  // キャッシュ作成時の入力ファイル最終更新時刻
  end;

// 入力ファイルのサイズと最終更新時刻を含むキャッシュ同一性を作る
function BuildPersistentFrameIdentity(const FileName: string;
  out Identity: TPersistentFrameIdentity): Boolean;
// 同一性と映像形式が一致する正確なフレームをディスクキャッシュから読む
function TryReadPersistentFrame(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize: Integer; Buffer: Pointer): Boolean;
// AviUtl2へ返した正確なフレームをバックグラウンド保存キューへ追加する
function QueuePersistentFrame(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize, MemoryCacheSizeMb: Integer;
  Buffer: Pointer): Boolean;
// 最後の入力handleを閉じる前に書き込みスレッドを安全に停止する
procedure StopPersistentFrameCacheWriter;

implementation

uses
  Winapi.Windows, System.Classes, System.Generics.Collections, System.SysUtils,
  System.SyncObjs;

const
  CACHE_MAGIC              = UInt64($3148434143464D56); // 永続フレームキャッシュを識別する値
  CACHE_VERSION            = 1;                         // キャッシュヘッダーの互換性番号
  CACHE_EXTENSION          = '.vfc';                    // 永続フレームキャッシュの拡張子
  CACHE_QUEUE_LIMIT        = 128;                       // 書き込み待ちで保持する最大フレーム数
  CACHE_CLEAN_INTERVAL     = 64;                        // LRU容量整理を行う書き込み間隔
  CACHE_DISK_MULTIPLIER    = 4;                         // メモリ設定値に対するディスク上限倍率

type
  TPersistentFrameHeader = packed record
    Magic          : UInt64;  // 永続キャッシュファイルの識別値
    Version        : Integer; // キャッシュ形式の互換性番号
    FileSize       : Int64;   // 元ファイルのサイズ
    LastWriteTime  : Int64;   // 元ファイルの最終更新時刻
    Frame          : Integer; // 元動画内の正確なフレーム番号
    Width          : Integer; // 出力映像の幅
    Height         : Integer; // 出力映像の高さ
    OutputFormat   : Integer; // AviUtl2へ返した映像形式
    ImageSize      : Integer; // 保存した映像バッファのbyte数
    PathByteLength : Integer; // 後続するUTF-8正規化パスのbyte数
    DataHash       : UInt64;  // 映像バッファ破損検出用ハッシュ
  end;

  TPersistentWriteItem = record
    Identity     : TPersistentFrameIdentity; // 保存元ファイルの同一性
    Frame        : Integer;                  // 保存するフレーム番号
    Width        : Integer;                  // 保存する映像幅
    Height       : Integer;                  // 保存する映像高さ
    OutputFormat : Integer;                  // 保存する出力映像形式
    Data         : TBytes;                   // 保存する正確な映像バッファ
    MaxBytes     : Int64;                    // 保存後に適用するディスク容量上限
  end;

  TPersistentCacheFileInfo = record
    FileName      : string; // 容量整理で削除候補にするキャッシュファイル
    FileSize      : Int64;  // キャッシュファイルのbyte数
    LastWriteTime : Int64;  // LRU比較に使う最終利用時刻
  end;

  TPersistentCacheWriter = class(TThread)
  private
    FWriteCount : Integer; // 前回容量整理後に書いたフレーム数
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

var
  CacheFileLock     : TCriticalSection;             // キャッシュファイルの読み書きを直列化するロック
  WriteQueue        : TQueue<TPersistentWriteItem>; // バックグラウンド書き込み待ちフレーム
  WriteQueueLock    : TCriticalSection;             // 書き込みキューを保護するロック
  WriteEvent        : TEvent;                       // 書き込みスレッドを起床させるイベント
  CacheWriter       : TPersistentCacheWriter;       // 遅延作成する書き込みスレッド
  CacheShutdownFlag : Integer;                      // DLL解放前の書き込み停止要求

// キャッシュ書き込みの終了要求が出ているかを返す
function CacheShutdownRequested: Boolean;
begin
  Result := InterlockedCompareExchange(CacheShutdownFlag, 0, 0) <> 0;
end;

// 永続キャッシュを保存するユーザー別ディレクトリを返す
function PersistentCacheDirectory: string;
var
  BaseDirectory: string;
begin
  BaseDirectory := GetEnvironmentVariable('LOCALAPPDATA');
  if BaseDirectory = '' then
    BaseDirectory := GetEnvironmentVariable('TEMP');
  Result := IncludeTrailingPathDelimiter(BaseDirectory) +
    'VW_Media_Input\FrameCache';
end;

// 入力バイト列からキャッシュ名と破損検出に使う64bitハッシュを作る
{$Q-}
{$R-}
function HashBuffer64(Buffer: Pointer; ByteCount: Integer): UInt64;
const
  FNV_OFFSET = UInt64(14695981039346656037); // FNV-1a 64bitの初期値
  FNV_PRIME  = UInt64(1099511628211);        // FNV-1a 64bitの乗数
var
  I: Integer;
  P: PByte;
begin
  Result := FNV_OFFSET;
  if (Buffer = nil) or (ByteCount <= 0) then
    Exit;
  P := PByte(Buffer);
  for I := 0 to ByteCount - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * FNV_PRIME;
  end;
end;
{$Q+}
{$R+}

// キャッシュ対象を一意に表す文字列を作る
function PersistentFrameKeyText(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize: Integer): UTF8String;
begin
  Result := UTF8String(Identity.NormalizedPath + '|' +
    IntToStr(Identity.FileSize) + '|' + IntToStr(Identity.LastWriteTime) + '|' +
    IntToStr(Frame) + '|' + IntToStr(Width) + '|' + IntToStr(Height) + '|' +
    IntToStr(OutputFormat) + '|' + IntToStr(ImageSize));
end;

// キャッシュ対象に対応する永続キャッシュファイル名を返す
function PersistentFrameFileName(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize: Integer): string;
var
  KeyText: UTF8String;
  KeyHash: UInt64;
begin
  KeyText := PersistentFrameKeyText(Identity, Frame, Width, Height,
    OutputFormat, ImageSize);
  if Length(KeyText) > 0 then
    KeyHash := HashBuffer64(@KeyText[1], Length(KeyText))
  else
    KeyHash := HashBuffer64(nil, 0);
  Result := IncludeTrailingPathDelimiter(PersistentCacheDirectory) +
    IntToHex(KeyHash, 16) + CACHE_EXTENSION;
end;

// Windowsのファイル属性から更新時刻を比較用Int64へ変換する
function FileTimeToIdentityValue(const Value: TFileTime): Int64;
var
  RawValue: UInt64;
begin
  RawValue := UInt64(Value.dwLowDateTime) or
    (UInt64(Value.dwHighDateTime) shl 32);
  Result := Int64(RawValue);
end;

// 入力ファイルのサイズと最終更新時刻を含むキャッシュ同一性を作る
function BuildPersistentFrameIdentity(const FileName: string;
  out Identity: TPersistentFrameIdentity): Boolean;
var
  Attributes: WIN32_FILE_ATTRIBUTE_DATA;
begin
  Identity.NormalizedPath := '';
  Identity.FileSize := 0;
  Identity.LastWriteTime := 0;
  Result := GetFileAttributesEx(PChar(FileName), GetFileExInfoStandard,
    @Attributes);
  if not Result then
    Exit;
  Identity.NormalizedPath := LowerCase(ExpandFileName(FileName));
  Identity.FileSize := Int64(UInt64(Attributes.nFileSizeLow) or
    (UInt64(Attributes.nFileSizeHigh) shl 32));
  Identity.LastWriteTime := FileTimeToIdentityValue(Attributes.ftLastWriteTime);
end;

// LRU判定のためキャッシュファイルの最終更新時刻を現在時刻へ進める
procedure TouchCacheFile(const FileName: string);
var
  FileHandle: THandle;
  CurrentTime: TFileTime;
begin
  FileHandle := CreateFile(PChar(FileName), FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    GetSystemTimeAsFileTime(CurrentTime);
    SetFileTime(FileHandle, nil, nil, @CurrentTime);
  finally
    CloseHandle(FileHandle);
  end;
end;

// 同一性と映像形式が一致する正確なフレームをディスクキャッシュから読む
function TryReadPersistentFrame(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize: Integer; Buffer: Pointer): Boolean;
var
  CacheFileName: string;
  CacheStream: TFileStream;
  Header: TPersistentFrameHeader;
  StoredPath: UTF8String;
  ExpectedSize: Int64;
begin
  Result := False;
  if (Identity.NormalizedPath = '') or (Buffer = nil) or (ImageSize <= 0) then
    Exit;
  CacheFileName := PersistentFrameFileName(Identity, Frame, Width, Height,
    OutputFormat, ImageSize);
  if not FileExists(CacheFileName) then
    Exit;

  CacheFileLock.Enter;
  try
    try
      CacheStream := TFileStream.Create(CacheFileName, fmOpenRead or fmShareDenyWrite);
      try
        if CacheStream.Size < SizeOf(Header) then
          Exit;
        CacheStream.ReadBuffer(Header, SizeOf(Header));
        if (Header.Magic <> CACHE_MAGIC) or
           (Header.Version <> CACHE_VERSION) or
           (Header.FileSize <> Identity.FileSize) or
           (Header.LastWriteTime <> Identity.LastWriteTime) or
           (Header.Frame <> Frame) or (Header.Width <> Width) or
           (Header.Height <> Height) or (Header.OutputFormat <> OutputFormat) or
           (Header.ImageSize <> ImageSize) or
           (Header.PathByteLength <= 0) or (Header.PathByteLength > 32768) then
          Exit;
        ExpectedSize := SizeOf(Header) + Header.PathByteLength + Int64(ImageSize);
        if CacheStream.Size <> ExpectedSize then
          Exit;
        SetLength(StoredPath, Header.PathByteLength);
        CacheStream.ReadBuffer(StoredPath[1], Header.PathByteLength);
        if string(StoredPath) <> Identity.NormalizedPath then
          Exit;
        CacheStream.ReadBuffer(Buffer^, ImageSize);
        if HashBuffer64(Buffer, ImageSize) <> Header.DataHash then
          Exit;
        Result := True;
      finally
        CacheStream.Free;
      end;
      if Result then
        TouchCacheFile(CacheFileName);
    except
      Result := False;
    end;
    if not Result then
      DeleteFile(CacheFileName);
  finally
    CacheFileLock.Leave;
  end;
end;

// 指定フレームを一時ファイル経由で永続キャッシュへ保存する
procedure WritePersistentFrame(const Item: TPersistentWriteItem);
var
  CacheDirectory: string;
  CacheFileName: string;
  TemporaryFileName: string;
  CacheStream: TFileStream;
  Header: TPersistentFrameHeader;
  StoredPath: UTF8String;
begin
  if Length(Item.Data) = 0 then
    Exit;
  CacheDirectory := PersistentCacheDirectory;
  ForceDirectories(CacheDirectory);
  CacheFileName := PersistentFrameFileName(Item.Identity, Item.Frame,
    Item.Width, Item.Height, Item.OutputFormat, Length(Item.Data));
  if FileExists(CacheFileName) then
    Exit;
  TemporaryFileName := CacheFileName + '.' + IntToHex(GetCurrentThreadId, 8) + '.tmp';

  FillChar(Header, SizeOf(Header), 0);
  StoredPath := UTF8String(Item.Identity.NormalizedPath);
  Header.Magic := CACHE_MAGIC;
  Header.Version := CACHE_VERSION;
  Header.FileSize := Item.Identity.FileSize;
  Header.LastWriteTime := Item.Identity.LastWriteTime;
  Header.Frame := Item.Frame;
  Header.Width := Item.Width;
  Header.Height := Item.Height;
  Header.OutputFormat := Item.OutputFormat;
  Header.ImageSize := Length(Item.Data);
  Header.PathByteLength := Length(StoredPath);
  Header.DataHash := HashBuffer64(@Item.Data[0], Length(Item.Data));

  CacheFileLock.Enter;
  try
    try
      CacheStream := TFileStream.Create(TemporaryFileName, fmCreate);
      try
        CacheStream.WriteBuffer(Header, SizeOf(Header));
        if Length(StoredPath) > 0 then
          CacheStream.WriteBuffer(StoredPath[1], Length(StoredPath));
        CacheStream.WriteBuffer(Item.Data[0], Length(Item.Data));
      finally
        CacheStream.Free;
      end;
      if FileExists(CacheFileName) then
        DeleteFile(TemporaryFileName)
      else
        RenameFile(TemporaryFileName, CacheFileName);
    except
      DeleteFile(TemporaryFileName);
    end;
  finally
    CacheFileLock.Leave;
  end;
end;

// LRU削除用のキャッシュ一覧を最終利用時刻の古い順へ並べる
procedure SortCacheFilesByWriteTime(var Files: array of TPersistentCacheFileInfo;
  LeftIndex, RightIndex: Integer);
var
  LeftCursor  : Integer;                  // 左から比較する配列位置
  RightCursor : Integer;                  // 右から比較する配列位置
  Pivot       : Int64;                    // 分割基準にする最終利用時刻
  Temporary   : TPersistentCacheFileInfo; // 要素交換に使う一時値
begin
  LeftCursor := LeftIndex;
  RightCursor := RightIndex;
  Pivot := Files[(LeftIndex + RightIndex) div 2].LastWriteTime;
  repeat
    while Files[LeftCursor].LastWriteTime < Pivot do
      Inc(LeftCursor);
    while Files[RightCursor].LastWriteTime > Pivot do
      Dec(RightCursor);
    if LeftCursor <= RightCursor then
    begin
      Temporary := Files[LeftCursor];
      Files[LeftCursor] := Files[RightCursor];
      Files[RightCursor] := Temporary;
      Inc(LeftCursor);
      Dec(RightCursor);
    end;
  until LeftCursor > RightCursor;
  if LeftIndex < RightCursor then
    SortCacheFilesByWriteTime(Files, LeftIndex, RightCursor);
  if LeftCursor < RightIndex then
    SortCacheFilesByWriteTime(Files, LeftCursor, RightIndex);
end;

// ディスク使用量が上限以下になるまで最終利用時刻が古いキャッシュを削除する
procedure TrimPersistentCache(MaxBytes: Int64);
var
  SearchResult    : TSearchRec;                   // キャッシュディレクトリの列挙結果
  SearchPath      : string;                       // 列挙に使うvfcファイルパターン
  CacheFileName   : string;                       // 列挙中のキャッシュファイル名
  TotalBytes      : Int64;                        // 列挙したキャッシュの合計byte数
  Attributes      : WIN32_FILE_ATTRIBUTE_DATA;    // 最終利用時刻を含むファイル属性
  CacheFiles      : array of TPersistentCacheFileInfo; // 1回の走査で集める削除候補
  CacheFileCount  : Integer;                      // 削除候補配列に格納した件数
  CacheFileIndex  : Integer;                      // 古い順に削除する配列位置
begin
  if (MaxBytes <= 0) or CacheShutdownRequested then
    Exit;
  SearchPath := IncludeTrailingPathDelimiter(PersistentCacheDirectory) +
    '*' + CACHE_EXTENSION;
  TotalBytes := 0;
  CacheFileCount := 0;
  if FindFirst(SearchPath, faAnyFile, SearchResult) <> 0 then
    Exit;
  try
    repeat
      if CacheShutdownRequested then
        Exit;
      if (SearchResult.Attr and faDirectory) = 0 then
      begin
        CacheFileName := IncludeTrailingPathDelimiter(PersistentCacheDirectory) +
          SearchResult.Name;
        if CacheFileCount >= Length(CacheFiles) then
          SetLength(CacheFiles, CacheFileCount + 256);
        CacheFiles[CacheFileCount].FileName := CacheFileName;
        CacheFiles[CacheFileCount].FileSize := SearchResult.Size;
        if GetFileAttributesEx(PChar(CacheFileName), GetFileExInfoStandard,
          @Attributes) then
          CacheFiles[CacheFileCount].LastWriteTime :=
            FileTimeToIdentityValue(Attributes.ftLastWriteTime)
        else
          CacheFiles[CacheFileCount].LastWriteTime := 0;
        TotalBytes := TotalBytes + SearchResult.Size;
        Inc(CacheFileCount);
      end;
    until FindNext(SearchResult) <> 0;
  finally
    FindClose(SearchResult);
  end;

  if (TotalBytes <= MaxBytes) or (CacheFileCount = 0) or
    CacheShutdownRequested then
    Exit;
  SetLength(CacheFiles, CacheFileCount);
  if CacheFileCount > 1 then
    SortCacheFilesByWriteTime(CacheFiles, 0, CacheFileCount - 1);
  for CacheFileIndex := 0 to CacheFileCount - 1 do
  begin
    if (TotalBytes <= MaxBytes) or CacheShutdownRequested then
      Exit;
    CacheFileLock.Enter;
    try
      if DeleteFile(CacheFiles[CacheFileIndex].FileName) then
        TotalBytes := TotalBytes - CacheFiles[CacheFileIndex].FileSize;
    finally
      CacheFileLock.Leave;
    end;
  end;
end;

// バックグラウンド書き込みスレッドを開始する
constructor TPersistentCacheWriter.Create;
begin
  FWriteCount := CACHE_CLEAN_INTERVAL - 1;
  inherited Create(False);
  FreeOnTerminate := False;
end;

// キューへ追加されたフレームを順番にディスクへ保存する
procedure TPersistentCacheWriter.Execute;
var
  Item: TPersistentWriteItem;
  HasItem: Boolean;
begin
  while (not Terminated) and (not CacheShutdownRequested) do
  begin
    WriteEvent.WaitFor(1000);
    repeat
      HasItem := False;
      WriteQueueLock.Enter;
      try
        if (not Terminated) and (not CacheShutdownRequested) and
          (WriteQueue.Count > 0) then
        begin
          Item := WriteQueue.Dequeue;
          HasItem := True;
        end;
        if WriteQueue.Count = 0 then
          WriteEvent.ResetEvent;
      finally
        WriteQueueLock.Leave;
      end;
      if not HasItem then
        Break;
      try
        WritePersistentFrame(Item);
      except
        // キャッシュ保存失敗は映像デコードを停止させず、次のフレームを処理する。
      end;
      Inc(FWriteCount);
      if FWriteCount >= CACHE_CLEAN_INTERVAL then
      begin
        try
          TrimPersistentCache(Item.MaxBytes);
        except
          // 容量整理失敗時も既存キャッシュと映像デコードは継続する。
        end;
        FWriteCount := 0;
      end;
      Item.Data := nil;
    until Terminated or CacheShutdownRequested;
  end;
end;

// AviUtl2へ返した正確なフレームをバックグラウンド保存キューへ追加する
function QueuePersistentFrame(const Identity: TPersistentFrameIdentity;
  Frame, Width, Height, OutputFormat, ImageSize, MemoryCacheSizeMb: Integer;
  Buffer: Pointer): Boolean;
var
  Item: TPersistentWriteItem;
begin
  Result := False;
  if (Identity.NormalizedPath = '') or (Buffer = nil) or (ImageSize <= 0) or
     (MemoryCacheSizeMb <= 0) or CacheShutdownRequested then
    Exit;
  if FileExists(PersistentFrameFileName(Identity, Frame, Width, Height,
    OutputFormat, ImageSize)) then
    Exit;

  Item.Identity := Identity;
  Item.Frame := Frame;
  Item.Width := Width;
  Item.Height := Height;
  Item.OutputFormat := OutputFormat;
  Item.MaxBytes := Int64(MemoryCacheSizeMb) * CACHE_DISK_MULTIPLIER * 1024 * 1024;
  SetLength(Item.Data, ImageSize);
  Move(Buffer^, Item.Data[0], ImageSize);

  WriteQueueLock.Enter;
  try
    if CacheShutdownRequested or (WriteQueue.Count >= CACHE_QUEUE_LIMIT) then
      Exit;
    if CacheWriter = nil then
      CacheWriter := TPersistentCacheWriter.Create;
    WriteQueue.Enqueue(Item);
    Result := True;
    WriteEvent.SetEvent;
  finally
    WriteQueueLock.Leave;
  end;
end;

// 最後の入力handleを閉じる前に書き込みスレッドを安全に停止する
procedure StopPersistentFrameCacheWriter;
var
  Writer: TPersistentCacheWriter;
begin
  InterlockedExchange(CacheShutdownFlag, 1);
  WriteQueueLock.Enter;
  try
    Writer := CacheWriter;
    if Writer <> nil then
      Writer.Terminate;
    WriteEvent.SetEvent;
  finally
    WriteQueueLock.Leave;
  end;

  if Writer <> nil then
  begin
    Writer.WaitFor;
    WriteQueueLock.Enter;
    try
      if CacheWriter = Writer then
        CacheWriter := nil;
      WriteQueue.Clear;
    finally
      WriteQueueLock.Leave;
    end;
    Writer.Free;
  end;
  InterlockedExchange(CacheShutdownFlag, 0);
end;

initialization
  CacheFileLock := TCriticalSection.Create;
  WriteQueue := TQueue<TPersistentWriteItem>.Create;
  WriteQueueLock := TCriticalSection.Create;
  WriteEvent := TEvent.Create(nil, True, False, '');

finalization
  StopPersistentFrameCacheWriter;
  WriteEvent.Free;
  WriteQueueLock.Free;
  WriteQueue.Free;
  CacheFileLock.Free;

end.
