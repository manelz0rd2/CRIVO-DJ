Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Save-OperationHistory {
    param([Parameter(Mandatory)]$Operation)
    $root = Get-AppDataRoot
    $path = Join-Path $root ("History\{0}.json" -f $Operation.Id)
    Write-JsonFile -Path $path -Value $Operation
    return $path
}

function Get-OperationHistory {
    $folder = Join-Path (Get-AppDataRoot) 'History'
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    @(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File | Sort-Object LastWriteTime -Descending | ForEach-Object {
        $item = Read-JsonFile -Path $_.FullName
        if ($item) { $item }
    })
}

function Write-AppLog {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $settingsPath=Join-Path (Get-AppDataRoot) 'Config\settings.json'
    if(-not(Test-Path -LiteralPath $settingsPath -PathType Leaf)){$settingsPath=Join-Path (Get-AppRoot) 'Config\settings.json'}
    $settings = Read-JsonFile -Path $settingsPath
    if ($settings -and $settings.LogLevel -eq 'Simple' -and $Level -eq 'INFO') { return }
    $path = Join-Path (Get-AppDataRoot) ("Logs\{0:yyyy-MM-dd}.log" -f (Get-Date))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}{3}" -f (Get-Date), $Level, $Message, [Environment]::NewLine
    [System.IO.File]::AppendAllText($path, $line, [System.Text.UTF8Encoding]::new($false))
}

function Undo-Operation {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Operation)
    $results = [System.Collections.Generic.List[object]]::new()
    if ($Operation.Action -eq 'Metadata') {
        $dll=Join-Path (Get-AppRoot) 'lib\TagLibSharp.dll';if(-not('TagLib.File' -as [type])){Add-Type -Path $dll}
        foreach($item in ($Operation.Items|ForEach-Object{$_}|Sort-Object Index -Descending)){
            $file=$null
            try{
                if($item.Result -ne 'Updated' -or -not$item.Before -or ($item.PSObject.Properties['UndoneAt'] -and $item.UndoneAt)){continue};$file=[TagLib.File]::Create([string]$item.Source)
                $file.Tag.Title=[string]$item.Before.Title;$file.Tag.Performers=[string[]]@($item.Before.Performers);$file.Tag.Album=[string]$item.Before.Album;$file.Tag.Genres=[string[]]@($item.Before.Genres);$file.Tag.Year=[uint32]$item.Before.Year;$file.Tag.BeatsPerMinute=[uint32]$item.Before.Bpm;$file.Tag.InitialKey=[string]$item.Before.Key;$file.Save()
                $item|Add-Member NoteProperty UndoneAt (Get-Date).ToString('o') -Force
                $results.Add([pscustomobject]@{File=$item.Source;Status='Metadata restaurada'})
            }catch{$results.Add([pscustomobject]@{File=$item.Source;Status='Erro';Error=$_.Exception.Message})}finally{if($file){try{$file.Dispose()}catch{}}}
        }
        $remaining=@($Operation.Items|Where-Object{$_.Result -eq 'Updated' -and (-not$_.PSObject.Properties['UndoneAt'] -or -not$_.UndoneAt)});if(-not$remaining.Count){$Operation|Add-Member -NotePropertyName UndoneAt -NotePropertyValue (Get-Date).ToString('o') -Force};Save-OperationHistory -Operation $Operation|Out-Null;return $results
    }
    foreach ($item in @($Operation.Items) | Sort-Object Index -Descending) {
        try {
            if ($item.Result -notin @('Copied','Moved','Renamed') -or ($item.PSObject.Properties['UndoneAt'] -and $item.UndoneAt)) { continue }
            $backupPath=if($item.PSObject.Properties['BackupPath']){[string]$item.BackupPath}else{''}
            $recordedHash=if($item.PSObject.Properties['DestinationHash']){[string]$item.DestinationHash}else{''}
            if((Test-Path -LiteralPath $item.Destination -PathType Leaf) -and $recordedHash){$currentHash=(Get-FileHash -LiteralPath $item.Destination -Algorithm SHA256).Hash;if($currentHash -ne $recordedHash){$results.Add([pscustomobject]@{File=$item.Destination;Status='Conflito';Error='O arquivo de destino foi alterado depois da organização.'});continue}}
            if ($Operation.Action -eq 'Move') {
                if (Test-Path -LiteralPath $item.Destination) {
                    if(Test-Path -LiteralPath $item.Source){$results.Add([pscustomobject]@{File=$item.Source;Status='Conflito';Error='A origem já contém outro arquivo; nada foi sobrescrito.'});continue}
                    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $item.Source)) | Out-Null
                    Move-Item -LiteralPath $item.Destination -Destination $item.Source
                    if($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)){Copy-Item -LiteralPath $backupPath -Destination $item.Destination -Force;$status='Faixa e arquivo substituído restaurados'}else{$status='Restaurado'}
                } else { throw 'O arquivo organizado não existe mais no destino.' }
            } else {
                if($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)){[System.IO.Directory]::CreateDirectory((Split-Path -Parent $item.Destination))|Out-Null;Copy-Item -LiteralPath $backupPath -Destination $item.Destination -Force;$status='Arquivo substituído restaurado'}
                elseif (Test-Path -LiteralPath $item.Destination) {Remove-Item -LiteralPath $item.Destination -Force;$status='Cópia removida'}
                else{$status='Cópia já estava ausente'}
            }
            $item|Add-Member NoteProperty UndoneAt (Get-Date).ToString('o') -Force
            $results.Add([pscustomobject]@{ File = $item.Destination; Status = $status })
        } catch {
            $results.Add([pscustomobject]@{ File = $item.Destination; Status = 'Erro'; Error = $_.Exception.Message })
        }
    }
    $remaining=@($Operation.Items|Where-Object{$_.Result -in @('Copied','Moved','Renamed') -and (-not$_.PSObject.Properties['UndoneAt'] -or -not$_.UndoneAt)});if(-not$remaining.Count){$Operation | Add-Member -NotePropertyName UndoneAt -NotePropertyValue (Get-Date).ToString('o') -Force}
    Save-OperationHistory -Operation $Operation | Out-Null
    return $results
}

Export-ModuleMember -Function Save-OperationHistory, Get-OperationHistory, Write-AppLog, Undo-Operation
