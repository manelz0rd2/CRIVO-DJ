#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if(-not $OutputPath){$OutputPath=Join-Path $root 'docs\media\crivo-dj-reel-vertical.mp4'}
$screenshots = Join-Path $root 'docs\screenshots'
$media = Split-Path -Parent $OutputPath
$frames = Join-Path $media 'reel-frames'
New-Item -ItemType Directory -Force -Path $media,$frames | Out-Null

$ink = [Drawing.Color]::FromArgb(23,22,19)
$paper = [Drawing.Color]::FromArgb(225,222,214)
$muted = [Drawing.Color]::FromArgb(180,176,168)
$line = [Drawing.Color]::FromArgb(92,88,81)
$signal = [Drawing.Color]::FromArgb(255,255,255)

function New-Font([float]$size,[Drawing.FontStyle]$style=[Drawing.FontStyle]::Regular) {
    [Drawing.Font]::new('Segoe UI',$size,$style,[Drawing.GraphicsUnit]::Pixel)
}

function Draw-CenteredText($graphics,[string]$text,$font,$brush,[float]$y,[float]$maxWidth=980) {
    $format = New-Object Drawing.StringFormat
    try {
        $format.Alignment = [Drawing.StringAlignment]::Center
        $format.LineAlignment = [Drawing.StringAlignment]::Near
        $graphics.DrawString($text,$font,$brush,[Drawing.RectangleF]::new([float]((1080-$maxWidth)/2),$y,$maxWidth,260),$format)
    } finally { $format.Dispose() }
}

function Draw-ImageFit($graphics,[string]$path,[Drawing.RectangleF]$box,[Drawing.RectangleF]$source) {
    $image = [Drawing.Image]::FromFile($path)
    try {
        if($source.Width -le 0){$source=[Drawing.RectangleF]::new(0,0,$image.Width,$image.Height)}
        $scale=[Math]::Min($box.Width/$source.Width,$box.Height/$source.Height)
        $width=$source.Width*$scale;$height=$source.Height*$scale
        $target=[Drawing.RectangleF]::new($box.X+(($box.Width-$width)/2),$box.Y+(($box.Height-$height)/2),$width,$height)
        $graphics.DrawImage($image,$target,$source,[Drawing.GraphicsUnit]::Pixel)
        $graphics.DrawRectangle((New-Object Drawing.Pen $line,3),[Drawing.Rectangle]::Round($target))
    } finally { $image.Dispose() }
}

function New-Slide {
    param([int]$Number,[string]$Title,[string]$Subtitle,[string]$Body,[string]$Screenshot,[Drawing.RectangleF]$Crop,[switch]$Final)
    $path=Join-Path $frames ('slide-{0:d2}.png' -f $Number)
    $bitmap=New-Object Drawing.Bitmap 1080,1920
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.Clear($ink)
        $paperBrush=New-Object Drawing.SolidBrush $paper
        $mutedBrush=New-Object Drawing.SolidBrush $muted
        $signalBrush=New-Object Drawing.SolidBrush $signal
        $rulePen=New-Object Drawing.Pen $line,3
        $brandFont=New-Font 28 ([Drawing.FontStyle]::Bold)
        $titleFont=New-Font ($(if($Final){82}else{64})) ([Drawing.FontStyle]::Bold)
        $subtitleFont=New-Font 31 ([Drawing.FontStyle]::Bold)
        $bodyFont=New-Font 30
        try {
            Draw-CenteredText $graphics 'CRIVO DJ por MANELZ0RD' $brandFont $mutedBrush 55 980
            $graphics.DrawLine($rulePen,50,112,1030,112)
            Draw-CenteredText $graphics $Title $titleFont $signalBrush 155 990
            if($Subtitle){Draw-CenteredText $graphics $Subtitle $subtitleFont $mutedBrush 350 950}
            if($Screenshot){
                Draw-ImageFit $graphics $Screenshot ([Drawing.RectangleF]::new(50,450,980,820)) $Crop
                Draw-CenteredText $graphics $Body $bodyFont $paperBrush 1340 920
            } else {
                $logo=Join-Path $root 'Assets\CRIVO-DJ.png'
                Draw-ImageFit $graphics $logo ([Drawing.RectangleF]::new(290,475,500,500)) ([Drawing.RectangleF]::Empty)
                Draw-CenteredText $graphics $Body $bodyFont $paperBrush 1080 900
            }
            Draw-CenteredText $graphics 'CURADORIA  •  REVISÃO  •  IDENTIFICAÇÃO  •  VALIDAÇÃO  •  ORGANIZAÇÃO' (New-Font 17 ([Drawing.FontStyle]::Bold)) $mutedBrush 1815 1000
            $bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $paperBrush.Dispose();$mutedBrush.Dispose();$signalBrush.Dispose();$rulePen.Dispose()
            $brandFont.Dispose();$titleFont.Dispose();$subtitleFont.Dispose();$bodyFont.Dispose()
        }
    } finally {$graphics.Dispose();$bitmap.Dispose()}
    $path
}

$download=Join-Path $screenshots '01-baixar-tracks.png'
$organize=Join-Path $screenshots '02-organizar-biblioteca.png'
$audit=Join-Path $screenshots '03-auditoria-rekordbox.png'

$slides=@(
    (New-Slide 1 'DO LINK AO REKORDBOX' 'UM WORKFLOW PARA SUA PESQUISA MUSICAL' 'Baixe, revise, organize e audite sem perder o controle dos arquivos.' $download ([Drawing.RectangleF]::Empty)),
    (New-Slide 2 'COLE UMA TRACK OU PLAYLIST' 'YOUTUBE  •  SOUNDCLOUD  •  SPOTIFY' 'Playlists viram tracks no grid. Cada música aparece com sua própria capa e progresso.' $download ([Drawing.RectangleF]::Empty)),
    (New-Slide 3 'ORGANIZE E REVISE' 'DADOS FALTANTES CONTINUAM SOB SEU CONTROLE' 'Defina a estrutura, confira o destino e acerte os metadados antes de aplicar.' $organize ([Drawing.RectangleF]::Empty)),
    (New-Slide 4 'PLAYLIST DIRETO NO REKORDBOX' 'COM BACKUP E VERIFICAÇÃO' 'As tracks organizadas podem entrar na coleção e na playlist escolhida pelo CRIVO.' $organize ([Drawing.RectangleF]::new(0,60,395,700))),
    (New-Slide 5 'ENCONTRE O QUE PRECISA DE ATENÇÃO' 'AUDITORIA DA BIBLIOTECA' 'Arquivos ausentes, qualidade suspeita, dados faltantes, análises e duplicatas em uma única visão.' $audit ([Drawing.RectangleF]::Empty)),
    (New-Slide 6 'CRIVO DJ' 'POR MANELZ0RD' "Baixe músicas. Organize sua pesquisa. Revise o Rekordbox.`n`nBeta para Windows." '' ([Drawing.RectangleF]::Empty) -Final)
)

$ffmpeg=Join-Path $PSScriptRoot 'ffmpeg.exe'
if(-not(Test-Path -LiteralPath $ffmpeg)){throw "FFmpeg não encontrado em $ffmpeg"}
$durations=@(4,6,6,6,6,4)
$arguments=New-Object Collections.Generic.List[string]
for($i=0;$i -lt $slides.Count;$i++){
    $arguments.Add('-i');$arguments.Add($slides[$i])
}
$filters=New-Object Collections.Generic.List[string]
for($i=0;$i -lt $slides.Count;$i++){
    $out="v$i"
    $fadeOut=([double]$durations[$i] - 0.45).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $filters.Add("[$i`:v]scale=1080:1920,zoompan=z='min(zoom+0.00018,1.025)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$($durations[$i]*30):s=1080x1920:fps=30,fade=t=in:st=0:d=0.45,fade=t=out:st=$fadeOut`:d=0.45,setsar=1[$out]")
}
$concat=((0..($slides.Count-1)|ForEach-Object{"[v$_]"}) -join '')+"concat=n=$($slides.Count):v=1:a=0[outv]"
$filters.Add($concat)
$arguments.Add('-filter_complex');$arguments.Add(($filters -join ';'))
$arguments.Add('-map');$arguments.Add('[outv]');$arguments.Add('-c:v');$arguments.Add('libx264');$arguments.Add('-preset');$arguments.Add('medium');$arguments.Add('-crf');$arguments.Add('19');$arguments.Add('-pix_fmt');$arguments.Add('yuv420p');$arguments.Add('-movflags');$arguments.Add('+faststart');$arguments.Add('-r');$arguments.Add('30');$arguments.Add('-y');$arguments.Add($OutputPath)

& $ffmpeg @arguments
if($LASTEXITCODE -ne 0){throw "FFmpeg encerrou com o código $LASTEXITCODE"}
Get-Item -LiteralPath $OutputPath | Select-Object FullName,Length,LastWriteTime
