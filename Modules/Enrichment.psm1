Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'History.psm1')

$script:LastMusicBrainzRequest = [datetime]::MinValue

function Get-OnlineSearchParts {
    param([Parameter(Mandatory)]$Track)
    $artist=[string]$Track.Artist;$title=[string]$Track.Title
    $base=[IO.Path]::GetFileNameWithoutExtension([string]$Track.Name)
    if((-not $artist -or ($Track.PSObject.Properties['MissingTitle'] -and $Track.MissingTitle)) -and $base -match '^\s*(.+?)\s+-\s+(.+?)\s*$'){
        if(-not $artist){$artist=$Matches[1].Trim()};$title=$Matches[2].Trim()
    }
    if(-not $title){$title=$base}
    $title=$title -replace '(?i)\s*[\[(](official\s*(audio|video)|320\s*kbps|free download)[\])]\s*',' '
    [pscustomobject]@{Artist=$artist.Trim();Title=$title.Trim()}
}

function Invoke-MusicBrainzJson {
    param([Parameter(Mandatory)][string]$Uri)
    $elapsed=(Get-Date)-$script:LastMusicBrainzRequest
    if($elapsed.TotalMilliseconds -lt 1100){Start-Sleep -Milliseconds ([int](1100-$elapsed.TotalMilliseconds))}
    $headers=@{'User-Agent'='CRIVO-DJ/2.0 (local desktop metadata organizer)';'Accept'='application/json'}
    for($attempt=1;$attempt -le 3;$attempt++){
        try { $result=Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -TimeoutSec 25; $script:LastMusicBrainzRequest=Get-Date; return $result }
        catch { $script:LastMusicBrainzRequest=Get-Date;if($attempt -ge 3){throw};Start-Sleep -Seconds (2*$attempt) }
    }
}

function Get-CacheFile {
    param([Parameter(Mandatory)][string]$Key)
    $sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[Text.Encoding]::UTF8.GetBytes($Key);$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    Join-Path (Get-AppDataRoot) "Cache\OnlineMetadata\$hash.json"
}

function Get-CachedSuggestion {
    param([string]$Path,[int]$CacheDays)
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    if(((Get-Date)-(Get-Item -LiteralPath $Path).LastWriteTime).TotalDays -gt $CacheDays){return $null}
    Read-JsonFile -Path $Path
}

function ConvertFrom-MusicBrainzRecording {
    param([Parameter(Mandatory)]$Recording,[int]$Score=0,[string]$Source='MusicBrainz')
    $artist='';if($Recording.PSObject.Properties['artist-credit']){$artist=@($Recording.'artist-credit'|ForEach-Object{$_.name}) -join ', '}
    $album='';$year='';if($Recording.PSObject.Properties['releases'] -and @($Recording.releases).Count){$dated=@($Recording.releases|Where-Object{$_.PSObject.Properties['date'] -and $_.date}|Sort-Object date);$release=if($dated.Count){$dated[0]}else{@($Recording.releases)[0]};$album=[string]$release.title;if($release.PSObject.Properties['date'] -and $release.date -match '^\d{4}'){$year=$Matches[0]}}
    $genre='';if($Recording.PSObject.Properties['genres'] -and @($Recording.genres).Count){$genre=[string](@($Recording.genres|Sort-Object count -Descending)[0].name)}elseif($Recording.PSObject.Properties['tags'] -and @($Recording.tags).Count){$genre=[string](@($Recording.tags|Sort-Object count -Descending)[0].name)}
    $isrc='';if($Recording.PSObject.Properties['isrcs'] -and @($Recording.isrcs).Count){$isrc=[string]@($Recording.isrcs)[0]}
    [pscustomobject]@{Found=$true;Title=[string]$Recording.title;Artist=$artist;Album=$album;Genre=$genre;Year=$year;ISRC=$isrc;Confidence=[int][Math]::Min(100,[Math]::Max(0,$Score));Source=$Source;MusicBrainzId=[string]$Recording.id;Error=''}
}

function Find-WithAcoustId {
    param([Parameter(Mandatory)]$Track,[Parameter(Mandatory)]$Settings)
    $key=[string]$Settings.InternetMetadata.AcoustIdClientKey;if([string]::IsNullOrWhiteSpace($key)){return $null}
    $fpcalc=Join-Path (Get-AppRoot) 'lib\Chromaprint\fpcalc.exe';if(-not(Test-Path -LiteralPath $fpcalc)){return $null}
    try{
        $raw=& $fpcalc -json ([string]$Track.FullName) 2>$null;if(-not$raw){return $null};$fingerprint=$raw|ConvertFrom-Json
        $body=@{client=$key;format='json';duration=[int][Math]::Round([double]$fingerprint.duration);fingerprint=[string]$fingerprint.fingerprint;meta='recordings releasegroups releases isrcs'}
        $response=Invoke-RestMethod -Uri 'https://api.acoustid.org/v2/lookup' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 35
        $match=@($response.results|Where-Object{$_.recordings}|Sort-Object score -Descending|Select-Object -First 1)
        if(-not$match.Count){return $null};$recording=@($match[0].recordings)[0];return ConvertFrom-MusicBrainzRecording -Recording $recording -Score ([int]([double]$match[0].score*100)) -Source 'AcoustID + MusicBrainz'
    }catch{Write-AppLog -Message "AcoustID falhou para $($Track.FullName): $($_.Exception.Message)" -Level WARN;return $null}
}

function Find-WithMusicBrainzText {
    param([Parameter(Mandatory)]$Track)
    $parts=Get-OnlineSearchParts -Track $Track;if(-not$parts.Title){return $null}
    $query=if($parts.Artist){"recording:`"$($parts.Title)`" AND artist:`"$($parts.Artist)`""}else{"recording:`"$($parts.Title)`""}
    $uri='https://musicbrainz.org/ws/2/recording/?query='+[Uri]::EscapeDataString($query)+'&fmt=json&limit=5'
    try{
        $search=Invoke-MusicBrainzJson -Uri $uri;$recording=@($search.recordings|Select-Object -First 1);if(-not$recording.Count){return $null}
        $score=[int]$recording[0].score;$id=[string]$recording[0].id
        $reviewScore=[Math]::Min(89,$score)
        try{$detail=Invoke-MusicBrainzJson -Uri ("https://musicbrainz.org/ws/2/recording/$id?inc=artists+releases+release-groups+genres+tags+isrcs&fmt=json");return ConvertFrom-MusicBrainzRecording -Recording $detail -Score $reviewScore -Source 'MusicBrainz (busca textual)'}catch{return ConvertFrom-MusicBrainzRecording -Recording $recording[0] -Score $reviewScore -Source 'MusicBrainz (busca textual)'}
    }catch{Write-AppLog -Message "MusicBrainz falhou para $($Track.FullName): $($_.Exception.Message)" -Level WARN;return [pscustomobject]@{Found=$false;Title='';Artist='';Album='';Genre='';Year='';ISRC='';Confidence=0;Source='MusicBrainz';MusicBrainzId='';Error=$_.Exception.Message}}
}

function Get-OnlineMetadataSuggestion {
    param([Parameter(Mandatory)]$Track,[Parameter(Mandatory)]$Settings,[switch]$Force)
    $cacheDays=[int]$Settings.InternetMetadata.CacheDays;$cacheKey="$($Track.FullName)|$($Track.Size)|$($Track.Modified)|$($Settings.InternetMetadata.AcoustIdClientKey)";$cache=Get-CacheFile -Key $cacheKey
    if(-not$Force){$saved=Get-CachedSuggestion -Path $cache -CacheDays $cacheDays;if($saved){return $saved}}
    $suggestion=Find-WithAcoustId -Track $Track -Settings $Settings;if(-not$suggestion){$suggestion=Find-WithMusicBrainzText -Track $Track}
    if(-not$suggestion){$suggestion=[pscustomobject]@{Found=$false;Title='';Artist='';Album='';Genre='';Year='';ISRC='';Confidence=0;Source='Nenhuma correspondência';MusicBrainzId='';Error='Nenhuma correspondência encontrada'}}
    if(-not$Suggestion.PSObject.Properties['Error'] -or -not$Suggestion.Error){Write-JsonFile -Path $cache -Value $suggestion};return $suggestion
}

function Set-TrackSuggestion {
    param([Parameter(Mandatory)]$Track,[Parameter(Mandatory)]$Suggestion,[switch]$FillOnlyEmpty)
    if(-not$Suggestion.Found){return $false}
    foreach($field in @('Title','Artist','Album','Genre','Year')){
        $current=[string]$Track.$field;$value=[string]$Suggestion.$field
        if($value -and (-not$FillOnlyEmpty -or -not$current -or ($field -eq 'Title' -and $Track.MissingTitle) -or ($field -eq 'Genre' -and $Track.MissingGenre))){$Track.$field=$value}
    }
    if($Suggestion.ISRC){$Track|Add-Member -NotePropertyName ISRC -NotePropertyValue ([string]$Suggestion.ISRC) -Force}
    if($Track.Title){$Track.MissingTitle=$false};if($Track.Genre){$Track.MissingGenre=$false}
    $Track|Add-Member -NotePropertyName OnlineConfidence -NotePropertyValue ([int]$Suggestion.Confidence) -Force
    $Track|Add-Member -NotePropertyName OnlineSource -NotePropertyValue ([string]$Suggestion.Source) -Force
    return $true
}

function Write-ApprovedMetadata {
    param([Parameter(Mandatory)][object[]]$Tracks,[string]$Template='Enriquecimento online')
    $dll=Join-Path (Get-AppRoot) 'lib\TagLibSharp.dll';if(-not('TagLib.File' -as [type])){Add-Type -Path $dll}
    $items=New-Object Collections.Generic.List[object];$id=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    foreach($track in $Tracks){
        $result='Updated';$error='';$before=$null;$file=$null
        try{
            $file=[TagLib.File]::Create([string]$track.FullName);$before=[pscustomobject]@{Title=$file.Tag.Title;Performers=@($file.Tag.Performers);Album=$file.Tag.Album;Genres=@($file.Tag.Genres);Year=[uint32]$file.Tag.Year;Bpm=[uint32]$file.Tag.BeatsPerMinute;Key=$file.Tag.InitialKey}
            if($track.Title){$file.Tag.Title=[string]$track.Title};if($track.Artist){$file.Tag.Performers=@([string]$track.Artist)};if($track.Album){$file.Tag.Album=[string]$track.Album};if($track.Genre){$file.Tag.Genres=@([string]$track.Genre)};if($track.Year -match '^\d{4}$'){$file.Tag.Year=[uint32]$track.Year};if($track.Bpm){$file.Tag.BeatsPerMinute=[uint32]$track.Bpm};if($track.Key){$file.Tag.InitialKey=[string]$track.Key};$file.Save()
        }catch{$result='Error';$error=$_.Exception.Message}finally{if($file){try{$file.Dispose()}catch{}}}
        $items.Add([pscustomobject]@{Index=$items.Count+1;Source=$track.FullName;Destination=$track.FullName;Before=$before;Result=$result;Error=$error})
    }
    $operation=[pscustomobject]@{Id="metadata-$id";Date=(Get-Date).ToString('o');Action='Metadata';Template=$Template;Source='';Destination='';Counts=[pscustomobject]@{Total=$items.Count;Updated=@($items|Where-Object Result -eq 'Updated').Count;Errors=@($items|Where-Object Result -eq 'Error').Count};Items=$items;UndoneAt=$null};$path=Save-OperationHistory -Operation $operation
    [pscustomobject]@{Operation=$operation;HistoryPath=$path;Updated=$operation.Counts.Updated;Errors=$operation.Counts.Errors}
}

Export-ModuleMember -Function Get-OnlineSearchParts,Get-OnlineMetadataSuggestion,Set-TrackSuggestion,Write-ApprovedMetadata
