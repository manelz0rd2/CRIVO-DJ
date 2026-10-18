Set-StrictMode -Version Latest

function Get-AppRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-AppDataRoot {
    if ($env:ODT_DATA_ROOT) { return $env:ODT_DATA_ROOT }
    return Join-Path $env:LOCALAPPDATA 'CRIVO DJ'
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path, $Default = $null)
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $Default }
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $folder = Split-Path -Parent $Path
    if ($folder) { [System.IO.Directory]::CreateDirectory($folder) | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-SafePathPart {
    param([AllowNull()][string]$Value, [string]$Fallback = 'Dado faltante')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $result = $Value.Trim() -replace '[<>:"/\\|?*]', '-'
    $result = $result -replace '\s+', ' '
    $result = $result.Trim(' ', '.')
    if ($result -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { $result = "_$result" }
    if ([string]::IsNullOrWhiteSpace($result)) { return $Fallback }
    if ($result.Length -gt 80) { $result = $result.Substring(0, 80).Trim() }
    return $result
}

function Get-RelativePathSafe {
    param([Parameter(Mandatory)][string]$BasePath, [Parameter(Mandatory)][string]$Path)
    try { return [System.IO.Path]::GetRelativePath($BasePath, $Path) }
    catch {
        $baseUri = [Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
        $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
        return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
    }
}

function Import-PortableAssembly {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$TypeName=''
    )
    if($TypeName -and ($TypeName -as [type])){return $true}
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Componente necessário não encontrado: $Path"}
    try {
        # Carregar pelos bytes evita o bloqueio 0x80131515 aplicado pelo
        # Windows a DLLs extraídas de um ZIP baixado da internet. A DLL segue
        # sendo a cópia empacotada e controlada pelo próprio CRIVO.
        [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Path))
    } catch {
        try { Add-Type -Path $Path -ErrorAction Stop } catch { throw "Não foi possível carregar um componente do CRIVO. Extraia novamente o pacote completo. Detalhe: $($_.Exception.Message)" }
    }
    if($TypeName -and -not($TypeName -as [type])){throw "O componente foi carregado, mas não disponibilizou $TypeName."}
    return $true
}

Export-ModuleMember -Function Get-AppRoot, Get-AppDataRoot, Read-JsonFile, Write-JsonFile, ConvertTo-SafePathPart, Get-RelativePathSafe, Import-PortableAssembly
