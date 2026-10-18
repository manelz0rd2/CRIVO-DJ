#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $app 'Modules\UsbBackup.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-UsbBackup-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'origem';$destination=Join-Path $root 'destino';$failedDestination=Join-Path $root 'falha'

try{
    [IO.Directory]::CreateDirectory((Join-Path $source 'Músicas\Subpasta'))|Out-Null
    [IO.Directory]::CreateDirectory($destination)|Out-Null;[IO.Directory]::CreateDirectory($failedDestination)|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $source 'Músicas\Faixa 1.mp3'),[byte[]](1,2,3,4,5,6))
    [IO.File]::WriteAllBytes((Join-Path $source 'Músicas\Subpasta\Faixa 2.wav'),[byte[]](7,8,9,10))
    $hidden=Join-Path $source '.crivo-oculto';[IO.File]::WriteAllText($hidden,'controle',[Text.Encoding]::UTF8);[IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden)
    $before=@{};Get-ChildItem $source -Recurse -Force -File|ForEach-Object{$before[$_.FullName]=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}
    $plan=New-CrivoUsbBackupPlan -SourceRoot $source -DestinationRoot $destination
    if($plan.FileCount -ne 3 -or -not$plan.EnoughSpace){throw 'O plano não incluiu todos os arquivos ou calculou o espaço incorretamente.'}
    $progressCount=0;$result=Invoke-CrivoUsbBackup -Plan $plan -OnProgress {param($current,$total,$name,$phase)$script:progressCount=$current}
    if(-not$result.Success -or $result.VerifiedCount -ne 3 -or $result.ErrorCount){throw 'A cópia não foi validada.'}
    if(-not(Test-Path (Join-Path $result.BackupRoot 'Manifesto-SHA256.json')) -or -not(Test-Path (Join-Path $result.BackupRoot 'Relatorio-da-copia.html'))){throw 'Manifesto ou relatório não foi criado.'}
    foreach($item in $before.GetEnumerator()){if((Get-FileHash $item.Key -Algorithm SHA256).Hash -ne $item.Value){throw 'A origem foi alterada.'}}
    $copied=@(Get-ChildItem $result.BackupRoot -Recurse -Force -File|Where-Object{$_.Name -notin @('Manifesto-SHA256.json','Relatorio-da-copia.html','Relatorio-tecnico.json')})
    if($copied.Count -ne 3){throw 'A quantidade de arquivos preservados está incorreta.'}

    $inside=Join-Path $source 'destino-inseguro';[IO.Directory]::CreateDirectory($inside)|Out-Null;$threw=$false
    try{New-CrivoUsbBackupPlan -SourceRoot $source -DestinationRoot $inside|Out-Null}catch{$threw=$true}
    if(-not$threw){throw 'Um destino dentro da origem foi aceito.'}

    $badPlan=New-CrivoUsbBackupPlan -SourceRoot $source -DestinationRoot $failedDestination
    $badPlan.Files[1].Source=Join-Path $source 'arquivo-removido.mp3'
    $threw=$false;try{Invoke-CrivoUsbBackup -Plan $badPlan|Out-Null}catch{$threw=$true}
    if(-not$threw){throw 'Uma origem interrompida foi apresentada como concluída.'}
    $partial=@(Get-ChildItem $failedDestination -Directory -Filter '*.incompleta')
    if($partial.Count -ne 1 -or -not(Test-Path (Join-Path $partial[0].FullName 'LEIA-ME-COPIA-INCOMPLETA.txt'))){throw 'A falha não deixou a cópia claramente marcada como incompleta.'}
    Write-Output 'CÓPIA SEGURA OK: preservação, hashes, destino inseguro e interrupção tratados.'
}finally{
    if(Test-Path -LiteralPath $root){[IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Normal);Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
