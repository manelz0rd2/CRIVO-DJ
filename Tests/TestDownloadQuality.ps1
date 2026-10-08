#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSeconds=360
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Download-Quality-'+[guid]::NewGuid().ToString('N'))

try{
    Import-Module (Join-Path $app 'Modules\Downloader.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Metadata.psm1') -Force
    $settings=Get-Content -LiteralPath (Join-Path $app 'Config\settings.json') -Raw|ConvertFrom-Json
    $engine=Join-Path $app ([string]$settings.Acquisition.DownloaderPath)
    $ffmpeg=[Environment]::ExpandEnvironmentVariables([string]$settings.Acquisition.FFmpegPath)
    [IO.Directory]::CreateDirectory($testRoot)|Out-Null
    $download=Start-ODTDownload -Url $Url -OutputRoot $testRoot -EnginePath $engine -FFmpegPath $ffmpeg -Quality '320'
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do{
        Start-Sleep -Milliseconds 500
        $download=Get-ODTDownloadProgress -Download $download
    }while($download.Status -eq 'Baixando' -and (Get-Date) -lt $deadline)
    if($download.Status -eq 'Baixando'){try{$download.Process.Kill()}catch{};throw "O download não terminou em $TimeoutSeconds segundos."}
    if($download.Status -ne 'Concluido'){throw "O download falhou: $($download.Detail)"}
    $file=Get-Item -LiteralPath $download.FinalPath
    $profile=Get-Mp3BitrateProfile -File $file
    if($profile.Mode -ne 'CBR' -or $profile.Minimum -ne 320 -or $profile.Maximum -ne 320){throw "O MP3 não ficou em 320 CBR: modo=$($profile.Mode), mínimo=$($profile.Minimum), máximo=$($profile.Maximum), médio=$($profile.Average)"}
    Write-Output "DOWNLOAD QUALITY OK: 320 CBR | $($file.Name) | $($file.Length) bytes"
}finally{
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    if(Test-Path -LiteralPath $testRoot){
        $resolved=(Resolve-Path -LiteralPath $testRoot).Path
        $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
