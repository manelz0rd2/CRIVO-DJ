Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Metadata.psm1')

function ConvertFrom-RekordboxLocation {
    param([string]$Location)
    if([string]::IsNullOrWhiteSpace($Location)){return ''}
    try{$value=[Uri]::UnescapeDataString(($Location -replace '^file://(localhost/)?',''));if($value -match '^/[A-Za-z]:/'){$value=$value.Substring(1)};return ($value -replace '/','\')}catch{return $Location}
}

function Import-RekordboxXmlMetadata {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object[]]$Tracks)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "XML do Rekordbox não encontrado: $Path"}
    [xml]$xml=Get-Content -LiteralPath $Path -Raw -Encoding UTF8;$nodes=@($xml.DJ_PLAYLISTS.COLLECTION.TRACK);$updated=0
    $byPath=@{};foreach($track in $Tracks){$byPath[[IO.Path]::GetFullPath($track.FullName).ToLowerInvariant()]=$track}
    foreach($node in $nodes){$location=ConvertFrom-RekordboxLocation ([string]$node.Location);if(-not$location){continue};try{$key=[IO.Path]::GetFullPath($location).ToLowerInvariant()}catch{continue};if(-not$byPath.ContainsKey($key)){continue};$track=$byPath[$key]
        foreach($pair in @(@('Name','Title'),@('Artist','Artist'),@('Album','Album'),@('Genre','Genre'),@('Key','Key'),@('Year','Year'),@('AverageBpm','Bpm'))){$value=[string]$node.($pair[0]);if($value -and ((-not $track.($pair[1])) -or $pair[1] -in @('Bpm','Key'))){if($pair[1] -eq 'Bpm'){$track.Bpm=[int][Math]::Round([double]$value)}else{$track.($pair[1])=$value};$updated++}}
        $track|Add-Member NoteProperty RekordboxTrackID ([string]$node.TrackID) -Force
    }
    return [pscustomobject]@{Path=$Path;Tracks=$Tracks.Count;Matched=$updated}
}

function Export-RekordboxXml {
    param([Parameter(Mandatory)][object[]]$Tracks,[Parameter(Mandatory)][string]$Path,[string]$PlaylistName='CRIVO DJ — Organizado')
    $settings=New-Object System.Xml.XmlWriterSettings;$settings.Indent=$true;$settings.Encoding=New-Object Text.UTF8Encoding($false)
    $writer=[Xml.XmlWriter]::Create($Path,$settings)
    try{$writer.WriteStartElement('DJ_PLAYLISTS');$writer.WriteAttributeString('Version','1.0.0');$writer.WriteStartElement('PRODUCT');$writer.WriteAttributeString('Name','rekordbox');$writer.WriteAttributeString('Version','7.0.0');$writer.WriteEndElement();$writer.WriteStartElement('COLLECTION');$writer.WriteAttributeString('Entries',[string]$Tracks.Count);$index=0
        foreach($track in $Tracks){$index++;$writer.WriteStartElement('TRACK');$writer.WriteAttributeString('TrackID',[string]$index);$writer.WriteAttributeString('Name',[string]$track.Title);$writer.WriteAttributeString('Artist',[string]$track.Artist);$writer.WriteAttributeString('Album',[string]$track.Album);$writer.WriteAttributeString('Genre',[string]$track.Genre);$writer.WriteAttributeString('Year',[string]$track.Year);$writer.WriteAttributeString('AverageBpm',[string]$track.Bpm);$writer.WriteAttributeString('Key',[string]$track.Key);$writer.WriteAttributeString('Location',([Uri]::new([IO.Path]::GetFullPath($track.FullName))).AbsoluteUri);$writer.WriteEndElement()}
        $writer.WriteEndElement();$writer.WriteStartElement('PLAYLISTS');$writer.WriteStartElement('NODE');$writer.WriteAttributeString('Type','0');$writer.WriteAttributeString('Name','ROOT');$writer.WriteStartElement('NODE');$writer.WriteAttributeString('Type','1');$writer.WriteAttributeString('Name',$PlaylistName);$index=0;foreach($track in $Tracks){$index++;$writer.WriteStartElement('TRACK');$writer.WriteAttributeString('Key',[string]$index);$writer.WriteEndElement()};$writer.WriteEndElement();$writer.WriteEndElement();$writer.WriteEndElement();$writer.WriteEndElement()}finally{$writer.Dispose()};return $Path
}

function Get-RekordboxXmlLibrary {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "XML do Rekordbox não encontrado: $Path"}
    [xml]$xml=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $tracks=New-Object Collections.Generic.List[object];$byId=@{}
    foreach($node in @($xml.DJ_PLAYLISTS.COLLECTION.TRACK)){
        if(-not$node){continue};$location=ConvertFrom-RekordboxLocation ([string]$node.GetAttribute('Location'))
        $item=[pscustomobject]@{TrackID=[string]$node.GetAttribute('TrackID');Name=[string]$node.GetAttribute('Name');Artist=[string]$node.GetAttribute('Artist');Album=[string]$node.GetAttribute('Album');Genre=[string]$node.GetAttribute('Genre');Bpm=[string]$node.GetAttribute('AverageBpm');Key=[string]$node.GetAttribute('Key');Rating=[string]$node.GetAttribute('Rating');Comments=[string]$node.GetAttribute('Comments');Location=$location;Exists=([bool]($location -and (Test-Path -LiteralPath $location -PathType Leaf)));PlaylistCount=0;PlaylistNames=@();PlaylistDisplay='—'}
        $tracks.Add($item);if($item.TrackID){$byId[$item.TrackID]=$item}
    }
    $playlists=New-Object Collections.Generic.List[object]
    function Add-PlaylistNodes([object]$Node,[string]$Parent){
        if(-not$Node){return};foreach($child in @($Node.SelectNodes('./NODE'))){
            $name=[string]$child.Name;$folder=if($Parent){"$Parent / $name"}else{$name}
            if([string]$child.Type -eq '1'){$keys=@($child.SelectNodes('./TRACK')|ForEach-Object{[string]$_.Key}|Where-Object{$_});foreach($key in $keys){if($byId.ContainsKey($key)){$byId[$key].PlaylistCount++;$byId[$key].PlaylistNames=@($byId[$key].PlaylistNames)+$folder;$byId[$key].PlaylistDisplay=(@($byId[$key].PlaylistNames|Select-Object -Unique)-join '; ')}};$playlists.Add([pscustomobject]@{Name=$name;Path=$folder;TrackCount=$keys.Count;TrackIDs=$keys})}
            Add-PlaylistNodes -Node $child -Parent $folder
        }
    }
    Add-PlaylistNodes -Node $xml.DJ_PLAYLISTS.PLAYLISTS -Parent ''
    return [pscustomobject]@{Path=$Path;Product=[string]$xml.DJ_PLAYLISTS.PRODUCT.Name;Version=[string]$xml.DJ_PLAYLISTS.PRODUCT.Version;Tracks=$tracks.ToArray();Playlists=$playlists.ToArray();TracksById=$byId}
}

function Get-AuditTechnicalInfo {
    param([string]$Path,[Parameter(Mandatory)]$Settings,[int]$KnownBitrate=0,[int]$KnownSampleRate=0,[switch]$Fast)
    $result=[ordered]@{Exists=$false;Readable=$false;Corrupt=$false;RootUnavailable=$false;Root='';NormalizedPath='';Size=0L;Bitrate=0;SampleRate=0;Codec='';QualityIssue='';Error='';Metadata=$null}
    if([string]::IsNullOrWhiteSpace($Path)){return [pscustomobject]$result}
    $normalized=$Path.Trim().Trim('"')
    try{
        if($normalized -match '^(?i)file:'){$uri=[Uri]$normalized;if($uri.IsFile){$normalized=[Uri]::UnescapeDataString($uri.LocalPath)}}
        $normalized=$normalized -replace '/','\'
        if($normalized -match '^\\([A-Za-z]:\\)'){$normalized=$normalized.Substring(1)}
        $normalized=[IO.Path]::GetFullPath($normalized);$result.NormalizedPath=$normalized;$root=[IO.Path]::GetPathRoot($normalized);$result.Root=$root
        if($root -match '^[A-Za-z]:\\$'){
            try{$drive=[IO.DriveInfo]::new($root);if(-not$drive.IsReady){$result.RootUnavailable=$true;$result.Error="A unidade $root está indisponível ou bloqueada";return [pscustomobject]$result}}catch{$result.RootUnavailable=$true;$result.Error="A unidade $root está indisponível ou bloqueada";return [pscustomobject]$result}
        }elseif($root -and -not(Test-Path -LiteralPath $root -PathType Container)){$result.RootUnavailable=$true;$result.Error="A origem $root está indisponível";return [pscustomobject]$result}
    }catch{$result.NormalizedPath=$normalized;$result.Error=$_.Exception.Message;return [pscustomobject]$result}
    if(-not(Test-Path -LiteralPath $normalized -PathType Leaf)){return [pscustomobject]$result}
    $result.Exists=$true
    try{
        $file=Get-Item -LiteralPath $normalized -Force -ErrorAction Stop;$result.Size=[int64]$file.Length;$result.Codec=$file.Extension.TrimStart('.').ToUpperInvariant()
        $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$stream.Dispose();$result.Readable=$true
        if($file.Length -eq 0){$result.Corrupt=$true;$result.Error='Arquivo vazio';return [pscustomobject]$result}
        if($Fast -and ($KnownBitrate -gt 0 -or $KnownSampleRate -gt 0)){$result.Bitrate=$KnownBitrate;$result.SampleRate=$KnownSampleRate}
        else{$meta=Get-AudioMetadata -File $file -Settings $Settings;$result.Metadata=$meta;$result.Bitrate=[int]$meta.Bitrate;$result.SampleRate=[int]$meta.SampleRate;$result.Corrupt=[bool]$meta.IsCorrupt;if($meta.MetadataError){$result.Error=[string]$meta.MetadataError}}
        $quality=New-Object Collections.Generic.List[string]
        if($file.Extension.ToLowerInvariant() -eq '.mp3' -and $result.Bitrate -gt 0 -and $result.Bitrate -lt [int]$Settings.Quality.MinimumMp3Bitrate){$quality.Add("Bitrate baixo: $($result.Bitrate) kbps")}
        if($result.SampleRate -gt 0 -and $result.SampleRate -lt [int]$Settings.Quality.MinimumSampleRate){$quality.Add("Sample rate baixo: $($result.SampleRate) Hz")}
        $result.QualityIssue=$quality -join '; '
    }catch{$result.Corrupt=$true;$result.Error=$_.Exception.Message}
    return [pscustomobject]$result
}

function Get-AuditIdentityText {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return ''}
    $normalized=$Value.Normalize([Text.NormalizationForm]::FormD)
    $builder=New-Object Text.StringBuilder
    foreach($character in $normalized.ToCharArray()){
        if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$builder.Append($character)}
    }
    return (($builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant() -replace '[^\p{L}\p{Nd}]',''))
}

function Add-AuditRowFinding {
    param([Parameter(Mandatory)]$Row,[Parameter(Mandatory)][string]$Category,[Parameter(Mandatory)][string]$Message,[string]$IssueType='',[string]$DuplicateType='')
    $categories=@(([string]$Row.IssueCategories -split ';')|Where-Object{$_})
    if($categories -notcontains $Category){$categories+=,$Category;$Row.IssueCategories=$categories -join ';';$Row.IssueCount=[int]$Row.IssueCount+1}
    $current=[string]$Row.Issues
    if(-not$current -or $current -eq 'Nenhum problema encontrado'){$Row.Issues=$Message}elseif($current -notlike "*$Message*"){$Row.Issues="$current; $Message"}
    if($IssueType -and ([string]$Row.IssueType -eq 'OK' -or -not$Row.IssueType)){$Row.IssueType=$IssueType}
    if($DuplicateType){
        $types=@(([string]$Row.DuplicateType -split '; ')|Where-Object{$_});if($types -notcontains $DuplicateType){$types+=,$DuplicateType};$Row.DuplicateType=$types -join '; '
    }
}

function Add-AuditDuplicateAndLocationFindings {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [string]$ScopeRoot='',
        [string[]]$AudioExtensions=@('.mp3','.wav','.flac','.aiff','.aif','.m4a','.aac','.ogg','.opus','.wma')
    )
    $normalizedExtensions=@($AudioExtensions|ForEach-Object{if($_.StartsWith('.')){$_.ToLowerInvariant()}else{'.'+$_.ToLowerInvariant()}})
    $audioRows=@($Rows|Where-Object{$_.Exists -and $_.Location -and ($normalizedExtensions -contains [IO.Path]::GetExtension([string]$_.Location).ToLowerInvariant())})
    $rootSet=@{};$parentCounts=@{}
    foreach($row in $audioRows){
        $path=[IO.Path]::GetFullPath([string]$row.Location);$directory=Split-Path -Parent $path;$root=[IO.Path]::GetPathRoot($path);$relativeDirectory=$directory
        $depthRoot=$root
        if($ScopeRoot){try{$candidate=[IO.Path]::GetFullPath($ScopeRoot);if($directory.StartsWith($candidate,[StringComparison]::OrdinalIgnoreCase)){$depthRoot=$candidate}}catch{}}
        if($depthRoot -and $directory.StartsWith($depthRoot,[StringComparison]::OrdinalIgnoreCase)){$relativeDirectory=$directory.Substring($depthRoot.Length)}
        $depth=@($relativeDirectory -split '[\\/]+'|Where-Object{$_}).Count;$sourceFolder=Split-Path $directory -Leaf
        $fileSize=0L;try{$fileSize=(Get-Item -LiteralPath $path -Force).Length}catch{}
        $row|Add-Member NoteProperty SourceFolder $sourceFolder -Force
        $row|Add-Member NoteProperty FolderDepth $depth -Force
        $row|Add-Member NoteProperty StorageRoot $root -Force
        $row|Add-Member NoteProperty FileSize ([int64]$fileSize) -Force
        $row|Add-Member NoteProperty DuplicateType '' -Force
        if($root){$rootSet[$root.ToLowerInvariant()]=$true};$parentKey=$directory.ToLowerInvariant();if(-not$parentCounts.ContainsKey($parentKey)){$parentCounts[$parentKey]=0};$parentCounts[$parentKey]++
    }

    foreach($group in @($audioRows|Group-Object{([IO.Path]::GetFullPath([string]$_.Location)).ToLowerInvariant()}|Where-Object Count -gt 1)){
        foreach($row in $group.Group){Add-AuditRowFinding -Row $row -Category 'Duplicate' -Message 'A mesma localização aparece mais de uma vez na coleção' -IssueType 'Duplicata' -DuplicateType 'Mesmo caminho'}
    }

    $hashCache=@{}
    foreach($sizeGroup in @($audioRows|Where-Object{$_.FileSize -gt 0}|Group-Object FileSize|Where-Object Count -gt 1)){
        $byHash=@{}
        foreach($row in $sizeGroup.Group){
            $path=[IO.Path]::GetFullPath([string]$row.Location);$key=$path.ToLowerInvariant()
            if(-not$hashCache.ContainsKey($key)){try{$hashCache[$key]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}catch{$hashCache[$key]=''}}
            $hash=[string]$hashCache[$key];if(-not$hash){continue};if(-not$byHash.ContainsKey($hash)){$byHash[$hash]=New-Object Collections.Generic.List[object]};$byHash[$hash].Add($row)
        }
        foreach($hash in @($byHash.Keys)){
            $group=@($byHash[$hash].ToArray());$uniquePaths=@($group|ForEach-Object{([IO.Path]::GetFullPath([string]$_.Location)).ToLowerInvariant()}|Select-Object -Unique)
            if($uniquePaths.Count -gt 1){foreach($row in $group){Add-AuditRowFinding -Row $row -Category 'Duplicate' -Message 'Conteúdo idêntico encontrado em outro caminho' -IssueType 'Duplicata' -DuplicateType 'Conteúdo idêntico'}}
        }
    }

    $identityGroups=@{}
    foreach($row in $audioRows){$artist=Get-AuditIdentityText ([string]$row.Artist);$title=Get-AuditIdentityText ([string]$row.Title);if(-not$artist -or -not$title){continue};$key="$artist|$title";if(-not$identityGroups.ContainsKey($key)){$identityGroups[$key]=New-Object Collections.Generic.List[object]};$identityGroups[$key].Add($row)}
    foreach($key in @($identityGroups.Keys)){
        $group=@($identityGroups[$key].ToArray());$uniquePaths=@($group|ForEach-Object{([IO.Path]::GetFullPath([string]$_.Location)).ToLowerInvariant()}|Select-Object -Unique)
        if($uniquePaths.Count -gt 1){foreach($row in $group){if(([string]$row.DuplicateType) -notmatch 'Conteúdo idêntico'){Add-AuditRowFinding -Row $row -Category 'PossibleDuplicate' -Message 'Mesmo artista e título em arquivos diferentes; revisar versão, remix ou duplicidade' -IssueType 'Possível duplicata' -DuplicateType 'Artista + título'}}}
    }

    $distinctParents=$parentCounts.Count;$singleParentTracks=@($audioRows|Where-Object{$parentCounts[(Split-Path -Parent ([IO.Path]::GetFullPath([string]$_.Location))).ToLowerInvariant()] -le 2})
    $fragmented=($audioRows.Count -ge 20 -and $distinctParents -ge 10 -and $singleParentTracks.Count -ge [Math]::Ceiling($audioRows.Count*0.35))
    $depths=@($audioRows|ForEach-Object{[int]$_.FolderDepth}|Sort-Object);$medianDepth=if($depths.Count){[int]$depths[[Math]::Floor(($depths.Count-1)/2)]}else{0};$deepThreshold=[Math]::Max(8,$medianDepth+3)
    foreach($row in $audioRows){
        $directory=(Split-Path -Parent ([IO.Path]::GetFullPath([string]$row.Location))).ToLowerInvariant();$deep=[int]$row.FolderDepth -ge $deepThreshold;$isolated=$fragmented -and $parentCounts[$directory] -le 2
        if($deep -or $isolated){$reason=if($deep -and $isolated){'Caminho profundo e pasta com poucas tracks'}elseif($deep){'Caminho excessivamente profundo'}else{'Track isolada numa biblioteca espalhada por muitas pastas'};Add-AuditRowFinding -Row $row -Category 'Location' -Message "$reason; considere consolidar antes de relocalizar no Rekordbox" -IssueType 'Origem dispersa'}
    }
    $exact=@($audioRows|Where-Object{$_.IssueCategories -match '(^|;)Duplicate(;|$)'}).Count;$possible=@($audioRows|Where-Object{$_.IssueCategories -match '(^|;)PossibleDuplicate(;|$)'}).Count;$location=@($audioRows|Where-Object{$_.IssueCategories -match '(^|;)Location(;|$)'}).Count
    return [pscustomobject]@{ExactDuplicates=$exact;PossibleDuplicates=$possible;LocationIssues=$location;SourceFolders=$distinctParents;StorageRoots=$rootSet.Count;Fragmented=$fragmented}
}

function Get-RekordboxAudit {
    param([Parameter(Mandatory)]$Library,[Parameter(Mandatory)]$Settings,[object[]]$LocalTracks=@(),[switch]$CompareLocal,[scriptblock]$OnProgress)
    [object[]]$LocalTracks=@($LocalTracks);$localTrackCount=@($LocalTracks).Count
    $rows=New-Object Collections.Generic.List[object];$seen=@{};$localByPath=@{};$technicalCache=@{};$libraryTracks=@($Library.Tracks)
    foreach($track in @($LocalTracks)){if($track.FullName){try{$localByPath[[IO.Path]::GetFullPath([string]$track.FullName).ToLowerInvariant()]=$track}catch{}}}
    for($index=0;$index -lt $libraryTracks.Count;$index++){
        $track=$libraryTracks[$index];if($OnProgress){& $OnProgress ($index+1) $libraryTracks.Count ([string]$track.Name)}
        $pathKey='';if($track.Location){try{$pathKey=[IO.Path]::GetFullPath([string]$track.Location).ToLowerInvariant()}catch{$pathKey=[string]$track.Location}}
        $duplicate=$false;if($pathKey){if($seen.ContainsKey($pathKey)){$duplicate=$true}else{$seen[$pathKey]=$true}}
        if($pathKey -and $technicalCache.ContainsKey($pathKey)){$technical=$technicalCache[$pathKey]}else{$knownBitrate=if($track.PSObject.Properties['Bitrate']){[int]$track.Bitrate}else{0};$knownSampleRate=if($track.PSObject.Properties['SampleRate']){[int]$track.SampleRate}else{0};$technical=Get-AuditTechnicalInfo -Path ([string]$track.Location) -Settings $Settings -KnownBitrate $knownBitrate -KnownSampleRate $knownSampleRate -Fast;if($pathKey){$technicalCache[$pathKey]=$technical}}
        $issues=New-Object Collections.Generic.List[string];$categories=New-Object Collections.Generic.List[string]
        if($technical.RootUnavailable){$issues.Add([string]$technical.Error);$categories.Add('Unavailable')}
        elseif(-not$technical.Exists){$issues.Add('O caminho salvo no Rekordbox não existe');$categories.Add('Missing')}
        elseif(-not$technical.Readable -or $technical.Corrupt){$detail=if($technical.Error){$technical.Error}else{'Arquivo inacessível ou corrompido'};$issues.Add($detail);$categories.Add('Integrity')}
        if($duplicate){$issues.Add('Caminho duplicado na coleção');$categories.Add('Duplicate')}
        $missingMetadata=New-Object Collections.Generic.List[string];$trackAlbum=if($track.PSObject.Properties['Album']){[string]$track.Album}else{''};$trackYear=if($track.PSObject.Properties['Year']){[string]$track.Year}else{''}
        if(-not$track.Name){$missingMetadata.Add('título')};if(-not$track.Artist){$missingMetadata.Add('artista')};if(-not$trackAlbum){$missingMetadata.Add('álbum')};if(-not$track.Genre){$missingMetadata.Add('gênero')};if(-not$trackYear){$missingMetadata.Add('ano')};if(-not$track.Bpm){$missingMetadata.Add('BPM')};if(-not$track.Key){$missingMetadata.Add('tonalidade')}
        if($missingMetadata.Count){$issues.Add('Dados faltantes: '+($missingMetadata -join ', '));$categories.Add('Metadata')}
        $analysisValue=if($track.PSObject.Properties['Analysis']){[string]$track.Analysis}else{''}
        if(-not$analysisValue){$issues.Add('Sem dados de análise do Rekordbox');$categories.Add('Analysis')}
        if($technical.QualityIssue){$issues.Add([string]$technical.QualityIssue);$categories.Add('Quality')}
        $local=$null;if($pathKey -and $localByPath.ContainsKey($pathKey)){$local=$localByPath[$pathKey]}
        if(($CompareLocal -or $localTrackCount) -and -not$local){$issues.Add('Fora da pasta ou HD usado na comparação');$categories.Add('Comparison')}
        $diff=New-Object Collections.Generic.List[string]
        if($local){foreach($field in @('Artist','Genre','Bpm','Key')){$localValue=[string]$local.$field;$rbValue=[string]$track.$field;if($localValue -and $rbValue -and $localValue -ne $rbValue){$diff.Add($field)}}}
        if($diff.Count){$issues.Add('Dados diferentes no arquivo: '+($diff -join ', '));if(-not$categories.Contains('Metadata')){$categories.Add('Metadata')}}
        $categoryText=$categories -join ';';$issueType=if($categories.Contains('Missing')){'Sem arquivo físico'}elseif($categories.Contains('Integrity')){'Arquivo suspeito'}elseif($categories.Contains('Quality')){'Qualidade suspeita'}elseif($categories.Contains('Metadata')){'Dados faltantes'}elseif($categories.Contains('Analysis')){'Sem análise'}elseif($categories.Contains('Duplicate')){'Duplicata'}elseif($categories.Contains('Comparison')){'Fora da comparação'}elseif($categories.Contains('Unavailable')){'Não verificada'}else{'OK'}
        $actionableCount=@($categories|Where-Object{$_ -ne 'Unavailable'}).Count
        [object[]]$playlistNames=if($track.PSObject.Properties['PlaylistNames']){@($track.PlaylistNames|Where-Object{$_}|Select-Object -Unique)}else{@()};$playlistDisplay=if($playlistNames.Count){$playlistNames -join '; '}else{'—'}
        $rows.Add([pscustomobject]@{TrackID=$track.TrackID;Title=$(if($track.Name){$track.Name}else{[IO.Path]::GetFileNameWithoutExtension([string]$track.Location)});Artist=$track.Artist;Album=$trackAlbum;Genre=$track.Genre;Year=$trackYear;Bpm=$track.Bpm;Key=$track.Key;Bitrate=$technical.Bitrate;SampleRate=$technical.SampleRate;Codec=$technical.Codec;Analysis=$(if($analysisValue){$analysisValue}else{'—'});Location=$(if($technical.NormalizedPath){$technical.NormalizedPath}else{$track.Location});Exists=$technical.Exists;Readable=$technical.Readable;Verified=(-not$technical.RootUnavailable);PlaylistCount=$track.PlaylistCount;PlaylistNames=$playlistNames;PlaylistDisplay=$playlistDisplay;MatchedLocal=[bool]$local;LocalOnly=$false;IssueCategories=$categoryText;IssueType=$issueType;IssueCount=$actionableCount;Issues=$(if($issues.Count){$issues -join '; '}else{'Nenhum problema encontrado'});DuplicateType='';SourceFolder='';FolderDepth=0;StorageRoot='';FileSize=[int64]$technical.Size})
    }
    $unmatchedLocal=0;foreach($track in @($LocalTracks)){try{$key=[IO.Path]::GetFullPath([string]$track.FullName).ToLowerInvariant();if(-not$seen.ContainsKey($key)){$unmatchedLocal++;$title=if($track.PSObject.Properties['Title']){[string]$track.Title}else{[IO.Path]::GetFileNameWithoutExtension([string]$track.FullName)};$artist=if($track.PSObject.Properties['Artist']){[string]$track.Artist}else{''};$rows.Add([pscustomobject]@{TrackID='';Title=$title;Artist=$artist;Album=$(if($track.PSObject.Properties['Album']){[string]$track.Album}else{''});Genre=$(if($track.PSObject.Properties['Genre']){[string]$track.Genre}else{''});Year=$(if($track.PSObject.Properties['Year']){[string]$track.Year}else{''});Bpm=$(if($track.PSObject.Properties['Bpm']){[string]$track.Bpm}else{''});Key=$(if($track.PSObject.Properties['Key']){[string]$track.Key}else{''});Bitrate=$(if($track.PSObject.Properties['Bitrate']){[int]$track.Bitrate}else{0});SampleRate=$(if($track.PSObject.Properties['SampleRate']){[int]$track.SampleRate}else{0});Codec=$(if($track.PSObject.Properties['Codec']){[string]$track.Codec}else{''});Analysis='—';Location=[string]$track.FullName;Exists=$true;Readable=$true;PlaylistCount=0;PlaylistNames=@();PlaylistDisplay='—';MatchedLocal=$false;LocalOnly=$true;IssueCategories='LocalOnly';IssueType='Fora da coleção';IssueCount=1;Issues='No computador, fora da coleção do Rekordbox'})}}catch{}}
    $findings=Add-AuditDuplicateAndLocationFindings -Rows $rows.ToArray() -AudioExtensions $Settings.AudioExtensions;$missing=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Missing(;|$)'}).Count;$quality=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Quality(;|$)'}).Count;$metadata=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Metadata(;|$)'}).Count;$analysis=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Analysis(;|$)'}).Count;$problem=@($rows|Where-Object{$_.IssueCount -gt 0}).Count;$duplicates=[int]$findings.ExactDuplicates
    $unavailable=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Unavailable(;|$)'}).Count
    return [pscustomobject]@{Mode='Library';Rows=$rows.ToArray();Total=$libraryTracks.Count;Playlists=@($Library.Playlists).Count;MissingFiles=$missing;UnavailableFiles=$unavailable;QualityIssues=$quality;MetadataIssues=$metadata;AnalysisIssues=$analysis;DataProblems=@($rows|Where-Object{$_.IssueCategories -match '(^|;)(Metadata|Analysis)(;|$)'}).Count;Problems=$problem;DuplicatePaths=$duplicates;PossibleDuplicates=[int]$findings.PossibleDuplicates;LocationIssues=[int]$findings.LocationIssues;SourceFolders=[int]$findings.SourceFolders;StorageRoots=[int]$findings.StorageRoots;UnmatchedLocal=$unmatchedLocal}
}

function Get-RekordboxUsbAudit {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Settings,[scriptblock]$OnProgress)
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){throw "Dispositivo não encontrado: $Root"}
    $rootPath=[IO.Path]::GetFullPath($Root);$rows=New-Object Collections.Generic.List[object]
    $extensions=@($Settings.AudioExtensions|ForEach-Object{$_.ToLowerInvariant()});$audioFiles=@(Get-ChildItem -LiteralPath $rootPath -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$extensions -contains $_.Extension.ToLowerInvariant()})
    for($index=0;$index -lt $audioFiles.Count;$index++){
        $file=$audioFiles[$index];if($OnProgress){& $OnProgress ($index+1) ([Math]::Max(1,$audioFiles.Count)) $file.Name}
        $technical=Get-AuditTechnicalInfo -Path $file.FullName -Settings $Settings;$issues=New-Object Collections.Generic.List[string];$categories=New-Object Collections.Generic.List[string]
        if(-not$technical.Readable -or $technical.Corrupt){$issues.Add($(if($technical.Error){$technical.Error}else{'Arquivo inacessível ou corrompido'}));$categories.Add('Integrity')}
        if($technical.QualityIssue){$issues.Add([string]$technical.QualityIssue);$categories.Add('Quality')}
        $meta=$technical.Metadata
        $missingMetadata=New-Object Collections.Generic.List[string]
        if($meta){if(-not$meta.HasTitleMetadata){$missingMetadata.Add('título')};if(-not$meta.Artist){$missingMetadata.Add('artista')};if(-not$meta.Album){$missingMetadata.Add('álbum')};if(-not$meta.Genre){$missingMetadata.Add('gênero')};if(-not$meta.Year){$missingMetadata.Add('ano')};if(-not$meta.Bpm){$missingMetadata.Add('BPM')};if(-not$meta.Key){$missingMetadata.Add('tonalidade')}}
        if($missingMetadata.Count){$issues.Add('Dados faltantes: '+($missingMetadata -join ', '));$categories.Add('Metadata')}
        $issueType=if($categories.Contains('Integrity')){'Arquivo suspeito'}elseif($categories.Contains('Quality')){'Qualidade suspeita'}elseif($categories.Contains('Metadata')){'Dados faltantes'}else{'OK'}
        $rows.Add([pscustomobject]@{TrackID='';Title=$(if($meta -and $meta.Title){$meta.Title}else{$file.BaseName});Artist=$(if($meta){$meta.Artist}else{''});Album=$(if($meta){$meta.Album}else{''});Genre=$(if($meta){$meta.Genre}else{''});Year=$(if($meta){$meta.Year}else{''});Bpm=$(if($meta){$meta.Bpm}else{''});Key=$(if($meta){$meta.Key}else{''});Bitrate=$technical.Bitrate;SampleRate=$technical.SampleRate;Codec=$technical.Codec;Analysis='—';Location=$file.FullName;Exists=$true;Readable=$technical.Readable;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories=$categories -join ';';IssueType=$issueType;IssueCount=$issues.Count;Issues=$(if($issues.Count){$issues -join '; '}else{'Nenhum problema encontrado'});DuplicateType='';SourceFolder='';FolderDepth=0;StorageRoot='';FileSize=[int64]$technical.Size})
    }
    $rekordboxRoot=Join-Path $rootPath 'PIONEER\rekordbox';$structureIssues=0;$analysisIssues=0
    if(-not(Test-Path -LiteralPath $rekordboxRoot -PathType Container)){
        $structureIssues++;$rows.Add([pscustomobject]@{TrackID='';Title='Estrutura do Rekordbox';Artist='';Genre='';Bpm='';Key='';Bitrate=0;SampleRate=0;Codec='';Analysis='—';Location=$rekordboxRoot;Exists=$false;Readable=$false;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories='Structure';IssueType='Estrutura ausente';IssueCount=1;Issues='A pasta PIONEER\rekordbox não foi encontrada'})
    }else{
        $databases=@(Get-ChildItem -LiteralPath $rekordboxRoot -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Name -in @('export.pdb','exportLibrary.db','master.db')})
        if(-not$databases.Count){$structureIssues++;$rows.Add([pscustomobject]@{TrackID='';Title='Banco do dispositivo';Artist='';Genre='';Bpm='';Key='';Bitrate=0;SampleRate=0;Codec='DB';Analysis='—';Location=$rekordboxRoot;Exists=$false;Readable=$false;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories='Structure';IssueType='Banco ausente';IssueCount=1;Issues='Nenhum banco exportado do Rekordbox foi localizado'})}
        foreach($database in $databases){try{if($database.Length -eq 0){throw 'Banco vazio'};$stream=[IO.File]::Open($database.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$stream.Dispose()}catch{$structureIssues++;$rows.Add([pscustomobject]@{TrackID='';Title=$database.Name;Artist='';Genre='';Bpm='';Key='';Bitrate=0;SampleRate=0;Codec='DB';Analysis='—';Location=$database.FullName;Exists=$true;Readable=$false;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories='Structure';IssueType='Banco ilegível';IssueCount=1;Issues=$_.Exception.Message})}}
    }
    $analysisRoot=Join-Path $rootPath 'PIONEER\USBANLZ';[object[]]$analysisFiles=@();if(Test-Path -LiteralPath $analysisRoot -PathType Container){$analysisFiles=@(Get-ChildItem -LiteralPath $analysisRoot -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension.ToUpperInvariant() -in @('.DAT','.EXT','.2EX')})}
    if(-not$analysisFiles.Count){$analysisIssues++;$rows.Add([pscustomobject]@{TrackID='';Title='Dados de análise';Artist='';Genre='';Bpm='';Key='';Bitrate=0;SampleRate=0;Codec='ANLZ';Analysis='Ausente';Location=$analysisRoot;Exists=$false;Readable=$false;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories='Analysis;Structure';IssueType='Análise ausente';IssueCount=1;Issues='Nenhum arquivo de análise do Rekordbox foi encontrado'})}
    foreach($analysisFile in $analysisFiles){
        $problem='';try{if($analysisFile.Length -eq 0){throw 'Arquivo de análise vazio'};$stream=[IO.File]::Open($analysisFile.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$stream.Dispose();if($analysisFile.Extension.ToUpperInvariant() -ne '.DAT'){$dat=[IO.Path]::ChangeExtension($analysisFile.FullName,'.DAT');if(-not(Test-Path -LiteralPath $dat -PathType Leaf)){$problem='Arquivo de análise sem o DAT correspondente'}}}catch{$problem=$_.Exception.Message}
        if($problem){$analysisIssues++;$rows.Add([pscustomobject]@{TrackID='';Title=$analysisFile.Name;Artist='';Genre='';Bpm='';Key='';Bitrate=0;SampleRate=0;Codec='ANLZ';Analysis='Incompleta';Location=$analysisFile.FullName;Exists=$true;Readable=$false;PlaylistCount=0;MatchedLocal=$false;LocalOnly=$false;IssueCategories='Analysis;Structure';IssueType='Análise incompleta';IssueCount=1;Issues=$problem})}
    }
    $findings=Add-AuditDuplicateAndLocationFindings -Rows $rows.ToArray() -ScopeRoot $rootPath -AudioExtensions $Settings.AudioExtensions;$quality=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Quality(;|$)'}).Count;$metadata=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Metadata(;|$)'}).Count;$integrity=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Integrity(;|$)'}).Count;$problem=@($rows|Where-Object{$_.IssueCount -gt 0}).Count
    return [pscustomobject]@{Mode='Usb';Root=$rootPath;Rows=$rows.ToArray();Total=$audioFiles.Count;Playlists=0;MissingFiles=$integrity;QualityIssues=$quality;MetadataIssues=$metadata;AnalysisIssues=$analysisIssues;DataProblems=($metadata+$analysisIssues+$structureIssues);Problems=$problem;DuplicatePaths=[int]$findings.ExactDuplicates;PossibleDuplicates=[int]$findings.PossibleDuplicates;LocationIssues=[int]$findings.LocationIssues;SourceFolders=[int]$findings.SourceFolders;StorageRoots=[int]$findings.StorageRoots;UnmatchedLocal=0;StructureIssues=$structureIssues;AnalysisFileCount=$analysisFiles.Count}
}

function Export-RekordboxAudit {
    param([Parameter(Mandatory)]$Audit,[Parameter(Mandatory)][string]$Path)
    $extension=[IO.Path]::GetExtension($Path).ToLowerInvariant();if($extension -eq '.json'){$Audit|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Path -Encoding UTF8}else{@($Audit.Rows)|Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8};return $Path
}

function Export-RekordboxPlaylistM3U8 {
    param([Parameter(Mandatory)]$Library,[Parameter(Mandatory)][string]$PlaylistPath,[Parameter(Mandatory)][string]$Path)
    $playlist=@($Library.Playlists|Where-Object{$_.Path -eq $PlaylistPath}|Select-Object -First 1);if(-not$playlist.Count){throw "Playlist não encontrada: $PlaylistPath"}
    $lines=New-Object Collections.Generic.List[string];$lines.Add('#EXTM3U');foreach($id in @($playlist[0].TrackIDs)){if($Library.TracksById.ContainsKey([string]$id)){$track=$Library.TracksById[[string]$id];$lines.Add("#EXTINF:-1,$($track.Artist) - $($track.Name)");$lines.Add([string]$track.Location)}};[IO.File]::WriteAllLines($Path,$lines.ToArray(),(New-Object Text.UTF8Encoding($false)));return $Path
}

function Export-TracksM3U8 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tracks,[Parameter(Mandatory)][string]$Path)
    $lines=New-Object Collections.Generic.List[string];$lines.Add('#EXTM3U')
    foreach($track in $Tracks){
        $title=if($track.PSObject.Properties['Title'] -and $track.Title){[string]$track.Title}else{[IO.Path]::GetFileNameWithoutExtension([string]$track.FullName)}
        $artist=if($track.PSObject.Properties['Artist']){[string]$track.Artist}else{''}
        $display=if($artist){"$artist - $title"}else{$title}
        $lines.Add("#EXTINF:-1,$display");$lines.Add([string]$track.FullName)
    }
    [IO.File]::WriteAllLines($Path,$lines.ToArray(),(New-Object Text.UTF8Encoding($false)));return $Path
}

Export-ModuleMember -Function Import-RekordboxXmlMetadata,Export-RekordboxXml,Get-RekordboxXmlLibrary,Get-RekordboxAudit,Get-RekordboxUsbAudit,Export-RekordboxAudit,Export-RekordboxPlaylistM3U8,Export-TracksM3U8
