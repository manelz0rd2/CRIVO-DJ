#requires -Version 5.1
Set-StrictMode -Version Latest

function Invoke-CrivoUsbRecoveryHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Payload,
        [int]$TimeoutSeconds=900,
        [scriptblock]$OnWait
    )

    $appRoot=Split-Path -Parent $PSScriptRoot
    $helper=Join-Path $appRoot 'Tools\CRIVO-UsbRecovery\CRIVO-UsbRecovery.exe'
    if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw "Motor de recuperação não encontrado: $helper"}
    $token=[guid]::NewGuid().ToString('N')
    $payloadPath=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Recovery-$token.json"
    $stdout=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Recovery-$token.out"
    $stderr=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Recovery-$token.err"
    try{
        [IO.File]::WriteAllText($payloadPath,($Payload|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        $process=Start-Process -FilePath $helper -ArgumentList @("`"$payloadPath`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        [void]$process.Handle
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while(-not$process.WaitForExit(250)){
            if($OnWait){&$OnWait}
            if([DateTime]::UtcNow -ge $deadline){
                try{$process.Kill();$process.WaitForExit()}catch{}
                throw "A operação ultrapassou $TimeoutSeconds segundos e foi encerrada sem alterar a origem."
            }
        }
        $process.WaitForExit();$process.Refresh()
        $output=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8).Trim()}else{''}
        $errorOutput=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr,[Text.Encoding]::UTF8).Trim()}else{''}
        $result=$null
        if($output){try{$result=$output|ConvertFrom-Json}catch{}}
        $exitCode=$process.ExitCode
        if(($null -ne $exitCode -and $exitCode -ne 0) -or $null -eq $result -or -not ([bool]$result.success)){
            $message=if($result -and $result.PSObject.Properties['message']){[string]$result.message}elseif($errorOutput){$errorOutput}elseif($output){$output}else{'O motor de recuperação não retornou um resultado válido.'}
            throw $message
        }
        return $result
    }finally{
        foreach($path in @($payloadPath,$stdout,$stderr)){if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}}
    }
}

function New-CrivoUsbRecoveryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [scriptblock]$OnWait
    )
    if(-not(Test-Path -LiteralPath $SourceRoot -PathType Container)){throw "A origem não foi encontrada: $SourceRoot"}
    $database=Join-Path $SourceRoot 'PIONEER\rekordbox\EXPORT.PDB'
    if(-not(Test-Path -LiteralPath $database -PathType Leaf)){throw 'A biblioteca antiga do Rekordbox não foi encontrada neste dispositivo.'}
    [IO.Directory]::CreateDirectory($WorkingDirectory)|Out-Null
    $planPath=Join-Path $WorkingDirectory ("plano-recuperacao-"+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.json')
    $result=Invoke-CrivoUsbRecoveryHelper -Payload ([ordered]@{operation='analyze';databasePath=$database;sourceRoot=$SourceRoot;planPath=$planPath}) -TimeoutSeconds 300 -OnWait $OnWait
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json
    [pscustomobject]@{Result=$result;Plan=$plan;PlanPath=$planPath;SourceRoot=[IO.Path]::GetFullPath($SourceRoot)}
}

function Invoke-CrivoUsbRecoveryCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [scriptblock]$OnWait
    )
    if(-not(Test-Path -LiteralPath $PlanPath -PathType Leaf)){throw "O plano de recuperação não foi encontrado: $PlanPath"}
    if(-not(Test-Path -LiteralPath $DestinationRoot -PathType Container)){throw "O destino não foi encontrado: $DestinationRoot"}
    Invoke-CrivoUsbRecoveryHelper -Payload ([ordered]@{operation='recover';planPath=$PlanPath;destinationRoot=$DestinationRoot}) -TimeoutSeconds 3600 -OnWait $OnWait
}

Export-ModuleMember -Function New-CrivoUsbRecoveryPlan,Invoke-CrivoUsbRecoveryCopy

