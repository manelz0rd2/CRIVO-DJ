#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$database=Join-Path $env:APPDATA 'Pioneer\rekordbox\master.db'
if(-not(Test-Path -LiteralPath $database -PathType Leaf)){Write-Output 'SKIP: master.db não encontrado';return}

# Carrega exatamente a mesma função usada pelo botão ESCANEAR BIBLIOTECA, mas sem abrir a janela.
. (Join-Path $app 'ODT.ps1') -ValidateOnly
$script:RekordboxSummaryText.Text='';Set-AuditMode Usb
if($AuditUsbSourcePanel.Visibility -ne 'Visible' -or $AuditLibrarySourcePanel.Visibility -ne 'Collapsed'){throw 'O modo Pendrive não alternou os painéis da Auditoria.'}
Set-AuditMode Library
if($AuditLibrarySourcePanel.Visibility -ne 'Visible' -or $AuditUsbSourcePanel.Visibility -ne 'Collapsed'){throw 'O modo Biblioteca não restaurou os painéis da Auditoria.'}
$library=Get-RekordboxDatabaseLibrary -Path $database
if(-not$library -or @($library.Tracks).Count -lt 1){throw 'A leitura de runtime não retornou a coleção do Rekordbox.'}
$expectedMissing=0;$expectedUnavailable=0
foreach($track in @($library.Tracks)){
    $location=[string]$track.Location
    try{$location=[Uri]::UnescapeDataString(($location -replace '^file://(localhost/)?',''));if($location -match '^/[A-Za-z]:/'){$location=$location.Substring(1)};$location=$location -replace '/','\'}catch{}
    if(-not$location){$expectedMissing++;continue}
    $root=[IO.Path]::GetPathRoot($location)
    if($root -and -not(Test-Path -LiteralPath $root -PathType Container)){$expectedUnavailable++;continue}
    if(-not(Test-Path -LiteralPath $location -PathType Leaf)){$expectedMissing++}
}
try{$directAudit=Get-RekordboxAudit -Library $library -Settings $script:Settings}catch{throw "$($_.Exception.Message)`n$($_.ScriptStackTrace)"}
if(-not$directAudit -or @($directAudit.Rows).Count -ne @($library.Tracks).Count){throw 'A auditoria direta não retornou uma linha para cada track da coleção.'}
$RekordboxXmlText.Text=$database
Invoke-RekordboxIntegrationAudit
if(-not$script:RekordboxAudit -or [int]$AuditCollectionCount.Text -ne @($library.Tracks).Count){throw 'O botão ESCANEAR BIBLIOTECA não atualizou os indicadores da Auditoria.'}
if([int]$script:RekordboxAudit.MissingFiles -ne $expectedMissing){throw "A auditoria marcou $($script:RekordboxAudit.MissingFiles) arquivo(s) físico(s) ausente(s), mas a verificação direta encontrou $expectedMissing."}
if([int]$script:RekordboxAudit.UnavailableFiles -ne $expectedUnavailable){throw "A auditoria marcou $($script:RekordboxAudit.UnavailableFiles) arquivo(s) em unidades indisponíveis, mas a verificação direta encontrou $expectedUnavailable."}
Select-ComboTag $AuditFilterCombo 'All';Update-RekordboxAuditView
if(@($RekordboxAuditGrid.ItemsSource).Count -ne @($library.Tracks).Count){throw 'A lista da Auditoria não recebeu todas as tracks.'}
if($null -eq $AuditQualityCount.Text -or $null -eq $AuditDataCount.Text){throw 'Os novos indicadores da Auditoria não foram atualizados.'}
Write-Output "AUDITORIA RUNTIME OK: $(@($library.Tracks).Count) tracks e $(@($library.Playlists).Count) playlists; scanner, indicadores e lista atualizados."
