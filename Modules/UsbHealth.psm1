#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CrivoDriveTypeLabel {
    param([int]$DriveType)
    switch ($DriveType) {
        2 { 'Removível' }
        3 { 'Disco local' }
        4 { 'Unidade de rede' }
        5 { 'Mídia óptica' }
        6 { 'Disco de memória' }
        default { 'Não identificado' }
    }
}

function Get-CrivoUsbDeviceInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "A origem não foi encontrada: $Root"
    }

    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
    $volumeRoot = [IO.Path]::GetPathRoot($resolved)
    $deviceId = $volumeRoot.TrimEnd('\')
    $logicalDisk = $null
    $volumeStatus = $null

    if ($deviceId -match '^[A-Za-z]:$') {
        try {
            $escaped = $deviceId.Replace("'", "''")
            $logicalDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$escaped'" -ErrorAction Stop | Select-Object -First 1
        } catch {
            $logicalDisk = $null
        }
        try {$volumeStatus=Get-Volume -DriveLetter $deviceId.Substring(0,1) -ErrorAction Stop|Select-Object -First 1}catch{$volumeStatus=$null}
    }

    $size = if ($logicalDisk -and $null -ne $logicalDisk.Size) { [int64]$logicalDisk.Size } else { 0L }
    $free = if ($logicalDisk -and $null -ne $logicalDisk.FreeSpace) { [int64]$logicalDisk.FreeSpace } else { 0L }
    $driveType = if ($logicalDisk) { [int]$logicalDisk.DriveType } else { 0 }

    [pscustomobject]@{
        SelectedPath = $resolved
        VolumeRoot = $volumeRoot
        DeviceId = $deviceId
        Label = if ($logicalDisk) { [string]$logicalDisk.VolumeName } else { '' }
        FileSystem = if ($logicalDisk) { [string]$logicalDisk.FileSystem } else { '' }
        DriveType = $driveType
        DriveTypeLabel = Get-CrivoDriveTypeLabel -DriveType $driveType
        IsRemovable = ($driveType -eq 2)
        SizeBytes = $size
        FreeBytes = $free
        FreePercent = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 1) } else { $null }
        InformationComplete = [bool]$logicalDisk
        IsVolumeRoot = ($resolved.TrimEnd('\') -eq $volumeRoot.TrimEnd('\'))
        WindowsHealthStatus = if($volumeStatus){[string]$volumeStatus.HealthStatus}else{''}
        WindowsOperationalStatus = if($volumeStatus){(@($volumeStatus.OperationalStatus)|ForEach-Object{[string]$_}) -join ', '}else{''}
    }
}

function New-CrivoHealthCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('OK','Atenção','Problema','Não verificado')][string]$Level,
        [Parameter(Mandatory)][string]$Summary,
        [string]$Detail = ''
    )
    [pscustomobject]@{ Name=$Name; Level=$Level; Summary=$Summary; Detail=$Detail }
}

function Get-CrivoUsbHealth {
    <#
      Diagnóstico lógico e estritamente somente leitura. A função não cria arquivos,
      não executa CHKDSK e não tenta inferir desgaste físico sem dados do dispositivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Settings,
        [scriptblock]$OnProgress
    )

    $device = Get-CrivoUsbDeviceInfo -Root $Root
    $checks = [Collections.Generic.List[object]]::new()

    if ($device.InformationComplete) {
        $checks.Add((New-CrivoHealthCheck 'Dispositivo' 'OK' "$($device.DriveTypeLabel) identificado" "$($device.DeviceId) $($device.Label)".Trim()))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Dispositivo' 'Não verificado' 'O Windows não forneceu todos os dados do dispositivo.' 'A verificação dos arquivos ainda pode ser executada.'))
    }

    if(-not$device.IsVolumeRoot){
        $checks.Add((New-CrivoHealthCheck 'Estado informado pelo Windows' 'Não verificado' 'Uma pasta de teste não permite avaliar o dispositivo original.' 'Use a raiz do pendrive para consultar o estado que o Windows consegue fornecer.'))
    }elseif([string]::IsNullOrWhiteSpace($device.WindowsHealthStatus)){
        $checks.Add((New-CrivoHealthCheck 'Estado informado pelo Windows' 'Não verificado' 'O Windows não forneceu um estado de saúde para este volume.' 'Pendrives normalmente não expõem desgaste físico ou SMART confiável pela conexão USB.'))
    }elseif($device.WindowsHealthStatus -eq 'Healthy' -and $device.WindowsOperationalStatus -match 'OK'){
        $checks.Add((New-CrivoHealthCheck 'Estado informado pelo Windows' 'OK' 'O volume está operacional segundo o Windows.' 'Isso não mede desgaste da memória e não garante que o dispositivo não falhará depois.'))
    }else{
        $checks.Add((New-CrivoHealthCheck 'Estado informado pelo Windows' 'Atenção' "$($device.WindowsHealthStatus): $($device.WindowsOperationalStatus)" 'Faça uma cópia segura antes de qualquer outra operação.'))
    }

    if(-not$device.IsVolumeRoot){
        $checks.Add((New-CrivoHealthCheck 'Sistema de arquivos' 'Não verificado' 'Foi escolhida uma pasta de teste, não a raiz de um dispositivo.' 'O sistema de arquivos pertence ao disco que guarda esta cópia e não comprova o formato do pendrive original.'))
    } elseif ([string]::IsNullOrWhiteSpace($device.FileSystem)) {
        $checks.Add((New-CrivoHealthCheck 'Sistema de arquivos' 'Não verificado' 'O sistema de arquivos não foi informado pelo Windows.'))
    } elseif ($device.FileSystem -in @('FAT32','exFAT')) {
        $checks.Add((New-CrivoHealthCheck 'Sistema de arquivos' 'OK' "$($device.FileSystem) identificado." 'A compatibilidade final ainda depende do equipamento selecionado.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Sistema de arquivos' 'Atenção' "$($device.FileSystem) pode não ser aceito por alguns equipamentos DJ." 'Use o teste de compatibilidade do modelo antes da apresentação.'))
    }

    if(-not$device.IsVolumeRoot){
        $checks.Add((New-CrivoHealthCheck 'Espaço livre' 'Não verificado' 'O espaço livre do pendrive original não pode ser obtido a partir desta pasta de teste.'))
    }elseif ($device.SizeBytes -le 0) {
        $checks.Add((New-CrivoHealthCheck 'Espaço livre' 'Não verificado' 'Não foi possível confirmar capacidade e espaço livre.'))
    } elseif ($device.FreePercent -lt 10) {
        $checks.Add((New-CrivoHealthCheck 'Espaço livre' 'Atenção' "Restam $($device.FreePercent)% da capacidade." 'Pouco espaço pode impedir novas exportações ou cópias de segurança.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Espaço livre' 'OK' "$($device.FreePercent)% da capacidade está livre."))
    }

    $audit = Get-RekordboxUsbAudit -Root $device.SelectedPath -Settings $Settings -OnProgress $OnProgress

    if ([int]$audit.StructureIssues -gt 0) {
        $summary=if([int]$audit.InvalidDatabasePages -gt 0){"$($audit.InvalidDatabasePages) parte(s) da biblioteca não puderam ser lidas com segurança."}else{"$($audit.StructureIssues) problema(s) confirmado(s) na biblioteca."}
        $checks.Add((New-CrivoHealthCheck 'Biblioteca do Rekordbox' 'Problema' $summary 'O CRIVO não alterou o dispositivo. Veja o relatório antes de preparar uma reconstrução em outro local.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Biblioteca do Rekordbox' 'OK' 'Os arquivos básicos da biblioteca foram encontrados e puderam ser abertos.' 'Isso ainda não confirma sozinho todas as tracks e posições das playlists.'))
    }

    $rekordboxRoot=Join-Path $device.SelectedPath 'PIONEER\rekordbox'
    $deviceLibrary=Join-Path $rekordboxRoot 'EXPORT.PDB'
    $oneLibrary=Join-Path $rekordboxRoot 'exportLibrary.db'
    if((Test-Path -LiteralPath $deviceLibrary -PathType Leaf) -and (Test-Path -LiteralPath $oneLibrary -PathType Leaf)){
        $deviceLibraryInfo=Get-Item -LiteralPath $deviceLibrary
        $oneLibraryInfo=Get-Item -LiteralPath $oneLibrary
        $difference=[math]::Abs(($deviceLibraryInfo.LastWriteTime-$oneLibraryInfo.LastWriteTime).TotalDays)
        if($difference -gt 1){
            $checks.Add((New-CrivoHealthCheck 'Versões da biblioteca' 'Atenção' 'O dispositivo contém duas versões da biblioteca com datas muito diferentes.' "Alguns equipamentos usam a biblioteca antiga e outros usam a mais recente. Detalhe técnico: Device Library em $($deviceLibraryInfo.LastWriteTime.ToString('dd/MM/yyyy HH:mm')); OneLibrary em $($oneLibraryInfo.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))."))
        }else{
            $checks.Add((New-CrivoHealthCheck 'Versões da biblioteca' 'OK' 'As duas versões da biblioteca foram encontradas com datas próximas.' 'A confirmação das tracks e posições das playlists ainda depende da leitura interna dos bancos.'))
        }
    }elseif((Test-Path -LiteralPath $deviceLibrary -PathType Leaf) -or (Test-Path -LiteralPath $oneLibrary -PathType Leaf)){
        $found=if(Test-Path -LiteralPath $deviceLibrary -PathType Leaf){'Device Library'}else{'OneLibrary'}
        $friendly=if($found -eq 'Device Library'){'a biblioteca usada por equipamentos anteriores'}else{'a biblioteca usada por equipamentos mais recentes'}
        $checks.Add((New-CrivoHealthCheck 'Versões da biblioteca' 'Não verificado' "Foi encontrada somente $friendly." 'Isso pode ser normal ou incompatível, dependendo do equipamento em que o dispositivo será usado.'))
    }

    if ([int]$audit.AnalysisIssues -gt 0) {
        $checks.Add((New-CrivoHealthCheck 'Dados de análise' 'Atenção' "$($audit.AnalysisIssues) ausência(s) ou inconsistência(s) encontrada(s)." 'Isso pode afetar waveform, beatgrid, cues ou outras informações dependentes da exportação.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Dados de análise' 'OK' "$($audit.AnalysisFileCount) arquivo(s) de análise localizado(s)."))
    }

    if ([int]$audit.MissingFiles -gt 0) {
        $checks.Add((New-CrivoHealthCheck 'Leitura dos áudios' 'Problema' "$($audit.MissingFiles) arquivo(s) inacessível(is) ou suspeito(s)." 'A presença do arquivo não garante que todo o áudio esteja íntegro.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Leitura dos áudios' 'OK' "$($audit.Total) arquivo(s) de áudio puderam ser inspecionados." 'Este teste não substitui a reprodução completa de todas as tracks.'))
    }

    if ([int]$audit.QualityIssues -gt 0) {
        $checks.Add((New-CrivoHealthCheck 'Qualidade dos áudios' 'Atenção' "$($audit.QualityIssues) arquivo(s) ficaram abaixo dos critérios de qualidade configurados." 'Qualidade baixa não significa necessariamente incompatibilidade ou arquivo corrompido.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Qualidade dos áudios' 'OK' 'Nenhum arquivo ficou abaixo dos critérios de qualidade configurados.'))
    }

    if ([int]$audit.MetadataIssues -gt 0) {
        $checks.Add((New-CrivoHealthCheck 'Dados das tracks' 'Atenção' "$($audit.MetadataIssues) track(s) possuem título, artista, álbum, gênero ou ano faltante." 'BPM e tonalidade não são contados aqui porque dependem normalmente da análise do software DJ.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Dados das tracks' 'OK' 'Nenhum dado obrigatório ficou ausente pelos critérios atuais.'))
    }

    if ([int]$audit.DuplicatePaths -gt 0 -or [int]$audit.PossibleDuplicates -gt 0) {
        $checks.Add((New-CrivoHealthCheck 'Duplicatas' 'Atenção' "$($audit.DuplicatePaths) exata(s) e $($audit.PossibleDuplicates) possível(is)." 'Possíveis duplicatas exigem revisão humana.'))
    } else {
        $checks.Add((New-CrivoHealthCheck 'Duplicatas' 'OK' 'Nenhuma duplicata foi indicada pelos critérios atuais.'))
    }

    $problemCount = @($checks | Where-Object Level -eq 'Problema').Count
    $attentionCount = @($checks | Where-Object Level -eq 'Atenção').Count
    $unknownCount = @($checks | Where-Object Level -eq 'Não verificado').Count
    $overall = if ($problemCount) {
        'Problemas encontrados'
    } elseif ($attentionCount) {
        'Pontos de atenção encontrados'
    } elseif ($unknownCount) {
        'Verificação parcial'
    } else {
        'Nenhum problema encontrado nesta verificação'
    }

    [pscustomobject]@{
        Mode = 'UsbHealth'
        GeneratedAt = Get-Date
        Root = $device.SelectedPath
        ReadOnly = $true
        Overall = $overall
        ProblemCount = $problemCount
        AttentionCount = $attentionCount
        UnknownCount = $unknownCount
        Device = $device
        Checks = $checks.ToArray()
        Audit = $audit
        Limitations = @(
            'O resultado descreve somente os testes executados e não garante a condição física da memória USB.',
            'SMART e desgaste físico não são estimados quando o dispositivo não fornece dados confiáveis.',
            'Compatibilidade com um equipamento específico deve ser verificada no perfil daquele modelo.',
            'Cues, loops, beatgrid e waveform não podem ser garantidos apenas pela leitura do arquivo de áudio.'
        )
    }
}

function Export-CrivoUsbHealthReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$Directory,
        [string]$BaseName
    )

    [IO.Directory]::CreateDirectory($Directory)|Out-Null
    if([string]::IsNullOrWhiteSpace($BaseName)){$BaseName='CRIVO-DJ-Diagnostico-'+(Get-Date -Format 'yyyyMMdd-HHmmss')}
    $htmlPath=Join-Path $Directory ($BaseName+'.html')
    $technicalPath=Join-Path $Directory ($BaseName+'-tecnico.json')
    $encode={param($value)[Net.WebUtility]::HtmlEncode([string]$value)}
    $rows=New-Object Text.StringBuilder
    foreach($check in @($Report.Checks)){
        $levelClass=switch([string]$check.Level){'Problema'{'problem'}'Atenção'{'attention'}'OK'{'ok'}default{'unknown'}}
        [void]$rows.AppendLine("<tr><td>$(& $encode $check.Name)</td><td><span class='level $levelClass'>$(& $encode $check.Level)</span></td><td>$(& $encode $check.Summary)</td><td>$(& $encode $check.Detail)</td></tr>")
    }
    $limitations=(@($Report.Limitations)|ForEach-Object{"<li>$(& $encode $_)</li>"}) -join "`n"
    $deviceLabel=([string]$Report.Device.Label).Trim();if(-not$deviceLabel){$deviceLabel='Sem nome'}
    $html=@"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CRIVO DJ — Diagnóstico do dispositivo</title>
<style>
body{margin:0;background:#b8b4ac;color:#171613;font-family:Arial,sans-serif}main{max-width:1180px;margin:28px auto;padding:0 18px}.brand{background:#111214;color:#fff;padding:18px 22px}.brand b{font-size:22px}.brand span{color:#c7c2b8;margin-left:12px}.panel{background:#d0ccc3;border:1px solid #777269;margin-top:14px;padding:18px}.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.card{background:#c4c0b7;border:1px solid #777269;padding:14px}.card small{display:block;color:#45413b;font-weight:bold}.card strong{display:block;font-size:25px;margin-top:6px}.overall{font-size:17px!important}.notice{border-left:5px solid #171613}table{width:100%;border-collapse:collapse;margin-top:10px;background:#d8d4cc}th,td{padding:10px;border-bottom:1px solid #aaa59c;text-align:left;vertical-align:top}th{background:#a7a299;font-size:11px}.level{display:inline-block;padding:4px 7px;font-weight:bold;font-size:11px}.problem{background:#8f1f1f;color:#fff}.attention{background:#b67b09;color:#fff}.ok{background:#485c43;color:#fff}.unknown{background:#69655e;color:#fff}details{margin-top:14px}footer{font-size:11px;color:#45413b;margin:18px 0}@media(max-width:800px){.summary{grid-template-columns:1fr 1fr}table{font-size:12px}}
</style></head><body><main>
<div class="brand"><b>CRIVO DJ</b><span>Diagnóstico do dispositivo</span></div>
<section class="panel notice"><strong>$(& $encode $Report.Overall)</strong><p>Dispositivo: $(& $encode $deviceLabel) — $(& $encode $Report.Root)</p><p>Esta verificação foi feita somente em modo de leitura. Nenhuma correção foi aplicada.</p></section>
<section class="summary">
<div class="card"><small>PROBLEMAS CONFIRMADOS</small><strong>$($Report.ProblemCount)</strong></div>
<div class="card"><small>PONTOS DE ATENÇÃO</small><strong>$($Report.AttentionCount)</strong></div>
<div class="card"><small>NÃO VERIFICADOS</small><strong>$($Report.UnknownCount)</strong></div>
<div class="card"><small>RESULTADO</small><strong class="overall">$(& $encode $Report.Overall)</strong></div>
</section>
<section class="panel"><h2>O que foi verificado</h2><table><thead><tr><th>VERIFICAÇÃO</th><th>RESULTADO</th><th>O QUE FOI ENCONTRADO</th><th>O QUE ISSO SIGNIFICA</th></tr></thead><tbody>$($rows.ToString())</tbody></table></section>
<section class="panel"><h2>Limites desta verificação</h2><ul>$limitations</ul><p><b>Próximo passo seguro:</b> revise este relatório e valide um backup antes de preparar qualquer reconstrução em outro local.</p><details><summary>Informações para suporte técnico</summary><p>Gerado em $(& $encode $Report.GeneratedAt). Arquivo técnico salvo ao lado deste relatório: $(& $encode ([IO.Path]::GetFileName($technicalPath))).</p></details></section>
<footer>CRIVO DJ v1 em desenvolvimento por MANELZ0RD</footer>
</main></body></html>
"@
    [IO.File]::WriteAllText($htmlPath,$html,[Text.UTF8Encoding]::new($false))
    $Report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $technicalPath -Encoding UTF8
    [pscustomobject]@{HtmlPath=$htmlPath;TechnicalPath=$technicalPath;Directory=$Directory}
}

Export-ModuleMember -Function Get-CrivoUsbDeviceInfo,Get-CrivoUsbHealth,Export-CrivoUsbHealthReport
