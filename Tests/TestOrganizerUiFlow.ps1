#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Organizer-UI-'+[guid]::NewGuid().ToString('N'))

try{
    $env:ODT_DATA_ROOT=Join-Path $testRoot 'Dados'
    $source=Join-Path $testRoot 'Pesquisa\House';[IO.Directory]::CreateDirectory($source)|Out-Null
    1..12|ForEach-Object{[IO.File]::WriteAllBytes((Join-Path $source ("interface-{0:D2}.mp3" -f $_)),[byte[]](1,2,3,4))}
    $windowsPowerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output=@(& $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $app 'ODT.ps1') -ValidateOnly -ValidationSource (Join-Path $testRoot 'Pesquisa') 2>&1)
    if($LASTEXITCODE -ne 0){throw ($output -join [Environment]::NewLine)}
    if(($output -join "`n") -notmatch 'FOLDER AND DESTINATION FLOW OK: 12') {throw 'O fluxo visual não confirmou scan, lista, destino interno e destino externo.'}
    Write-Output 'ORGANIZER UI FLOW OK: seleção, scan, lista, modelos, destinos e estados dos botões'
}finally{
    Remove-Item Env:ODT_DATA_ROOT -ErrorAction SilentlyContinue
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
