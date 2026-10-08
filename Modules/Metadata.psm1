Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

$script:TagLibAvailable = $false
$script:ShellBpmColumn = -2
$tagLibPath = Join-Path (Get-AppRoot) 'lib\TagLibSharp.dll'
if (Test-Path -LiteralPath $tagLibPath) {
    try { Add-Type -Path $tagLibPath -ErrorAction Stop; $script:TagLibAvailable = $true } catch { }
}

function Get-ShellAudioProperties {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $result = @{}
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace($File.DirectoryName)
        $item = $folder.ParseName($File.Name)
        # BPM não usa índice fixo: a posição muda conforme a versão e o idioma do Windows.
        $map = @{ Title = 21; Artist = 13; Album = 14; Genre = 16; Year = 15; Bitrate = 26 }
        foreach ($key in $map.Keys) {
            $value = $folder.GetDetailsOf($item, $map[$key])
            if ($value) { $result[$key] = ($value -replace '[^\x20-\x7E\u00C0-\u017F]', '').Trim() }
        }
        if (-not $result.ContainsKey('Bpm')) {
            if ($script:ShellBpmColumn -eq -2) {
                $script:ShellBpmColumn = -1
                for ($index = 0; $index -le 350; $index++) {
                    $column = [string]$folder.GetDetailsOf($null, $index)
                    if ($column -match '(?i)^\s*(BPM|beats per minute|batidas por minuto)\s*$') { $script:ShellBpmColumn = $index; break }
                }
            }
            if ($script:ShellBpmColumn -ge 0) {
                $value = [string]$folder.GetDetailsOf($item, $script:ShellBpmColumn)
                if ($value) { $result['Bpm'] = $value.Trim() }
            }
        }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    } catch { }
    return $result
}

function Get-WaveTechnicalInfo {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $result = @{ BitDepth = 0; SampleRate = 0; Valid = $false }
    try {
        $stream = [IO.File]::OpenRead($File.FullName)
        $reader = [IO.BinaryReader]::new($stream)
        $riff = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)); [void]$reader.ReadInt32(); $wave = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($riff -ne 'RIFF' -or $wave -ne 'WAVE') { throw 'Cabeçalho WAV inválido' }
        while ($stream.Position -le $stream.Length - 8) {
            $chunk = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)); $length = $reader.ReadInt32()
            if ($chunk -eq 'fmt ') {
                [void]$reader.ReadInt16(); [void]$reader.ReadInt16(); $result.SampleRate = $reader.ReadInt32(); [void]$reader.ReadInt32(); [void]$reader.ReadInt16(); $result.BitDepth = $reader.ReadInt16(); $result.Valid = $true; break
            }
            $stream.Position += $length + ($length % 2)
        }
        $reader.Dispose(); $stream.Dispose()
    } catch { $result.Error = $_.Exception.Message }
    return $result
}

function Get-Mp3BitrateProfile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $empty=[pscustomobject]@{Minimum=0;Maximum=0;Average=0;Mode='';Map='';Frames=0}
    if($File.Extension.ToLowerInvariant() -ne '.mp3' -or $File.Length -lt 4){return $empty}
    $values=New-Object Collections.Generic.List[int]
    $stream=$null
    try {
        $stream=[IO.File]::OpenRead($File.FullName)
        $start=0L
        if($File.Length -ge 10){
            $id3=New-Object byte[] 10;[void]$stream.Read($id3,0,10)
            if([Text.Encoding]::ASCII.GetString($id3,0,3) -eq 'ID3'){
                $tagSize=(($id3[6] -band 0x7F) -shl 21) -bor (($id3[7] -band 0x7F) -shl 14) -bor (($id3[8] -band 0x7F) -shl 7) -bor ($id3[9] -band 0x7F)
                $start=10L+$tagSize
                if(($id3[5] -band 0x10) -ne 0){$start+=10}
            }
        }
        $stream.Position=[Math]::Min($start,$File.Length-4)
        $header=New-Object byte[] 4;$sampleCount=16
        for($point=0;$point -lt $sampleCount;$point++){
            $target=[int64]($start+(($File.Length-4-$start)*$point/[Math]::Max(1,$sampleCount-1)));$found=$false
            for($probe=0;$probe -lt 4096 -and $target -le $File.Length-4;$probe++){
                $position=$target;$stream.Position=$position
                if($stream.Read($header,0,4) -ne 4){break}
                $b0=[int]$header[0];$b1=[int]$header[1];$b2=[int]$header[2]
                if($b0 -eq 0xFF -and (($b1 -band 0xE0) -eq 0xE0)){
                    $version=($b1 -shr 3) -band 3;$layer=($b1 -shr 1) -band 3;$bitrateIndex=($b2 -shr 4) -band 15;$sampleIndex=($b2 -shr 2) -band 3;$padding=($b2 -shr 1) -band 1
                    if($version -ne 1 -and $layer -eq 1 -and $bitrateIndex -gt 0 -and $bitrateIndex -lt 15 -and $sampleIndex -lt 3){
                        $bitrateTable=[int[]](32,40,48,56,64,80,96,112,128,160,192,224,256,320)
                        if($version -eq 3){$bitrate=$bitrateTable[$bitrateIndex-1];$sampleTable=[int[]](44100,48000,32000);$sampleRate=$sampleTable[$sampleIndex];$frameLength=[int][Math]::Floor((144000*$bitrate/$sampleRate)+$padding)}
                        else{$bitrateTable=[int[]](8,16,24,32,40,48,56,64,80,96,112,128,144,160);$bitrate=$bitrateTable[$bitrateIndex-1];$sampleTable=[int[]](22050,24000,16000);if($version -eq 0){$sampleTable=[int[]](11025,12000,8000)};$sampleRate=$sampleTable[$sampleIndex];$frameLength=[int][Math]::Floor((72000*$bitrate/$sampleRate)+$padding)}
                        if($frameLength -ge 4 -and $position+$frameLength -le $File.Length){
                            $nextPosition=$position+$frameLength;$validNext=($nextPosition -gt $File.Length-4)
                            if(-not$validNext){$stream.Position=$nextPosition;[void]$stream.Read($header,0,4);$validNext=([int]$header[0] -eq 0xFF -and (([int]$header[1] -band 0xE0) -eq 0xE0))}
                            if($validNext){$values.Add($bitrate);$found=$true;break}
                        }
                    }
                }
                $target=$position+1
            }
        }
    }catch{}finally{if($stream){$stream.Dispose()}}
    if($values.Count -eq 0){return $empty}
    $min=($values|Measure-Object -Minimum).Minimum;$max=($values|Measure-Object -Maximum).Maximum;$avg=[int][Math]::Round(($values|Measure-Object -Average).Average)
    $chars=[char[]]' .:-=+*#@';$map='';$pointCount=32
    for($i=0;$i -lt $pointCount;$i++){$from=[int][Math]::Floor($i*$values.Count/$pointCount);$to=[int][Math]::Max($from+1,[Math]::Floor(($i+1)*$values.Count/$pointCount));if($to -gt $values.Count){$to=$values.Count};$segment=@($values[$from..($to-1)]);$segmentAvg=[double](($segment|Measure-Object -Average).Average);$level=if($max -eq $min){4}else{[int][Math]::Round((($segmentAvg-$min)/($max-$min))*8)};$map+=[string]$chars[[Math]::Min(8,[Math]::Max(0,$level))]}
    [pscustomobject]@{Minimum=[int]$min;Maximum=[int]$max;Average=$avg;Mode=$(if($min -eq $max){'CBR'}else{'VBR'});Map=$map;Frames=$values.Count}
}

function Get-AudioMetadata {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)]$Settings
    )
    $title = $File.BaseName; $hasTitleMetadata=$false; $artist = ''; $album = ''; $genre = ''; $year = ''; $bpm = 0; $key = ''
    $bitrate = 0; $sampleRate = 0; $bitDepth = 0; $duration = [TimeSpan]::Zero; $metadataError = ''; $isCorrupt = ($File.Length -eq 0)
    if ($script:TagLibAvailable) {
        try {
            $tag = [TagLib.File]::Create($File.FullName)
            if ($tag.Tag.Title) { $title = $tag.Tag.Title; $hasTitleMetadata=$true }
            if ($tag.Tag.FirstPerformer) { $artist = $tag.Tag.FirstPerformer }
            if ($tag.Tag.Album) { $album = $tag.Tag.Album }
            if ($tag.Tag.FirstGenre) { $genre = $tag.Tag.FirstGenre }
            if ($tag.Tag.Year) { $year = [string]$tag.Tag.Year }
            if ($tag.Tag.BeatsPerMinute) { $bpm = [int]$tag.Tag.BeatsPerMinute }
            if ($bpm -le 0) {
                foreach ($text in @([string]$tag.Tag.Comment, [string]$tag.Tag.Grouping, [string]$tag.Tag.Description)) {
                    if ($text -match '(?i)(?<!\d)(\d{2,3}(?:[.,]\d+)?)\s*BPM\b') { $bpm = [int][Math]::Round([double]($Matches[1] -replace ',','.')); break }
                }
            }
            if ($tag.Tag.InitialKey) { $key = $tag.Tag.InitialKey }
            $bitrate = [int]$tag.Properties.AudioBitrate
            $sampleRate = [int]$tag.Properties.AudioSampleRate
            if ($tag.Properties.PSObject.Properties['BitsPerSample']) { $bitDepth = [int]$tag.Properties.BitsPerSample }
            $duration = $tag.Properties.Duration
            $tag.Dispose()
        } catch { $metadataError = $_.Exception.Message; $isCorrupt = $true }
    } else {
        $shell = Get-ShellAudioProperties -File $File
        if ($shell.ContainsKey('Title')) { $title = $shell['Title']; $hasTitleMetadata=$true }
        if ($shell.ContainsKey('Artist')) { $artist = $shell['Artist'] }
        if ($shell.ContainsKey('Album')) { $album = $shell['Album'] }
        if ($shell.ContainsKey('Genre')) { $genre = $shell['Genre'] }
        if ($shell.ContainsKey('Year')) { $year = $shell['Year'] }
        if ($shell.ContainsKey('Bpm') -and $shell['Bpm'] -match '\d+') { $bpm = [int]$Matches[0] }
        if ($shell.ContainsKey('Bitrate') -and $shell['Bitrate'] -match '\d+') { $bitrate = [int]$Matches[0] }
    }
    if ($bpm -le 0) {
        $shellBpm = Get-ShellAudioProperties -File $File
        if ($shellBpm.ContainsKey('Bpm') -and [string]$shellBpm['Bpm'] -match '(\d{2,3}(?:[.,]\d+)?)') { $bpm = [int][Math]::Round([double]($Matches[1] -replace ',','.')) }
    }
    if ($bpm -le 0 -and $File.BaseName -match '(?i)(?<!\d)(\d{2,3}(?:[.,]\d+)?)\s*BPM\b') { $bpm = [int][Math]::Round([double]($Matches[1] -replace ',','.')) }
    if ($File.Extension -in @('.wav','.aiff','.aif') -and $File.Length -gt 0) {
        $waveInfo = Get-WaveTechnicalInfo -File $File
        if ($File.Extension -eq '.wav') {
            if ($waveInfo.SampleRate) { $sampleRate = $waveInfo.SampleRate }
            if ($waveInfo.BitDepth) { $bitDepth = $waveInfo.BitDepth }
            if (-not $waveInfo.Valid) { $isCorrupt = $true; $metadataError = [string]$waveInfo.Error }
        }
    }
    if ($genre) {
        $alias = $Settings.GenreAliases.PSObject.Properties | Where-Object { $_.Name -eq $genre.Trim().ToUpperInvariant() } | Select-Object -First 1
        if ($alias) { $genre = [string]$alias.Value }
    }
    $bitrateProfile=Get-Mp3BitrateProfile -File $File
    [pscustomobject]@{
        Title = $title; Artist = $artist; Album = $album; Genre = $genre; Year = $year
        Bpm = $bpm; Key = $key; Bitrate = $bitrate; SampleRate = $sampleRate; BitDepth = $bitDepth; Codec = $File.Extension.TrimStart('.').ToUpperInvariant(); Duration = $duration
        BitrateMin = $bitrateProfile.Minimum; BitrateMax = $bitrateProfile.Maximum; BitrateAverage = $bitrateProfile.Average; BitrateMode = $bitrateProfile.Mode; BitrateMap = $bitrateProfile.Map; BitrateFrames = $bitrateProfile.Frames
        IsCorrupt = $isCorrupt; MetadataError = $metadataError; HasTitleMetadata=$hasTitleMetadata
        MetadataProvider = $(if ($script:TagLibAvailable) { 'TagLib#' } else { 'Windows Shell' })
    }
}

Export-ModuleMember -Function Get-AudioMetadata, Get-WaveTechnicalInfo, Get-Mp3BitrateProfile
