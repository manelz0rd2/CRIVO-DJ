Set-StrictMode -Version Latest

function Find-AudioDuplicates {
    param([Parameter(Mandatory)][object[]]$Tracks, [ValidateSet('Name','NameSize','Hash','Metadata')][string]$Level = 'NameSize')
    $groups = switch ($Level) {
        'Name' { $Tracks | Group-Object { $_.Name.ToLowerInvariant() } }
        'NameSize' { $Tracks | Group-Object { "$($_.Name.ToLowerInvariant())|$($_.Size)" } }
        'Hash' { $Tracks | Where-Object Hash | Group-Object Hash }
        'Metadata' { $Tracks | Group-Object { "$($_.Artist)|$($_.Title)|$($_.Size)".ToLowerInvariant() } }
    }
    @($groups | Where-Object Count -gt 1 | ForEach-Object { $_.Group })
}

Export-ModuleMember -Function Find-AudioDuplicates
