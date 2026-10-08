#requires -Version 5.1
param(
  [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\CRIVO-DJ.ico'),
  [string]$PngOutput = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\CRIVO-DJ.png')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing

function New-OdtBitmap([int]$Size) {
  $bitmap=New-Object Drawing.Bitmap($Size,$Size)
  $g=[Drawing.Graphics]::FromImage($bitmap)
  $g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.TextRenderingHint=[Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.Clear([Drawing.Color]::FromArgb(180,176,168))
  $border=New-Object Drawing.Pen([Drawing.Color]::FromArgb(23,22,19),[Math]::Max(1,$Size*.028))
  $g.DrawRectangle($border,0,0,$Size-1,$Size-1)
  $border.Dispose()
  $fontSize=if($Size -le 20){[Math]::Max(8,$Size*.55)}else{[Math]::Max(14,$Size*.62)}
  $font=New-Object Drawing.Font('Arial Black',$fontSize,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
  $format=New-Object Drawing.StringFormat
  $format.Alignment=[Drawing.StringAlignment]::Center
  $format.LineAlignment=[Drawing.StringAlignment]::Center
  $accent=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(23,22,19))
  $g.FillRectangle($accent,0,0,$Size,[Math]::Max(2,$Size*.12));$accent.Dispose()
  $brush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(23,22,19))
  $g.DrawString('C',$font,$brush,[Drawing.RectangleF]::FromLTRB(0,$Size*.07,$Size,$Size),$format)
  $brush.Dispose();$format.Dispose();$font.Dispose();$g.Dispose()
  return $bitmap
}

$sizes=@(16,24,32,48,64,128,256)
$images=New-Object Collections.Generic.List[byte[]]
foreach($size in $sizes){
  $bitmap=New-OdtBitmap $size
  $stream=New-Object IO.MemoryStream
  $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
  $images.Add($stream.ToArray())
  $stream.Dispose();$bitmap.Dispose()
}
$file=[IO.File]::Create($Output);$writer=New-Object IO.BinaryWriter($file)
$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
$offset=6+16*$images.Count
for($i=0;$i -lt $images.Count;$i++){
  $size=$sizes[$i];$dimension=if($size -eq 256){[byte]0}else{[byte]$size}
  $writer.Write($dimension);$writer.Write($dimension);$writer.Write([byte]0);$writer.Write([byte]0)
  $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$images[$i].Length);$writer.Write([uint32]$offset)
  $offset+=$images[$i].Length
}
foreach($bytes in $images){$writer.Write($bytes)}
$writer.Dispose();$file.Dispose()
$large=New-OdtBitmap 256
$large.Save($PngOutput,[Drawing.Imaging.ImageFormat]::Png)
$large.Dispose()
