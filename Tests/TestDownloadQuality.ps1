#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSeconds=360,
    [switch]$ResolveFirst
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Download-Quality-'+[guid]::NewGuid().ToString('N'))

try{
    Import-Module (Join-Path $app 'Modules\Downloader.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Metadata.psm1') -Force
    $settings=Get-Content -LiteralPath (Join-Path $app 'Config\settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $engine=Join-Path $app ([string]$settings.Acquisition.DownloaderPath)
    $ffmpeg=[Environment]::ExpandEnvironmentVariables([string]$settings.Acquisition.FFmpegPath);if($ffmpeg -and -not[IO.Path]::IsPathRooted($ffmpeg)){$ffmpeg=Join-Path $app $ffmpeg}
    [IO.Directory]::CreateDirectory($testRoot)|Out-Null
    $downloadUrl=$Url;$displayUrl=$Url;$initialTitle='';$initialArtist='';$provider='';$duration='';$thumbnail=''
    if($ResolveFirst){
        $resolver=Start-ODTPlaylistResolver -Url $Url -OutputRoot $testRoot -EnginePath $engine -Quality '320' -SingleTrack
        $resolveDeadline=(Get-Date).AddSeconds([Math]::Min(180,$TimeoutSeconds));$resolved=@()
        do{Start-Sleep -Milliseconds 300;$resolved=@(Complete-ODTPlaylistResolver -Resolver $resolver)}while(-not$resolved.Count -and $resolver.Status -eq 'Analisando' -and (Get-Date) -lt $resolveDeadline)
        if(-not$resolved.Count){throw "A resolução da track falhou: $($resolver.Detail)"}
        $request=$resolved[0];$downloadUrl=[string]$request.DownloadUrl;$displayUrl=[string]$request.Url;$initialTitle=[string]$request.Title;$initialArtist=[string]$request.Artist;$provider=[string]$request.Source;$duration=[string]$request.Duration;$thumbnail=[string]$request.Thumbnail
    }
    $download=Start-ODTDownload -Url $downloadUrl -DisplayUrl $displayUrl -InitialTitle $initialTitle -InitialSource $initialArtist -Provider $provider -InitialDuration $duration -InitialThumbnail $thumbnail -OutputRoot $testRoot -EnginePath $engine -FFmpegPath $ffmpeg -Quality '320'
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do{
        Start-Sleep -Milliseconds 500
        $download=Get-ODTDownloadProgress -Download $download
    }while($download.Status -eq 'Baixando' -and (Get-Date) -lt $deadline)
    if($download.Status -eq 'Baixando'){try{$download.Process.Kill()}catch{};throw "O download não terminou em $TimeoutSeconds segundos."}
    if($download.Status -ne 'Concluido'){throw "O download falhou: $($download.Detail)"}
    $file=Get-Item -LiteralPath $download.FinalPath
    if($ResolveFirst -and $initialArtist -and $file.BaseName -match ('(?i)^'+[regex]::Escape($initialArtist)+'\s*-\s*'+[regex]::Escape($initialArtist)+'\s*-')){throw "O artista foi duplicado no nome final: $($file.Name)"}
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
