#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-PortableAssembly-'+[guid]::NewGuid().ToString('N'))

try {
    [IO.Directory]::CreateDirectory($testRoot)|Out-Null
    $source=Join-Path $app 'lib\TagLibSharp.dll'
    $blocked=Join-Path $testRoot 'TagLibSharp.dll'
    Copy-Item -LiteralPath $source -Destination $blocked
    try{Set-Content -LiteralPath $blocked -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII}catch{}
    Import-Module (Join-Path $app 'Modules\Common.psm1') -Force
    if(-not(Import-PortableAssembly -Path $blocked -TypeName 'TagLib.File')){throw 'O carregamento portátil retornou falha.'}
    $file=[TagLib.File]
    if($null -eq $file){throw 'O tipo TagLib.File não ficou disponível.'}
    Write-Output 'CARREGAMENTO PORTÁTIL PASSOU: DLL marcada como download foi aceita'
} finally {
    if(Test-Path -LiteralPath $testRoot){
        $resolved=[IO.Path]::GetFullPath($testRoot)
        $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
