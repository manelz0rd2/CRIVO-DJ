Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Metadata.psm1')

function Get-AudioFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)]$Settings,
        [switch]$IncludeHash,
        [bool]$OnlyAudio=$true,
        [scriptblock]$OnProgress
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "A pasta de origem não existe: $Source" }
    $extensions = @($Settings.AudioExtensions | ForEach-Object { $_.ToLowerInvariant() })
    $excludedExtensions = @($Settings.ExcludedExtensions | ForEach-Object { $_.ToLowerInvariant() })
    $excluded = @($Settings.ExcludedFolders)
    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $files = @(Get-ChildItem -LiteralPath $Source -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $file=$_;$relative=$file.Name
        if ($file.FullName.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $relative=$file.FullName.Substring($sourceRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        }
        $relativeParts=@($relative -split '[\\/]+' | Where-Object {$_})
        ((-not$OnlyAudio) -or $extensions -contains $file.Extension.ToLowerInvariant()) -and $excludedExtensions -notcontains $file.Extension.ToLowerInvariant() -and
        -not (@($relativeParts | Where-Object { $excluded -contains $_ }).Count)
    })
    $result = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $files.Count; $i++) {
        $file = $files[$i]
        if ($OnProgress) { & $OnProgress ($i + 1) $files.Count $file.Name }
        $meta = Get-AudioMetadata -File $file -Settings $Settings
        $genreWasMissing = [string]::IsNullOrWhiteSpace([string]$meta.Genre)
        if ($genreWasMissing -and $Settings.PSObject.Properties['GenreFallbackPriority']) {
            foreach ($fallback in @($Settings.GenreFallbackPriority)) {
                if ($fallback -eq 'SourceFolder') {
                    $candidate = Split-Path $file.DirectoryName -Leaf
                    if ($candidate -and $candidate -notin @('Downloads','Music','Músicas','Pesquisa')) {
                        $candidateNormalized = $candidate.Trim().ToUpperInvariant()
                        $alias = $Settings.GenreAliases.PSObject.Properties | Where-Object { $_.Name.Trim().ToUpperInvariant() -eq $candidateNormalized } | Select-Object -First 1
                        $canonical = $Settings.GenreAliases.PSObject.Properties | Where-Object { ([string]$_.Value).Trim().ToUpperInvariant() -eq $candidateNormalized } | Select-Object -First 1
                        # Um nome de pasta arbitrário (por exemplo, "Novo Teste") não é metadata.
                        # O fallback só é válido quando a pasta corresponde a um gênero conhecido.
                        if ($alias) { $meta.Genre = [string]$alias.Value; break }
                        if ($canonical) { $meta.Genre = [string]$canonical.Value; break }
                    }
                } elseif ($fallback -eq '_PENDENTE') { $meta.Genre = '_PENDENTE'; break }
            }
        }
        $hash = ''
        if ($IncludeHash) { try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash } catch { } }
        $qualityIssues = [System.Collections.Generic.List[string]]::new()
        if ($meta.IsCorrupt) { $qualityIssues.Add('Corrompido/inacessível') }
        if ($file.Extension -eq '.mp3' -and $meta.Bitrate -gt 0 -and $meta.Bitrate -lt [int]$Settings.Quality.MinimumMp3Bitrate) { $qualityIssues.Add("Bitrate baixo: $($meta.Bitrate) kbps") }
        if ($meta.SampleRate -gt 0 -and $meta.SampleRate -lt [int]$Settings.Quality.MinimumSampleRate) { $qualityIssues.Add("Sample rate baixo: $($meta.SampleRate) Hz") }
        $result.Add([pscustomobject]@{
            Selected = $true; Name = $file.Name; OutputName = $file.Name; FullName = $file.FullName; Directory = $file.DirectoryName
            Extension = $file.Extension; Size = $file.Length; Created = $file.CreationTime; Modified = $file.LastWriteTime
            Title = $meta.Title; Artist = $meta.Artist; Album = $meta.Album; Genre = $meta.Genre; Year = $meta.Year
            Bpm = $(if([int]$meta.Bpm -gt 0){[int]$meta.Bpm}else{''}); Key = $meta.Key; Bitrate = $meta.Bitrate; SampleRate = $meta.SampleRate; BitDepth = $meta.BitDepth; Codec = $meta.Codec
            Duration = $meta.Duration; ISRC = ''; MetadataError = $meta.MetadataError
            BitrateMin = $meta.BitrateMin; BitrateMax = $meta.BitrateMax; BitrateAverage = $meta.BitrateAverage; BitrateMode = $meta.BitrateMode; BitrateMap = $meta.BitrateMap; BitrateFrames = $meta.BitrateFrames
            MissingTitle = (-not $meta.HasTitleMetadata); MissingGenre = $genreWasMissing; IsCorrupt = $meta.IsCorrupt; QualityStatus = $(if($qualityIssues.Count){$qualityIssues -join '; '}else{'OK'})
            Hash = $hash; Status = 'Analisado'; Destination = ''; Rule = ''; Error = $meta.MetadataError
        })
    }
    return $result
}

function Get-LibraryHealth {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tracks)
    [pscustomobject]@{
        Total = $Tracks.Count
        MissingGenre = @($Tracks | Where-Object { $_.MissingGenre -or -not $_.Genre }).Count
        MissingTitle = @($Tracks | Where-Object { $_.MissingTitle -or -not $_.Title }).Count
        MissingArtist = @($Tracks | Where-Object { -not $_.Artist }).Count
        MissingAlbum = @($Tracks | Where-Object { -not $_.Album }).Count
        MissingYear = @($Tracks | Where-Object { -not $_.Year }).Count
        MissingBpm = @($Tracks | Where-Object { -not $_.Bpm }).Count
        MissingKey = @($Tracks | Where-Object { -not $_.Key }).Count
        LowBitrate = @($Tracks | Where-Object { $_.Bitrate -gt 0 -and $_.Bitrate -lt 256 }).Count
        Corrupt = @($Tracks | Where-Object IsCorrupt).Count
        QualityIssues = @($Tracks | Where-Object QualityStatus -ne 'OK').Count
    }
}

Export-ModuleMember -Function Get-AudioFiles, Get-LibraryHealth
