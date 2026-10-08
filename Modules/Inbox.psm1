Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Initialize-ODTInbox {
    param([string]$Root=(Join-Path (Get-AppRoot) 'Inbox'))
    foreach($name in @('Pending','Processed','Errors')){[IO.Directory]::CreateDirectory((Join-Path $Root $name))|Out-Null}
    return $Root
}

function New-DownloadManifest {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Url,[string]$Provider='External',[string]$Quality='Best available',[string]$Status='Pending',[string]$Error='')
    Initialize-ODTInbox -Root $Root|Out-Null
    $id=(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8);$path=Join-Path (Join-Path $Root 'Pending') "$id.json"
    $manifest=[pscustomobject]@{Id=$id;CreatedAt=(Get-Date).ToString('o');Url=$Url;Provider=$Provider;Quality=$Quality;Status=$Status;Error=$Error;Files=@();ProcessedAt=$null}
    Write-JsonFile -Path $path -Value $manifest;return $path
}

function Get-InboxManifest {
    param([Parameter(Mandatory)][string]$Path)
    $manifest=Read-JsonFile -Path $Path
    if(-not$manifest){return $null}
    $folder=Split-Path -Parent $Path;$base=Split-Path -Parent $folder
    $audio=@(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue|Where-Object Extension -in @('.mp3','.wav','.flac','.aiff','.aif','.m4a','.aac','.ogg','.wma'))
    $manifest|Add-Member NoteProperty ManifestPath $Path -Force;$manifest|Add-Member NoteProperty AudioFiles $audio -Force;$manifest|Add-Member NoteProperty InboxRoot $base -Force
    return $manifest
}

function Get-InboxItems {
    param([string]$Root=(Join-Path (Get-AppRoot) 'Inbox'))
    Initialize-ODTInbox -Root $Root|Out-Null
    $items=New-Object Collections.Generic.List[object]
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $Root 'Pending') -Filter '*.json' -File -ErrorAction SilentlyContinue)){$item=Get-InboxManifest -Path $file.FullName;if($item){$items.Add($item)}}
    return $items.ToArray()
}

function Complete-InboxManifest {
    param([Parameter(Mandatory)]$Manifest,[ValidateSet('Processed','Errors')][string]$Bucket='Processed',[string]$Message='')
    $Manifest.Status=$Bucket;$Manifest.Error=$Message;$Manifest.ProcessedAt=(Get-Date).ToString('o')
    $root=[string]$Manifest.InboxRoot;$destination=Join-Path (Join-Path $root $Bucket) (Split-Path -Leaf $Manifest.ManifestPath)
    if(Test-Path -LiteralPath $Manifest.ManifestPath){Move-Item -LiteralPath $Manifest.ManifestPath -Destination $destination -Force}
    # ManifestPath, InboxRoot e AudioFiles são propriedades de runtime. Persistir FileInfo
    # inteiro cria JSON recursivo/truncado e deixa a conclusão da Inbox lenta.
    $persisted=[pscustomobject]@{
        Id=[string]$Manifest.Id;CreatedAt=[string]$Manifest.CreatedAt;Url=[string]$Manifest.Url
        Provider=[string]$Manifest.Provider;Quality=[string]$Manifest.Quality;Status=[string]$Manifest.Status
        Error=[string]$Manifest.Error;Files=@($Manifest.Files);ProcessedAt=[string]$Manifest.ProcessedAt
    }
    Write-JsonFile -Path $destination -Value $persisted
    return $destination
}

Export-ModuleMember -Function Initialize-ODTInbox,New-DownloadManifest,Get-InboxManifest,Get-InboxItems,Complete-InboxManifest
