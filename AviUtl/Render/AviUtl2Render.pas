unit AviUtl2Render;

interface

uses
  Winapi.Windows,System.SysUtils,Vcl.Graphics,System.Types;

type
  // Aviutl2 Bitmap共通描画領域管理クラス
  TAviUtl2Render = class
  private
    FAviUtl2 : Boolean;             // True : AviUtl2用の描画
    function GetHeight: Integer;
    function GetWidth: Integer;
  protected
    FBitmap : TBitmap;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure LoadFromFile(const fileName : string);virtual;
    procedure Render(const Sec : Double);virtual;
    procedure Clear;

    property Bitmap :TBitmap read FBitmap;

    property Width  : Integer read GetWidth;
    property Height : Integer read GetHeight;
    property AviUtl2 : Boolean read FAviUtl2 write FAviUtl2;
  end;

const
  TRANSPARENT_KEY_COLOR : TColor = $010101;

implementation

constructor TAviUtl2Render.Create;
begin
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FBitmap.AlphaFormat := afDefined;
  FBitmap.SetSize(1920,1080);
end;

destructor TAviUtl2Render.Destroy;
begin
  FBitmap.Free;
  inherited;
end;



{ TAviUtl2Render }

  // 市松模様の背景を指定範囲に描画する（透過画像用の下地）
// 引数：
//   Canvas  - 描画先キャンバス
//   R       - 描画範囲（市松模様を敷き詰める領域）
//   CellSize - 1マスのサイズ（省略時は8ピクセル）
// 備考： 明るめ/暗めの2色を交互に配置し、透明領域の視認性を向上させる。
procedure FillCheckerBoard(Canvas: TCanvas; const R: TRect;
  CellSize: Integer);
var
  i, j: Integer;
  Color1, Color2: TColor;
  Cell: TRect;
begin
  Color1 := $CCCCCC;
  Color2 := $999999;
  for i := 0 to (R.Width div CellSize) do
    for j := 0 to (R.Height div CellSize) do
    begin
      Cell.Left := R.Left + i * CellSize;
      Cell.Top := R.Top + j * CellSize;
      Cell.Right := Cell.Left + CellSize;
      Cell.Bottom := Cell.Top + CellSize;

      if (i + j) mod 2 = 0 then
        Canvas.Brush.Color := Color1
      else
        Canvas.Brush.Color := Color2;
      Canvas.FillRect(Cell);
    end;
end;


procedure ClearBitmapTransparent(Bitmap: TBitmap);
var
  y: Integer;
begin
  Bitmap.PixelFormat := pf32bit;
  Bitmap.AlphaFormat := afDefined;

  for y := 0 to Bitmap.Height - 1 do
    FillChar(Bitmap.ScanLine[y]^, Bitmap.Width * 4, 0);
end;

procedure TAviUtl2Render.Clear;
begin
  FBitmap.Canvas.Lock;
  try
    if FAviUtl2 then begin
      // Alpha を 0 にする（pf32bit 前提）
      //ClearBitmapTransparent(FBitmap);
      FBitmap.Canvas.Brush.Style := bsSolid;
      FBitmap.Canvas.Brush.Color := TRANSPARENT_KEY_COLOR;
      FBitmap.Canvas.FillRect(Rect(0, 0, FBitmap.Width, FBitmap.Height));
     end
    else begin
      FBitmap.Canvas.Brush.Style := bsSolid;
      FBitmap.Canvas.Brush.Color := clBlack;
      FBitmap.Canvas.FillRect(Rect(0, 0, FBitmap.Width, FBitmap.Height));

      // Alpha を 0 にする（pf32bit 前提）
      //FBitmap.AlphaFormat := afDefined;
      //FillCheckerBoard(FBitmap.Canvas,Rect(0, 0, FBitmap.Width, FBitmap.Height),32);
    end;
  finally
    FBitmap.Canvas.Unlock;
  end;
end;

function TAviUtl2Render.GetHeight: Integer;
begin
  Result := FBitmap.Height;
end;

function TAviUtl2Render.GetWidth: Integer;
begin
 Result := FBitmap.Width;
end;

procedure TAviUtl2Render.LoadFromFile(const fileName : string);
begin

end;

procedure TAviUtl2Render.Render(const Sec : Double);
{
var
  R: TRect;
  S: string;
  }
begin
  // --- ① 完全クリア（透明） ---
  FBitmap.Canvas.Lock;
  try
  {
    // --- ② フレーム番号描画 ---
    S := IntToStr(Frame);

    FBitmap.Canvas.Font.Name := 'Segoe UI';
    FBitmap.Canvas.Font.Height := -48;   // px 指定
    FBitmap.Canvas.Font.Color := clWhite;

    R := Rect(0, 0, FBitmap.Width, FBitmap.Height);
    DrawText(
      FBitmap.Canvas.Handle,
      PChar(S),
      Length(S),
      R,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE
    );
    }
  finally
    FBitmap.Canvas.Unlock;
  end;
end;

end.
