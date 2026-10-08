#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$windowsPowerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

foreach($test in @('RunTests.ps1','TestAuditStress.ps1','TestOrganizerStress.ps1','TestOrganizerUiFlow.ps1')){
    Write-Output "EXECUTANDO: $test"
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $PSScriptRoot $test)
    if($LASTEXITCODE -ne 0){throw "A suíte $test falhou com código $LASTEXITCODE."}
}

Write-Output 'SUÍTE COMPLETA DO CRIVO DJ PASSOU'
