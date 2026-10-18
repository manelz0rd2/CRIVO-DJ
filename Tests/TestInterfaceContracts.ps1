#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$app=Split-Path $PSScriptRoot -Parent
$xamlPath=Join-Path $app 'UI\MainWindow.xaml'
$scriptPath=Join-Path $app 'ODT.ps1'
$source=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$xamlSource=Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$downloaderSource=Get-Content -LiteralPath (Join-Path $app 'Modules\Downloader.psm1') -Raw -Encoding UTF8

$requiredControls=@(
    'MainTabs','DownloadQueueGrid','DownloadUrlText','StartDownloadButton',
    'SourceText','PreviewGrid','OrganizerListFilterCombo','EditTrackMetadataButton','ApplyButton',
    'RekordboxAuditGrid','AuditFilterCombo','EditAuditMetadataButton','ReviewAuditButton',
    'ToolkitSubTabs','ToolkitUsbPathText','ToolkitScanUsbButton','ToolkitChecksGrid',
    'ToolkitBackupDestinationText','ToolkitCreateBackupButton','ToolkitFirstAidButton',
    'EquipmentProfileCombo','ToolkitCompatibilityButton','CompatibilityChecksGrid'
)
# The regex is deliberately limited to XAML attributes and also catches names in templates.
$names=@([regex]::Matches($xamlSource,'x:Name="([^"]+)"') | ForEach-Object {$_.Groups[1].Value})
foreach($name in $requiredControls){if($names -notcontains $name){throw "Controle obrigatório não encontrado: $name"}}

foreach($label in @('BAIXAR','ORGANIZAR','AUDITORIA','KIT DE FERRAMENTAS USB','DIAGN','PIA SEGURA','RECUPERA','COMPATIBILIDADE')){
    if($source -notmatch [regex]::Escape($label) -and $xamlSource -notmatch [regex]::Escape($label)){throw "Área da interface não encontrada: $label"}
}

if($source -match '\[Windows\.MessageBox\]::Show|\[System\.Windows\.MessageBox\]::Show|\[Windows\.Forms\.MessageBox\]::Show'){
    throw 'Foi encontrada uma caixa de mensagem clássica fora da estética do CRIVO DJ.'
}
foreach($contract in @(
    'function Show-CrivoDialog','WindowStyle=''None''','function Show-AuditMetadataEditor',
    'ADICIONAR OU CORRIGIR METADADOS','SALVAR METADADOS','CRIAR C',
    'pode ficar incompleta','O dispositivo original n'
)){
    if(-not$source.Contains($contract)){throw "Contrato visual ou de comunicação ausente: $contract"}
}

foreach($downloadContract in @(
    'function Sync-PendingDownloadDestination',
    '$request.OutputFolder=$currentRoot',
    'function Confirm-ODTDownloadedFile',
    'O downloader terminou, mas o arquivo final',
    'Salva e pronta para organizar em'
)){
    if(-not$source.Contains($downloadContract) -and -not$downloaderSource.Contains($downloadContract)){throw "Contrato de confirmação do download ausente: $downloadContract"}
}
if(-not$source.Contains('terminou, mas nem tudo foi conclu')){throw 'A organizacao precisa diferenciar sucesso completo de resultado com erros.'}

Write-Output "INTERFACES OK: $($requiredControls.Count) controles essenciais, diálogos próprios, metadados e avisos de recuperação validados."
