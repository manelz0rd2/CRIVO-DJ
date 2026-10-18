#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'docs\marketing')
)

$ErrorActionPreference='Stop'
$app=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source=Join-Path $PSScriptRoot 'ReelRenderer.cs'
$renderer=Join-Path $PSScriptRoot 'ReelRenderer.exe'
$frames=Join-Path $OutputDirectory 'frames'
$silent=Join-Path $OutputDirectory 'CRIVO-DJ-reel-motion-sem-audio.mp4'
$final=Join-Path $OutputDirectory 'CRIVO-DJ-reel-motion.mp4'
$preview=Join-Path $OutputDirectory 'CRIVO-DJ-reel-motion-preview.jpg'
$ffmpeg=Join-Path $app 'Tools\ffmpeg.exe'
$screenshots=Join-Path $app 'docs\screenshots'
$logo=Join-Path $app 'Assets\CRIVO-DJ.png'
$music='C:\Users\EmanuelPereiraFraga\Music\CRIVO DJ\Downloads\GEMINX - NOWAYHOME!.mp3'

[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
if(Test-Path -LiteralPath $frames){Remove-Item -LiteralPath $frames -Recurse -Force}
[IO.Directory]::CreateDirectory($frames)|Out-Null

$csc="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /optimize+ /target:exe /out:$renderer /reference:System.Drawing.dll $source
if($LASTEXITCODE){throw 'Falha ao compilar o renderizador do reel.'}
& $renderer $screenshots $logo $frames
if($LASTEXITCODE){throw 'Falha ao renderizar os quadros do reel.'}

& $ffmpeg -y -framerate 24 -i (Join-Path $frames 'frame-%05d.jpg') -vf 'scale=1080:1920:flags=lanczos,format=yuv420p' -r 24 -c:v libx264 -preset medium -crf 18 -movflags +faststart $silent
if($LASTEXITCODE){throw 'Falha ao montar o vídeo.'}

if(Test-Path -LiteralPath $music){
    & $ffmpeg -y -i $silent -ss 55 -i $music -filter_complex '[1:a]atrim=0:52,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.15,afade=t=out:st=50.5:d=1.5[a]' -map 0:v -map '[a]' -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart $final
} else {
    Copy-Item -LiteralPath $silent -Destination $final -Force
}
if($LASTEXITCODE){throw 'Falha ao aplicar a trilha do reel.'}

& $ffmpeg -y -ss 26 -i $final -frames:v 1 -q:v 2 $preview
if($LASTEXITCODE){throw 'Falha ao gerar a prévia do reel.'}

Write-Output $final
Write-Output $preview
