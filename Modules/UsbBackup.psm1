#requires -Version 5.1
Set-StrictMode -Version Latest

function Test-CrivoPathInside {
    param([string]$Candidate,[string]$Parent)
    $candidateFull=[IO.Path]::GetFullPath($Candidate).TrimEnd('\')+'\'
    $parentFull=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
    return $candidateFull.StartsWith($parentFull,[StringComparison]::OrdinalIgnoreCase)
}

function New-CrivoUsbBackupPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot)
    if(-not(Test-Path -LiteralPath $SourceRoot -PathType Container)){throw "A origem não foi encontrada: $SourceRoot"}
    if(-not(Test-Path -LiteralPath $DestinationRoot -PathType Container)){throw "O destino não foi encontrado: $DestinationRoot"}
    $source=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SourceRoot).Path).TrimEnd('\')
    $destination=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $DestinationRoot).Path).TrimEnd('\')
    if(Test-CrivoPathInside -Candidate $destination -Parent $source){throw 'Escolha um destino fora do dispositivo original.'}
    $files=[Collections.Generic.List[object]]::new();$total=0L
    foreach($file in @(Get-ChildItem -LiteralPath $source -Recurse -Force -File -ErrorAction Stop)){
        $relative=$file.FullName.Substring($source.Length).TrimStart('\')
        $files.Add([pscustomobject]@{Source=$file.FullName;RelativePath=$relative;Size=[int64]$file.Length;LastWriteTimeUtc=$file.LastWriteTimeUtc.ToString('o')})
        $total+=[int64]$file.Length
    }
    $free=$null
    try{$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($destination));if($drive.IsReady){$free=[int64]$drive.AvailableFreeSpace}}catch{}
    [pscustomobject]@{
        CreatedAt=Get-Date;SourceRoot=$source;DestinationRoot=$destination;Files=$files.ToArray();FileCount=$files.Count;TotalBytes=$total
        AvailableBytes=$free;SpaceConfirmed=($null -ne $free);EnoughSpace=($null -eq $free -or $free -ge ($total+104857600));ReadOnlySource=$true
    }
}

function Write-CrivoBackupReport {
    param([Parameter(Mandatory)]$Result)
    $encode={param($value)[Net.WebUtility]::HtmlEncode([string]$value)}
    $html=@"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>CRIVO DJ — Cópia segura</title><style>
body{margin:0;background:#b8b4ac;color:#171613;font-family:Arial,sans-serif}main{max-width:980px;margin:28px auto;padding:0 18px}header{background:#111214;color:#fff;padding:19px 22px}section{background:#d0ccc3;border:1px solid #777269;padding:18px;margin-top:14px}.ok{border-left:6px solid #485c43}li{margin:8px 0}code{word-break:break-all}</style></head><body><main>
<header><b>CRIVO DJ</b> — Cópia segura</header><section class="ok"><h1>Cópia criada e validada</h1><p>O dispositivo original não foi alterado.</p></section>
<section><ul><li>$($Result.FileCount) arquivo(s)</li><li>$($Result.TotalBytes) bytes</li><li>$($Result.VerifiedCount) hashes SHA-256 conferidos</li><li>Falhas: $($Result.ErrorCount)</li></ul><p><b>Origem:</b> <code>$(& $encode $Result.SourceRoot)</code></p><p><b>Cópia:</b> <code>$(& $encode $Result.BackupRoot)</code></p></section>
<section><p>A validação confirma que os arquivos copiados correspondem aos arquivos lidos da origem durante esta operação. Ela não garante a condição física futura da memória nem substitui um teste no equipamento.</p></section>
</main></body></html>
"@
    [IO.File]::WriteAllText((Join-Path $Result.BackupRoot 'Relatorio-da-copia.html'),$html,[Text.UTF8Encoding]::new($false))
}

function Invoke-CrivoUsbBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan,[scriptblock]$OnProgress)
    if(-not$Plan.EnoughSpace){throw "O destino não possui espaço livre suficiente. Necessário: $($Plan.TotalBytes) bytes; disponível: $($Plan.AvailableBytes) bytes."}
    if(-not(Test-Path -LiteralPath $Plan.SourceRoot -PathType Container)){throw 'A origem foi desconectada antes do início da cópia.'}
    if(-not(Test-Path -LiteralPath $Plan.DestinationRoot -PathType Container)){throw 'O destino não está mais disponível.'}
    if(Test-CrivoPathInside -Candidate $Plan.DestinationRoot -Parent $Plan.SourceRoot){throw 'O destino não pode ficar dentro do dispositivo original.'}
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $partial=Join-Path $Plan.DestinationRoot "CRIVO DJ - Copia segura - $stamp.incompleta"
    $final=Join-Path $Plan.DestinationRoot "CRIVO DJ - Copia segura - $stamp"
    if((Test-Path -LiteralPath $partial) -or (Test-Path -LiteralPath $final)){throw 'Já existe uma cópia com o mesmo identificador de horário. Aguarde um segundo e tente novamente.'}
    [IO.Directory]::CreateDirectory($partial)|Out-Null
    $manifest=[Collections.Generic.List[object]]::new();$index=0
    try{
        foreach($item in @($Plan.Files)){
            $index++;$source=[string]$item.Source;$relative=[string]$item.RelativePath;$destination=Join-Path $partial $relative
            if($OnProgress){&$OnProgress $index ([int]$Plan.FileCount) $relative 'Copiando'}
            if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "O arquivo deixou de estar disponível: $relative"}
            [IO.Directory]::CreateDirectory((Split-Path $destination -Parent))|Out-Null
            $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash
            [IO.File]::Copy($source,$destination,$false)
            [IO.File]::SetLastWriteTimeUtc($destination,[datetime]::Parse([string]$item.LastWriteTimeUtc).ToUniversalTime())
            $destinationHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            if($sourceHash -ne $destinationHash){throw "A validação falhou para: $relative"}
            $manifest.Add([pscustomobject]@{RelativePath=$relative;Size=[int64]$item.Size;SHA256=$sourceHash;Validated=$true})
        }
        if($manifest.Count -ne [int]$Plan.FileCount){throw 'A quantidade final de arquivos não corresponde ao plano.'}
        $copiedBytes=($manifest|Measure-Object Size -Sum).Sum
        if([int64]$copiedBytes -ne [int64]$Plan.TotalBytes){throw 'O total de bytes da cópia não corresponde à origem.'}
        $result=[pscustomobject]@{Success=$true;CreatedAt=Get-Date;SourceRoot=$Plan.SourceRoot;BackupRoot=$final;FileCount=$Plan.FileCount;TotalBytes=$Plan.TotalBytes;VerifiedCount=$manifest.Count;ErrorCount=0;SourceUnchanged=$true}
        [IO.File]::WriteAllText((Join-Path $partial 'Manifesto-SHA256.json'),($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        [IO.Directory]::Move($partial,$final)
        Write-CrivoBackupReport -Result $result
        [IO.File]::WriteAllText((Join-Path $final 'Relatorio-tecnico.json'),($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        return $result
    }catch{
        $message="Esta cópia está incompleta e não foi validada.`r`n`r`n$($_.Exception.Message)`r`n`r`nO dispositivo original não foi alterado."
        try{[IO.File]::WriteAllText((Join-Path $partial 'LEIA-ME-COPIA-INCOMPLETA.txt'),$message,[Text.UTF8Encoding]::new($true))}catch{}
        throw ("A cópia não foi concluída. A origem não foi alterada. Destino parcial: $partial`n$($_.Exception.Message)")
    }
}

Export-ModuleMember -Function New-CrivoUsbBackupPlan,Invoke-CrivoUsbBackup
