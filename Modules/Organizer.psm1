Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'History.psm1')

$script:Months = @('Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro')

function Get-TrackDate {
    param($Track, [string]$DateSource)
    switch ($DateSource) {
        'CreationTime' { return [datetime]$Track.Created }
        'MetadataYear' {
            if ($Track.Year -match '^\d{4}$') { return [datetime]::new([int]$Track.Year, 1, 1) }
            return $null
        }
        default { return [datetime]$Track.Modified }
    }
}

function Get-BpmRangeName {
    param([int]$Bpm, $Settings)
    if ($Bpm -le 0) { return [string]$Settings.UnknownValues.Bpm }
    $range = $Settings.BpmRanges | Where-Object { $Bpm -ge [int]$_.Min -and $Bpm -le [int]$_.Max } | Select-Object -First 1
    if ($range) { return [string]$range.Name }
    return "$Bpm BPM"
}

function Resolve-FolderTemplate {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)]$Track,
        [Parameter(Mandatory)]$Settings,
        [string]$DateSource = 'LastWriteTime',
        [ValidateSet('Separate','Root','Priority','Skip')][string]$MissingMetadataPolicy = 'Separate'
    )
    $date = Get-TrackDate -Track $Track -DateSource $DateSource
    $genreValue = [string]$Track.Genre
    $isMissingGenre = [string]::IsNullOrWhiteSpace($genreValue) -or ($Track.PSObject.Properties['MissingGenre'] -and $Track.MissingGenre)
    if ($MissingMetadataPolicy -eq 'Separate' -and $isMissingGenre) { $genreValue = '' }
    if ($genreValue) {
        $genreAlias = $Settings.GenreAliases.PSObject.Properties | Where-Object { $_.Name -eq $genreValue.Trim().ToUpperInvariant() } | Select-Object -First 1
        if ($genreAlias) { $genreValue = [string]$genreAlias.Value }
    }
    $genre = ConvertTo-SafePathPart $genreValue ([string]$Settings.UnknownValues.Genre)
    $artist = ConvertTo-SafePathPart $Track.Artist ([string]$Settings.UnknownValues.Artist)
    $album = ConvertTo-SafePathPart $Track.Album '_SEM ALBUM'
    $key = ConvertTo-SafePathPart $Track.Key ([string]$Settings.UnknownValues.Key)
    $parent = ConvertTo-SafePathPart (Split-Path $Track.Directory -Leaf) '_RAIZ'
    $rootFolder = if ($Track.PSObject.Properties['SourceRootFolder']) { ConvertTo-SafePathPart ([string]$Track.SourceRootFolder) '_RAIZ' } else { $parent }
    $yearToken = if ($date) { $date.ToString('yyyy') } else { [string]$Settings.UnknownValues.Date }
    $shortYearToken = if ($date) { $date.ToString('yy') } else { [string]$Settings.UnknownValues.Date }
    $monthToken = if ($date) { $script:Months[$date.Month - 1] } else { [string]$Settings.UnknownValues.Date }
    $monthNumberToken = if ($date) { $date.ToString('MM') } else { [string]$Settings.UnknownValues.Date }
    $dayToken = if ($date) { $date.ToString('dd') } else { [string]$Settings.UnknownValues.Date }
    $tokens = [ordered]@{
        '{AAAA}' = $yearToken; '{AA}' = $shortYearToken; '{MES}' = $monthToken
        '{MES_NUM}' = $monthNumberToken; '{DIA}' = $dayToken; '{GENERO}' = $genre
        '{ARTISTA}' = $artist; '{ALBUM}' = $album; '{ANO}' = $(if ($Track.Year) { ConvertTo-SafePathPart ([string]$Track.Year) } else { $yearToken })
        '{BPM}' = $(if ($Track.Bpm) { [string]$Track.Bpm } else { [string]$Settings.UnknownValues.Bpm })
        '{BPM_RANGE}' = Get-BpmRangeName -Bpm ([int]$Track.Bpm) -Settings $Settings
        '{KEY}' = $key; '{EXTENSAO}' = $Track.Extension.TrimStart('.').ToUpperInvariant(); '{FORMATO}' = $Track.Extension.TrimStart('.').ToUpperInvariant()
        '{PASTA_ORIGEM}' = $parent; '{PASTA_PAI}' = $parent; '{PASTA_RAIZ}' = $rootFolder
        '{NOME_ARQUIVO}' = ConvertTo-SafePathPart $Track.Title $Track.Name; '{TITULO}' = ConvertTo-SafePathPart $Track.Title $Track.Name
        '{BITRATE}' = $(if ($Track.Bitrate) { [string]$Track.Bitrate } else { '_SEM BITRATE' }); '{SAMPLE_RATE}' = $(if ($Track.SampleRate) { [string]$Track.SampleRate } else { '_SEM SAMPLE RATE' })
    }
    $resolved = $Template
    foreach ($token in $tokens.Keys) { $resolved = $resolved.Replace($token, [string]$tokens[$token]) }
    if ($resolved -match '\{[^{}]+\}') { throw "Variável de pasta desconhecida: $($Matches[0])" }
    $rootBecauseMissing = $MissingMetadataPolicy -eq 'Root' -and (
        (($Template -match '\{GENERO\}') -and $isMissingGenre) -or
        (($Template -match '\{(BPM|BPM_RANGE)\}') -and -not $Track.Bpm) -or
        (($Template -match '\{KEY\}') -and -not $Track.Key) -or
        (($Template -match '\{ARTISTA\}') -and -not $Track.Artist) -or
        (($Template -match '\{(AAAA|AA|MES|MES_NUM|DIA|ANO)\}') -and $DateSource -eq 'MetadataYear' -and -not ($Track.Year -match '^\d{4}$'))
    )
    if ($rootBecauseMissing) { return '' }
    $parts = $resolved -split '[\\/]' | Where-Object { $_ }
    if ($MissingMetadataPolicy -eq 'Root') {
        $parts = @($parts | Where-Object { $_ -notmatch '^_(SEM|PENDENTE)' })
    }
    return (($parts | ForEach-Object { ConvertTo-SafePathPart $_ }) -join [IO.Path]::DirectorySeparatorChar)
}

function Get-UniqueDestination {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $directory = Split-Path -Parent $Path; $name = [IO.Path]::GetFileNameWithoutExtension($Path); $ext = [IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 10000; $i++) {
        $candidate = Join-Path $directory ("{0} ({1}){2}" -f $name, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Não foi possível criar um nome único para $Path"
}

function Get-UniquePlannedDestination {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Reserved, $NextSuffix)
    $directory=Split-Path -Parent $Path; $name=[IO.Path]::GetFileNameWithoutExtension($Path); $ext=[IO.Path]::GetExtension($Path)
    $suffixKey=("$directory|$name|$ext").ToLowerInvariant()
    $start=2
    if($NextSuffix -and $NextSuffix.ContainsKey($suffixKey)){$start=[int]$NextSuffix[$suffixKey]}
    for($i=$start;$i -lt 10000;$i++){
        $candidate=Join-Path $directory ("{0} ({1}){2}" -f $name,$i,$ext)
        if(-not $Reserved.ContainsKey($candidate.ToLowerInvariant()) -and -not (Test-Path -LiteralPath $candidate)){
            if($NextSuffix){$NextSuffix[$suffixKey]=$i+1}
            return $candidate
        }
    }
    throw "Não foi possível criar um nome único para $Path"
}

function Get-CleanTrackFileName {
    param([Parameter(Mandatory)]$Track, $Settings)
    $extension = [string]$Track.Extension
    $baseName = [IO.Path]::GetFileNameWithoutExtension([string]$Track.Name)
    if ($Track.Artist -and $Track.Title) { $baseName = "$($Track.Artist) - $($Track.Title)" }
    elseif ($Track.Title) { $baseName = [string]$Track.Title }
    if (-not $Settings -or $Settings.NameRules.ReplaceUnderscores) { $baseName = $baseName -replace '_+', ' ' }
    if ($Settings -and $Settings.NameRules.RemoveTerms) {
        foreach ($term in @($Settings.NameRules.RemoveTerms)) { $baseName = $baseName -replace ("(?i)\s*[\[(]?" + [regex]::Escape([string]$term) + "[\])]?") , '' }
    } else { $baseName = $baseName -replace '(?i)\s*[\[(](320\s*kbps|free download|official audio|original mix)[\])]', '' }
    if ($Settings -and $Settings.NameRules.RemoveRepeatedText) {
        $baseName = [regex]::Replace($baseName, '(?i)\b([^\s]+)(\s+\1\b)+', '$1')
    }
    if ($Settings -and $Settings.NameRules.TitleCase) {
        $baseName = (Get-Culture).TextInfo.ToTitleCase($baseName.ToLower())
    }
    $baseName = ConvertTo-SafePathPart $baseName 'Faixa'
    return $baseName + $extension.ToLowerInvariant()
}

function New-OrganizationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Tracks,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Template,
        [ValidateSet('PreserveTree','FlattenSource','Custom')][string]$TreeMode = 'PreserveTree',
        [ValidateSet('Copy','Move')][string]$Action = 'Copy',
        [ValidateSet('Skip','Replace','Rename','CompareHash')][string]$Conflict = 'Rename',
        [string]$DateSource = 'LastWriteTime',
        [switch]$RenameFiles,
        [switch]$SeparateMissing,
        [ValidateSet('Separate','Root','Priority','Skip')][string]$MissingMetadataPolicy = 'Separate',
        [switch]$CreateReport,
        [switch]$CreateRestore,
        [Parameter(Mandatory)]$Settings
    )
    $sourceFull = [IO.Path]::GetFullPath($Source).TrimEnd('\\')
    $destFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\\')
    if ($sourceFull -eq $destFull) { throw 'A pasta de destino não pode ser igual à origem.' }
    $sourcePrefix = $sourceFull + [IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destFull + [IO.Path]::DirectorySeparatorChar
    $plan = [System.Collections.Generic.List[object]]::new(); $destinations = @{}; $nextSuffix=@{}
    foreach ($track in @($Tracks)) {
        $track | Add-Member -NotePropertyName Destination -NotePropertyValue '' -Force
        $track | Add-Member -NotePropertyName Rule -NotePropertyValue '' -Force
        $track | Add-Member -NotePropertyName Error -NotePropertyValue '' -Force
        $track | Add-Member -NotePropertyName Status -NotePropertyValue $(if ($track.Selected) { 'Analisado' } else { 'Desmarcada' }) -Force
    }
    $index = 0
    foreach ($track in @($Tracks | Where-Object Selected)) {
        $index++
        $trackFull = [IO.Path]::GetFullPath([string]$track.FullName)
        if (-not ($trackFull.Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase) -or $trackFull.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase))) {
            throw "A track está fora da pasta de origem selecionada: $trackFull"
        }
        $sourceRelative = Get-RelativePathSafe -BasePath $sourceFull -Path $track.Directory
        $sourceRootFolder = if ($sourceRelative -and $sourceRelative -ne '.') { ($sourceRelative -split '[\\/]')[0] } else { Split-Path $sourceFull -Leaf }
        $track | Add-Member -NotePropertyName SourceRootFolder -NotePropertyValue $sourceRootFolder -Force
        if ($SeparateMissing) { $MissingMetadataPolicy = 'Separate' }
        $rulePath = Resolve-FolderTemplate -Template $Template -Track $track -Settings $Settings -DateSource $DateSource -MissingMetadataPolicy $MissingMetadataPolicy
        $relativeFolder = ''
        if ($TreeMode -eq 'PreserveTree') {
            $relativeFolder = Get-RelativePathSafe -BasePath $sourceFull -Path $track.Directory
            if ($relativeFolder -eq '.') { $relativeFolder = '' }
        }
        $targetFolder = $destFull
        if ($relativeFolder) { $targetFolder = Join-Path $targetFolder $relativeFolder }
        if ($rulePath) { $targetFolder = Join-Path $targetFolder $rulePath }
        $fileName = if ($track.PSObject.Properties['OutputName'] -and $track.OutputName -and $track.OutputName -ne $track.Name) {
            (ConvertTo-SafePathPart ([IO.Path]::GetFileNameWithoutExtension([string]$track.OutputName)) 'Faixa') + $track.Extension.ToLowerInvariant()
        } elseif ($RenameFiles) { Get-CleanTrackFileName -Track $track -Settings $Settings } else { $track.Name }
        $target = [IO.Path]::GetFullPath((Join-Path $targetFolder $fileName))
        $status = 'Ready'; $message = ''
        if (-not $target.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $status = 'Error'; $message = 'O destino calculado saiu da pasta escolhida'
        }
        if (-not (Test-Path -LiteralPath $trackFull -PathType Leaf)) {
            $status = 'Error'; $message = 'O arquivo de origem não existe mais'
        }
        $requiredMissing = ($MissingMetadataPolicy -eq 'Skip') -and (
            (($Template -match '\{GENERO\}') -and -not $track.Genre) -or
            (($Template -match '\{BPM|\{BPM_RANGE\}') -and -not $track.Bpm) -or
            (($Template -match '\{KEY\}') -and -not $track.Key) -or
            (($Template -match '\{ARTISTA\}') -and -not $track.Artist)
        )
        if ($requiredMissing) { $status = 'Skip'; $message = 'Metadata necessária ausente' }
        if ($trackFull -eq $target) { $status = 'Skip'; $message = 'Origem e destino são iguais' }
        elseif ($destinations.ContainsKey($target.ToLowerInvariant())) {
            if ($Conflict -eq 'Rename') { $target = Get-UniquePlannedDestination -Path $target -Reserved $destinations -NextSuffix $nextSuffix }
            else { $status = 'Conflict'; $message = 'Mais de um arquivo aponta para o mesmo destino' }
        }
        $destinations[$target.ToLowerInvariant()] = $true
        if ($target.Length -ge 248) { $status = 'Error'; $message = 'Caminho de destino muito longo' }
        $track.Destination = $target; $track.Rule = $rulePath; $track.Status = $status; $track.Error = $message
        $plan.Add([pscustomobject]@{ Index=$index; Track=$track; Source=$track.FullName; Destination=$target; Rule=$rulePath; Status=$status; Message=$message })
    }
    [pscustomobject]@{ Id=((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)); CreatedAt=(Get-Date).ToString('o'); Source=$sourceFull; Destination=$destFull; Template=$Template; TreeMode=$TreeMode; Action=$Action; Conflict=$Conflict; DateSource=$DateSource; RenameFiles=[bool]$RenameFiles; MissingMetadataPolicy=$MissingMetadataPolicy; CreateReport=[bool]$CreateReport; CreateRestore=[bool]$CreateRestore; Items=$plan }
}

function ConvertTo-PlanReportRows {
    param([Parameter(Mandatory)]$Plan, $Completed)
    foreach ($item in @($Plan.Items)) {
        $done = @($Completed | Where-Object Index -eq $item.Index | Select-Object -First 1)
        [pscustomobject]@{
            Origem=$item.Source; Destino=$(if($done.Count){$done[0].Destination}else{$item.Destination}); Regra=$item.Rule; Acao=$Plan.Action
            Titulo=$item.Track.Title; Artista=$item.Track.Artist; Album=$item.Track.Album; Genero=$item.Track.Genre
            Ano=$item.Track.Year; BPM=$item.Track.Bpm; Tonalidade=$item.Track.Key; Codec=$item.Track.Codec
            Bitrate=$item.Track.Bitrate; SampleRate=$item.Track.SampleRate; BitDepth=$item.Track.BitDepth
            Duracao=$item.Track.Duration; ISRC=$item.Track.ISRC; ErroMetadata=$item.Track.MetadataError
            BitrateMin=$item.Track.BitrateMin; BitrateMax=$item.Track.BitrateMax; BitrateMedio=$item.Track.BitrateAverage; BitrateModo=$item.Track.BitrateMode; MapaBitrate=$item.Track.BitrateMap
            Qualidade=$item.Track.QualityStatus; Status=$(if($done.Count){$done[0].Result}else{$item.Status})
            Erro=$(if($done.Count){$done[0].Error}else{$item.Message})
        }
    }
}

function Export-OrganizationPlan {
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Path)
    $rows = @(ConvertTo-PlanReportRows -Plan $Plan -Completed @())
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.json') { Write-JsonFile -Path $Path -Value ([pscustomobject]@{ Plan=$Plan; Rows=$rows }) }
    else { $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
    return $Path
}

function Invoke-OrganizationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan, [scriptblock]$OnProgress)
    $blocking = @($Plan.Items | Where-Object Status -in @('Error','Conflict'))
    if ($blocking.Count) { throw "O plano contém $($blocking.Count) conflito(s) ou erro(s). Corrija antes de aplicar." }
    $completed = [System.Collections.Generic.List[object]]::new(); $items = @($Plan.Items | Where-Object Status -eq 'Ready')
    $backupRoot=Join-Path (Get-AppDataRoot) ("Backups\Operations\$($Plan.Id)")
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]; $result = ''; $errorMessage = ''; $backupPath=''; $destinationHash=''; $destination=[string]$item.Destination
        if ($OnProgress) { & $OnProgress ($i + 1) $items.Count ([IO.Path]::GetFileName($item.Source)) }
        try {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $item.Destination)) | Out-Null
            if (Test-Path -LiteralPath $destination) {
                switch ($Plan.Conflict) {
                    'Skip' { $result = 'Skipped' }
                    'Replace' {
                        if($Plan.CreateRestore){[IO.Directory]::CreateDirectory($backupRoot)|Out-Null;$backupPath=Join-Path $backupRoot (("{0:D6}-" -f [int]$item.Index)+[IO.Path]::GetFileName($destination));Copy-Item -LiteralPath $destination -Destination $backupPath -Force}
                    }
                    'Rename' { $destination = Get-UniqueDestination -Path $destination }
                    'CompareHash' {
                        $same = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                        if ($same) { $result = 'DuplicateSkipped' } else { $destination = Get-UniqueDestination -Path $destination }
                    }
                }
            }
            if (-not $result) {
                if ($Plan.Action -eq 'Move') { Move-Item -LiteralPath $item.Source -Destination $destination -Force; $result = 'Moved' }
                else { Copy-Item -LiteralPath $item.Source -Destination $destination -Force; $result = 'Copied' }
                try{$destinationHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}catch{}
            }
            Write-AppLog -Message "$result | $($item.Source) -> $destination"
        } catch {
            $result = 'Error'; $errorMessage = $_.Exception.Message
            if($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)){try{Copy-Item -LiteralPath $backupPath -Destination $destination -Force}catch{$errorMessage+=" | Falha ao restaurar o destino anterior: $($_.Exception.Message)"}}
            Write-AppLog -Message "$($item.Source) | $errorMessage" -Level ERROR
        }
        $completed.Add([pscustomobject]@{ Index=$item.Index; Source=$item.Source; Destination=$destination; Rule=$item.Rule; Result=$result; Error=$errorMessage; BackupPath=$backupPath; DestinationHash=$destinationHash; UndoneAt=$null })
    }
    $counts = [pscustomobject]@{ Total=$Plan.Items.Count; Ready=$items.Count; Copied=@($completed|Where-Object Result -eq 'Copied').Count; Moved=@($completed|Where-Object Result -eq 'Moved').Count; Skipped=@($completed|Where-Object Result -match 'Skipped').Count; Errors=@($completed|Where-Object Result -eq 'Error').Count }
    $operation = [pscustomobject]@{ Id=$Plan.Id; Date=(Get-Date).ToString('o'); Action=$Plan.Action; Template=$Plan.Template; MissingMetadataPolicy=$Plan.MissingMetadataPolicy; Conflict=$Plan.Conflict; Source=$Plan.Source; Destination=$Plan.Destination; Counts=$counts; Items=$completed; UndoneAt=$null }
    $historyPath = $null
    if ($Plan.CreateRestore) { $historyPath = Save-OperationHistory -Operation $operation }
    $reportPath = $null
    if ($Plan.CreateReport) {
        $reportFolder = Join-Path (Get-AppDataRoot) 'Reports'
        [IO.Directory]::CreateDirectory($reportFolder) | Out-Null
        $reportPath = Join-Path $reportFolder ("CRIVO-DJ-{0}.csv" -f $Plan.Id)
        ConvertTo-PlanReportRows -Plan $Plan -Completed $completed | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
    }
    [pscustomobject]@{ Operation=$operation; HistoryPath=$historyPath; ReportPath=$reportPath; Success=@($completed | Where-Object Result -in @('Copied','Moved')).Count; Skipped=@($completed | Where-Object Result -match 'Skipped').Count; Errors=@($completed | Where-Object Result -eq 'Error').Count }
}

Export-ModuleMember -Function Resolve-FolderTemplate, New-OrganizationPlan, Invoke-OrganizationPlan, Export-OrganizationPlan, Get-UniqueDestination, Get-CleanTrackFileName
