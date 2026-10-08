#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $app 'Modules\Common.psm1') -Force
Import-Module (Join-Path $app 'Modules\Metadata.psm1') -Force
Import-Module (Join-Path $app 'Modules\Rekordbox.psm1') -Force
$settings=Read-JsonFile -Path (Join-Path $app 'Config\settings.json')
$root=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Audit-Stress-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null

function New-TestAudioFile {
    param([string]$RelativePath,[byte[]]$Bytes)
    $path=Join-Path $root $RelativePath;$directory=Split-Path -Parent $path
    [IO.Directory]::CreateDirectory($directory)|Out-Null;[IO.File]::WriteAllBytes($path,$Bytes);return $path
}

function New-LibraryTrack {
    param([string]$Id,[string]$Name,[string]$Artist,[string]$Path,[int]$Bitrate=320,[string]$Genre='House')
    return [pscustomobject]@{TrackID=$Id;Name=$Name;Artist=$Artist;Album='Album';Genre=$Genre;Year='2026';Bpm=128;Key='8A';Bitrate=$Bitrate;SampleRate=44100;Location=$Path;PlaylistCount=1;PlaylistNames=@('Coleção / Teste fechado');Analysis='DAT, EXT, 2EX'}
}

try{
    $healthy=New-TestAudioFile 'library\healthy.mp3' ([byte[]](1,2,3,4,5))
    $quality=New-TestAudioFile 'library\quality.mp3' ([byte[]](6,7,8,9,10,11))
    $metadataFile=New-TestAudioFile 'library\metadata.mp3' ([byte[]](12,13,14,15,16,17,18))
    $exactA=New-TestAudioFile 'downloads\provider-a\exact-a.mp3' ([byte[]](21,22,23,24,25,26,27,28))
    $exactB=New-TestAudioFile 'downloads\provider-b\exact-b.mp3' ([byte[]](21,22,23,24,25,26,27,28))
    $samePath=New-TestAudioFile 'library\same-path.mp3' ([byte[]](31,32,33,34,35,36,37,38,39))
    $possibleA=New-TestAudioFile 'incoming\one\possible-a.mp3' ([byte[]](41,42,43,44,45,46,47,48,49,50))
    $possibleB=New-TestAudioFile 'incoming\two\possible-b.mp3' ([byte[]](51,52,53,54,55,56,57,58,59,60,61))
    $deep=New-TestAudioFile 'a\b\c\d\e\f\g\h\deep.mp3' ([byte[]](71,72,73,74,75,76,77,78,79,80,81,82))

    $unavailable='Z:\CRIVO-Audit-Stress\missing.mp3';if([IO.DriveInfo]::new('Z:\').IsReady){$unavailable='Q:\CRIVO-Audit-Stress\missing.mp3'};if([IO.DriveInfo]::new(($unavailable.Substring(0,3))).IsReady){Write-Output 'SKIP: não há unidade indisponível livre para o cenário';return}
    $rows=New-Object Collections.Generic.List[object]
    $rows.Add((New-LibraryTrack '1' 'Healthy' 'Artist' $healthy))
    $rows.Add((New-LibraryTrack '2' 'Missing' 'Artist' (Join-Path $root 'does-not-exist.mp3')))
    $rows.Add((New-LibraryTrack '3' 'Unavailable' 'Artist' $unavailable))
    $rows.Add((New-LibraryTrack '4' 'Low bitrate' 'Artist' $quality 128))
    $rows.Add((New-LibraryTrack '5' 'Missing data' 'Artist' $metadataFile 320 ''))
    $rows.Add((New-LibraryTrack '6' 'Exact A' 'Exact Artist' $exactA))
    $rows.Add((New-LibraryTrack '7' 'Exact B' 'Other Metadata' $exactB))
    $rows.Add((New-LibraryTrack '8' 'Same path A' 'Path Artist' $samePath))
    $rows.Add((New-LibraryTrack '9' 'Same path B' 'Path Artist' $samePath))
    $rows.Add((New-LibraryTrack '10' 'Possible Match' 'Same Artist' $possibleA))
    $rows.Add((New-LibraryTrack '11' 'possible-match' 'same artist' $possibleB))
    $rows.Add((New-LibraryTrack '12' 'Deep Track' 'Folder Artist' $deep))

    $library=[pscustomobject]@{Tracks=$rows.ToArray();Playlists=@()};$audit=Get-RekordboxAudit -Library $library -Settings $settings
    if($audit.Total -ne 12 -or $audit.MissingFiles -ne 1 -or $audit.UnavailableFiles -ne 1 -or $audit.QualityIssues -ne 1 -or $audit.MetadataIssues -ne 1){throw "Contadores inesperados: total=$($audit.Total), missing=$($audit.MissingFiles), unavailable=$($audit.UnavailableFiles), quality=$($audit.QualityIssues), metadata=$($audit.MetadataIssues)."}
    if($audit.DuplicatePaths -ne 4){throw "Esperava 4 tracks em duplicidade exata/caminho, recebeu $($audit.DuplicatePaths)."}
    if($audit.PossibleDuplicates -ne 2){throw "Esperava 2 possíveis duplicatas, recebeu $($audit.PossibleDuplicates)."}
    if($audit.LocationIssues -ne 1){throw "Esperava somente a origem profundamente aninhada, recebeu $($audit.LocationIssues)."}
    $playlistRow=@($audit.Rows|Where-Object TrackID -eq '1')[0];if([string]$playlistRow.PlaylistDisplay -ne 'Coleção / Teste fechado'){throw 'A auditoria não preservou o nome e o caminho da playlist da track.'}
    foreach($id in @('6','7')){$match=@($audit.Rows|Where-Object TrackID -eq $id)[0];$value=[string]($match.DuplicateType);if($value -notmatch 'Conteúdo idêntico'){throw "Track $id não foi classificada por conteúdo idêntico."}}
    foreach($id in @('8','9')){$match=@($audit.Rows|Where-Object TrackID -eq $id)[0];$value=[string]($match.DuplicateType);if($value -notmatch 'Mesmo caminho'){throw "Track $id não foi classificada por mesmo caminho."}}
    foreach($id in @('10','11')){$match=@($audit.Rows|Where-Object TrackID -eq $id)[0];$value=[string]($match.IssueCategories);if($value -notmatch 'PossibleDuplicate'){throw "Track $id não foi classificada como possível duplicata."}}
    $unavailableRow=@($audit.Rows|Where-Object TrackID -eq '3')[0];if($unavailableRow.IssueCategories -notmatch '(^|;)Unavailable(;|$)' -or $unavailableRow.IssueCategories -match '(^|;)(Missing|Integrity)(;|$)' -or $unavailableRow.IssueCount -ne 0){throw "Unidade indisponível foi tratada incorretamente: tipo=$($unavailableRow.IssueType), count=$($unavailableRow.IssueCount), categorias=$($unavailableRow.IssueCategories)."}

    $usb=Join-Path $root 'usb';[IO.Directory]::CreateDirectory((Join-Path $usb 'PIONEER\rekordbox'))|Out-Null;[IO.File]::WriteAllBytes((Join-Path $usb 'PIONEER\rekordbox\export.pdb'),[byte[]](1,2,3))
    [IO.Directory]::CreateDirectory((Join-Path $usb 'PIONEER\USBANLZ\0001'))|Out-Null;[IO.File]::WriteAllBytes((Join-Path $usb 'PIONEER\USBANLZ\0001\ANLZ0000.DAT'),[byte[]](4,5,6))
    foreach($folder in @('Music\A','Music\B')){[IO.Directory]::CreateDirectory((Join-Path $usb $folder))|Out-Null;[IO.File]::WriteAllBytes((Join-Path $usb "$folder\usb-copy.mp3"),[byte[]](91,92,93,94,95,96,97,98))}
    $usbAudit=Get-RekordboxUsbAudit -Root $usb -Settings $settings
    if($usbAudit.Total -ne 2 -or $usbAudit.DuplicatePaths -ne 2){throw "Duplicidade do pendrive falhou: total=$($usbAudit.Total), duplicadas=$($usbAudit.DuplicatePaths)."}
    if(@($usbAudit.Rows|Where-Object{$_.Codec -in @('DB','ANLZ') -and $_.DuplicateType}).Count){throw 'Arquivos internos do Rekordbox entraram indevidamente na comparação de áudio.'}
    Write-Output 'AUDITORIA STRESS OK: ausentes, unidades indisponíveis, qualidade, metadados, duplicatas exatas, possíveis, origens e pendrive.'
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
