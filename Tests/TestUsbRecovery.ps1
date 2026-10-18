#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$appRoot=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $appRoot 'Modules\UsbRecovery.psm1') -Force

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('CrivoUsbRecoveryTest-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $testRoot 'origem'
$destination=Join-Path $testRoot 'destino'
$audio=Join-Path $source 'Conteudo\Música de teste.mp3'
$planPath=Join-Path $testRoot 'plano.json'

try{
    [IO.Directory]::CreateDirectory((Split-Path $audio -Parent))|Out-Null
    [IO.Directory]::CreateDirectory($destination)|Out-Null
    [IO.File]::WriteAllBytes($audio,[byte[]](1,2,3,4,5))
    $sourceHash=(Get-FileHash -LiteralPath $audio -Algorithm SHA256).Hash
    $plan=[ordered]@{
        format_version=1;source_root=$source;source_file_count=1;source_byte_count=5
        confirmed_link_count=1;unresolved_link_count=0
        source_files=@([ordered]@{path=$audio;relative_path='Conteudo\Música de teste.mp3';size=5})
        playlists=@([ordered]@{
            playlist_id=1;name='Seleção de teste';path='Seleção de teste';status='Recuperação parcial';total_entries=1
            entries=@([ordered]@{position=1;resolved=$true;title='Música de teste';source_path=$audio})
        })
    }
    [IO.File]::WriteAllText($planPath,($plan|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    $result=Invoke-CrivoUsbRecoveryCopy -PlanPath $planPath -DestinationRoot $destination
    if(-not$result.success -or -not$result.backup_validated){throw 'A cópia sintética não foi validada.'}
    if([string]$result.playlists[0].status -ne 'Recuperação parcial'){throw 'O retorno UTF-8 da recuperação foi corrompido.'}
    if(([string]$result.playlists[0].status).Contains([char]0xFFFD)){throw 'O retorno contém caractere de substituição.'}
    $copied=Join-Path ([string]$result.recovery_root) 'Original preservado\Conteudo\Música de teste.mp3'
    if(-not(Test-Path -LiteralPath $copied -PathType Leaf)){throw 'O áudio não foi preservado na cópia.'}
    if((Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash -ne $sourceHash){throw 'O conteúdo do áudio copiado é diferente da origem.'}
    $playlist=@(Get-ChildItem (Join-Path ([string]$result.recovery_root) 'Playlists') -Filter '*.m3u8' -File)
    if($playlist.Count -ne 1){throw 'A playlist recuperada não foi criada.'}
    $targetLine=@([IO.File]::ReadAllLines($playlist[0].FullName,[Text.Encoding]::UTF8)|Where-Object{$_ -and -not$_.StartsWith('#')})
    if($targetLine.Count -ne 1 -or -not(Test-Path -LiteralPath ([IO.Path]::GetFullPath((Join-Path $playlist[0].DirectoryName ($targetLine[0] -replace '/','\')))) -PathType Leaf)){throw 'A playlist recuperada aponta para um arquivo inexistente.'}
    $report=[IO.File]::ReadAllText((Join-Path ([string]$result.recovery_root) 'Relatorio-da-recuperacao.html'),[Text.Encoding]::UTF8)
    if(-not$report.Contains('Recuperação parcial') -or $report.Contains([char]0xFFFD)){throw 'O relatório da recuperação perdeu os acentos.'}
    if((Get-FileHash -LiteralPath $audio -Algorithm SHA256).Hash -ne $sourceHash){throw 'A origem foi alterada durante a recuperação.'}
    Write-Output 'TESTE DE RECUPERAÇÃO USB PASSOU'
}finally{
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith('CrivoUsbRecoveryTest-')){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
