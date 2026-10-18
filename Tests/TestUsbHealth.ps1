#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $app 'Modules\Common.psm1') -Force
Import-Module (Join-Path $app 'Modules\Metadata.psm1') -Force
Import-Module (Join-Path $app 'Modules\Rekordbox.psm1') -Force
Import-Module (Join-Path $app 'Modules\UsbHealth.psm1') -Force
$settings=Read-JsonFile -Path (Join-Path $app 'Config\settings.json')
$root=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-UsbHealth-'+[guid]::NewGuid().ToString('N'))

function Get-TestSnapshot {
    param([string]$Path)
    @(
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
        Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName.Substring($Path.Length),$_.Length,$_.LastWriteTimeUtc.Ticks }
    ) -join "`n"
}

try {
    [IO.Directory]::CreateDirectory((Join-Path $root 'PIONEER\rekordbox'))|Out-Null
    $damagedPdb=New-Object byte[] 8192
    [BitConverter]::GetBytes([uint32]4096).CopyTo($damagedPdb,4)
    [BitConverter]::GetBytes([uint32]20).CopyTo($damagedPdb,8)
    [BitConverter]::GetBytes([uint32]2).CopyTo($damagedPdb,12)
    # A segunda página física deveria declarar índice 1; o índice 99 simula
    # o mesmo tipo de dano de cabeçalho encontrado no pendrive real.
    [BitConverter]::GetBytes([uint32]99).CopyTo($damagedPdb,4100)
    [BitConverter]::GetBytes([uint32]0).CopyTo($damagedPdb,4104)
    [IO.File]::WriteAllBytes((Join-Path $root 'PIONEER\rekordbox\export.pdb'),$damagedPdb)
    [IO.Directory]::CreateDirectory((Join-Path $root 'PIONEER\USBANLZ\0001'))|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $root 'PIONEER\USBANLZ\0001\ANLZ0000.DAT'),[byte[]](5,6,7,8))
    [IO.Directory]::CreateDirectory((Join-Path $root 'Music'))|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $root 'Music\arquivo-suspeito.mp3'),[byte[]](9,10,11,12))

    $before=Get-TestSnapshot $root
    $report=Get-CrivoUsbHealth -Root $root -Settings $settings
    $after=Get-TestSnapshot $root

    if(-not$report.ReadOnly){throw 'O diagnóstico não declarou modo somente leitura.'}
    if($before -ne $after){throw 'O diagnóstico alterou arquivos da origem.'}
    if(-not$report.Device -or -not@($report.Checks).Count){throw 'O relatório não trouxe dispositivo e verificações.'}
    if([string]::IsNullOrWhiteSpace([string]$report.Overall)){throw 'O relatório não apresentou resultado geral.'}
    if(@($report.Limitations).Count -lt 4){throw 'Os limites técnicos não foram apresentados.'}
    if(-not@($report.Checks|Where-Object Name -eq 'Biblioteca do Rekordbox').Count){throw 'A biblioteca do Rekordbox não foi verificada.'}
    if(-not$report.Audit.DatabaseStructureChecked){throw 'O EXPORT.PDB não passou pela verificação estrutural básica.'}
    if([int]$report.Audit.StructureIssues -lt 1 -or [int]$report.Audit.InvalidDatabasePages -ne 1){throw 'Uma página incoerente do EXPORT.PDB não foi marcada como problema.'}
    if(-not@($report.Checks|Where-Object{$_.Name -eq 'Biblioteca do Rekordbox' -and $_.Level -eq 'Problema'}).Count){throw 'O dano estrutural não chegou ao resumo de saúde.'}
    if(-not@($report.Checks|Where-Object Name -eq 'Leitura dos áudios').Count){throw 'A leitura dos áudios não foi verificada.'}

    $export=Export-CrivoUsbHealthReport -Report $report -Directory (Join-Path $root 'Relatorios') -BaseName 'teste-diagnostico'
    if(-not(Test-Path -LiteralPath $export.HtmlPath -PathType Leaf) -or -not(Test-Path -LiteralPath $export.TechnicalPath -PathType Leaf)){throw 'Os relatórios visual e técnico não foram criados.'}
    $html=Get-Content -LiteralPath $export.HtmlPath -Raw -Encoding UTF8
    if($html -notmatch 'O que foi verificado' -or $html -notmatch 'Nenhuma correção foi aplicada' -or $html -notmatch 'Biblioteca do Rekordbox'){throw 'O relatório visual não apresentou linguagem clara e os avisos de segurança.'}

    $missing=Join-Path $root 'nao-existe'
    $threw=$false
    try { Get-CrivoUsbHealth -Root $missing -Settings $settings | Out-Null } catch { $threw=$true }
    if(-not$threw){throw 'Uma origem inexistente não foi recusada.'}

    Write-Output "USB HEALTH OK: somente leitura, $(@($report.Checks).Count) verificações e limites explícitos."
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
