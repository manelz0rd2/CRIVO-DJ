param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Backup,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [switch]$HashBackup
)

$ErrorActionPreference = 'Stop'

function Get-Inventory {
    param([string]$Root)
    $prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $items=@{}
    foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop){
        $relative=$file.FullName.Substring($prefix.Length)
        $items[$relative.ToLowerInvariant()]=[pscustomobject]@{
            RelativePath=$relative
            Length=[int64]$file.Length
            LastWriteTimeUtc=$file.LastWriteTimeUtc
            FullName=$file.FullName
        }
    }
    return $items
}

if(-not(Test-Path -LiteralPath $Source -PathType Container)){throw "Origem não encontrada: $Source"}
if(-not(Test-Path -LiteralPath $Backup -PathType Container)){throw "Backup não encontrado: $Backup"}
[IO.Directory]::CreateDirectory($ReportDirectory)|Out-Null

$sourceFiles=Get-Inventory -Root $Source
$backupFiles=Get-Inventory -Root $Backup
$differences=New-Object Collections.Generic.List[object]

foreach($key in $sourceFiles.Keys){
    $sourceFile=$sourceFiles[$key]
    if(-not$backupFiles.ContainsKey($key)){
        $differences.Add([pscustomobject]@{Type='Ausente no backup';Path=$sourceFile.RelativePath;SourceLength=$sourceFile.Length;BackupLength=$null})
        continue
    }
    $backupFile=$backupFiles[$key]
    if($sourceFile.Length -ne $backupFile.Length){
        $differences.Add([pscustomobject]@{Type='Tamanho diferente';Path=$sourceFile.RelativePath;SourceLength=$sourceFile.Length;BackupLength=$backupFile.Length})
    }
}
foreach($key in $backupFiles.Keys){
    if(-not$sourceFiles.ContainsKey($key)){
        $backupFile=$backupFiles[$key]
        $differences.Add([pscustomobject]@{Type='Somente no backup';Path=$backupFile.RelativePath;SourceLength=$null;BackupLength=$backupFile.Length})
    }
}

$criticalNames=@('PIONEER\rekordbox\EXPORT.PDB','PIONEER\rekordbox\exportExt.pdb','PIONEER\rekordbox\exportLibrary.db','PIONEER\rekordbox\exportLibrary.db-shm','PIONEER\rekordbox\exportLibrary.db-wal')
$critical=foreach($relative in $criticalNames){
    $sourcePath=Join-Path $Source $relative
    $backupPath=Join-Path $Backup $relative
    $sourceHash=if(Test-Path -LiteralPath $sourcePath -PathType Leaf){(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash}else{$null}
    $backupHash=if(Test-Path -LiteralPath $backupPath -PathType Leaf){(Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash}else{$null}
    [pscustomobject]@{Path=$relative;SourceHash=$sourceHash;BackupHash=$backupHash;Match=($sourceHash -and $sourceHash -eq $backupHash)}
}

$summary=[ordered]@{
    GeneratedAt=(Get-Date).ToString('o')
    Source=[IO.Path]::GetFullPath($Source)
    Backup=[IO.Path]::GetFullPath($Backup)
    SourceFileCount=$sourceFiles.Count
    BackupFileCount=$backupFiles.Count
    SourceBytes=[int64](($sourceFiles.Values|Measure-Object Length -Sum).Sum)
    BackupBytes=[int64](($backupFiles.Values|Measure-Object Length -Sum).Sum)
    DifferenceCount=$differences.Count
    CriticalHashesMatch=(@($critical|Where-Object{-not$_.Match}).Count -eq 0)
    Valid=($differences.Count -eq 0 -and @($critical|Where-Object{-not$_.Match}).Count -eq 0)
    Differences=$differences.ToArray()
    CriticalFiles=$critical
}

$summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $ReportDirectory 'backup-validation.json') -Encoding UTF8
$differences|Export-Csv -LiteralPath (Join-Path $ReportDirectory 'backup-differences.csv') -NoTypeInformation -Encoding UTF8
$critical|Export-Csv -LiteralPath (Join-Path $ReportDirectory 'critical-database-hashes.csv') -NoTypeInformation -Encoding UTF8

if($HashBackup){
    $manifest=foreach($item in $backupFiles.Values|Sort-Object RelativePath){
        $hash=Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256
        [pscustomobject]@{SHA256=$hash.Hash;Length=$item.Length;Path=$item.RelativePath}
    }
    $manifest|Export-Csv -LiteralPath (Join-Path $ReportDirectory 'backup-sha256-manifest.csv') -NoTypeInformation -Encoding UTF8
}

[pscustomobject]$summary

