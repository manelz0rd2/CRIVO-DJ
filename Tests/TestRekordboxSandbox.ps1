#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$helper=Join-Path $app 'Tools\ODT-RekordboxDirect\ODT-RekordboxDirect.exe'
$realDatabase=Join-Path $env:APPDATA 'Pioneer\rekordbox\master.db'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Rekordbox-Sandbox-'+[guid]::NewGuid().ToString('N'))

function Invoke-HelperJson {
    param([Parameter(Mandatory)]$Payload,[Parameter(Mandatory)][string]$Name)
    $payloadPath=Join-Path $sandbox "$Name.json"
    [IO.File]::WriteAllText($payloadPath,($Payload|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $raw=& $helper $payloadPath 2>&1
    $exitCode=$LASTEXITCODE
    if($exitCode -ne 0){throw "Helper falhou ($exitCode): $($raw -join [Environment]::NewLine)"}
    $result=($raw -join [Environment]::NewLine)|ConvertFrom-Json
    if(-not$result.success){throw [string]$result.message}
    return $result
}

function New-SilentTestWav {
    param([Parameter(Mandatory)][string]$Path)
    $sampleRate=8000;$channels=1;$bits=16;$dataLength=$sampleRate*2
    $stream=[IO.File]::Create($Path);$writer=New-Object IO.BinaryWriter($stream)
    try{
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([int](36+$dataLength));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([Text.Encoding]::ASCII.GetBytes('fmt '));$writer.Write([int]16);$writer.Write([int16]1);$writer.Write([int16]$channels);$writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate*$channels*$bits/8));$writer.Write([int16]($channels*$bits/8));$writer.Write([int16]$bits)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([int]$dataLength);$writer.Write((New-Object byte[] $dataLength))
    }finally{$writer.Dispose();$stream.Dispose()}
}

if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw "Helper não encontrado: $helper"}
if(-not(Test-Path -LiteralPath $realDatabase -PathType Leaf)){Write-Output 'SKIP: master.db não encontrado';return}
if(@(Get-Process -Name rekordbox,rekordboxAgent -ErrorAction SilentlyContinue).Count){Write-Output 'SKIP: Rekordbox ou rekordboxAgent está aberto';return}

$beforeHash=(Get-FileHash -LiteralPath $realDatabase -Algorithm SHA256).Hash
$beforeTime=(Get-Item -LiteralPath $realDatabase).LastWriteTimeUtc
[IO.Directory]::CreateDirectory($sandbox)|Out-Null
try{
    $sourceDirectory=Split-Path -Parent $realDatabase
    foreach($name in @('master.db','master.db-wal','master.db-shm','masterPlaylists6.xml','master.backup.db')){
        $source=Join-Path $sourceDirectory $name
        if(Test-Path -LiteralPath $source -PathType Leaf){[IO.File]::Copy($source,(Join-Path $sandbox $name),$true)}
    }
    $sandboxDatabase=Join-Path $sandbox 'master.db'
    $initialAudit=Invoke-HelperJson -Payload @{operation='audit';databasePath=$sandboxDatabase} -Name 'audit-before'
    $testTrack=Join-Path $sandbox 'CRIVO Sandbox Track.wav';New-SilentTestWav -Path $testTrack

    $playlistName='CRIVO SANDBOX '+[guid]::NewGuid().ToString('N').Substring(0,8)
    $payload=@{databasePath=$sandboxDatabase;playlistName=$playlistName;tracks=@(@{path=$testTrack;title='CRIVO Sandbox Track';artist='MANELZ0RD';album='CRIVO Tests';genre='House';bpm=128;key='8A';year='2026';bitrate=0;sampleRate=8000})}
    $first=Invoke-HelperJson -Payload $payload -Name 'write-first'
    if([int]$first.tracksInPlaylist -ne 1 -or [int]$first.tracksAddedToPlaylist -ne 1 -or [int]$first.tracksAddedToCollection -ne 1){throw 'A primeira escrita não criou a track e a playlist na cópia do banco.'}
    $second=Invoke-HelperJson -Payload $payload -Name 'write-second'
    if([int]$second.tracksInPlaylist -ne 1 -or [int]$second.tracksAlreadyPresent -ne 1){throw 'A segunda escrita duplicou a track ou não detectou a presença anterior.'}
    $finalAudit=Invoke-HelperJson -Payload @{operation='audit';databasePath=$sandboxDatabase} -Name 'audit-after'
    $playlist=@($finalAudit.playlists|Where-Object name -eq $playlistName)
    if($playlist.Count -ne 1 -or [int]$playlist[0].trackCount -ne 1){throw 'A playlist não apareceu na auditoria da cópia do banco.'}
    $sandboxContent=@($finalAudit.tracks|Where-Object location -eq $testTrack|Select-Object -First 1)
    if($sandboxContent.Count -ne 1){throw 'A track criada não apareceu na coleção da cópia do banco.'}
    $metadataUpdate=Invoke-HelperJson -Payload @{operation='update_metadata';databasePath=$sandboxDatabase;trackID=[string]$sandboxContent[0].trackID;metadata=@{title='CRIVO Sandbox Atualizada';artist='MANELZ0RD';album='CRIVO Tests Updated';genre='Deep House';bpm=126;key='9A';year='2025'}} -Name 'update-metadata'
    if([string]$metadataUpdate.metadata.title -ne 'CRIVO Sandbox Atualizada' -or [string]$metadataUpdate.metadata.genre -ne 'Deep House' -or [int]$metadataUpdate.metadata.bpm -ne 126 -or [string]$metadataUpdate.metadata.key -ne 'Em'){throw 'A escrita manual de metadata não foi confirmada no banco da cópia.'}

    $afterHash=(Get-FileHash -LiteralPath $realDatabase -Algorithm SHA256).Hash
    $afterTime=(Get-Item -LiteralPath $realDatabase).LastWriteTimeUtc
    if($beforeHash -ne $afterHash -or $beforeTime -ne $afterTime){throw 'O banco real foi alterado durante o teste isolado.'}
    Write-Output "REKORDBOX SANDBOX OK: $($initialAudit.tracks.Count) tracks lidas; playlist criada, reaberta e sem duplicação; banco real intacto."
}finally{
    if(Test-Path -LiteralPath $sandbox){
        [GC]::Collect();[GC]::WaitForPendingFinalizers()
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
