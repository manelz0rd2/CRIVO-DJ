#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CrivoEquipmentCatalog {
    [CmdletBinding()]
    param([string]$Path=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Config\equipamentos.json'))
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Catálogo de equipamentos não encontrado: $Path"}
    try{$catalog=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{throw "O catálogo de equipamentos não pôde ser lido: $($_.Exception.Message)"}
    if(-not$catalog -or -not$catalog.Profiles){throw 'O catálogo de equipamentos está vazio.'}
    return $catalog
}

function New-CrivoCompatibilityCheck {
    param([string]$Name,[string]$Level,[string]$Summary,[string]$Detail='')
    [pscustomobject]@{Name=$Name;Level=$Level;Summary=$Summary;Detail=$Detail}
}

function Test-CrivoEquipmentCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$HealthReport,
        [Parameter(Mandatory)][string]$ProfileId,
        [string]$CatalogPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Config\equipamentos.json')
    )
    $catalog=Get-CrivoEquipmentCatalog -Path $CatalogPath
    $profile=@($catalog.Profiles|Where-Object{[string]$_.Id -eq $ProfileId}|Select-Object -First 1)
    if(-not$profile.Count){throw "O equipamento '$ProfileId' não existe no catálogo atual."}
    $profile=$profile[0]
    $checks=[Collections.Generic.List[object]]::new()
    $root=[string]$HealthReport.Root
    $isVolumeRoot=if($HealthReport.Device.PSObject.Properties['IsVolumeRoot']){[bool]$HealthReport.Device.IsVolumeRoot}else{$true}
    $fileSystem=if($isVolumeRoot){([string]$HealthReport.Device.FileSystem).ToUpperInvariant()}else{''}
    $supportedFileSystems=@($profile.FileSystems|ForEach-Object{([string]$_).ToUpperInvariant()})
    if(-not$fileSystem){
        $summary=if($isVolumeRoot){'O Windows não informou o sistema de arquivos.'}else{'A origem é uma pasta de teste, não a raiz do dispositivo original.'}
        $checks.Add((New-CrivoCompatibilityCheck 'Sistema de arquivos' 'Não foi possível confirmar' $summary 'O CRIVO não presume compatibilidade sem esse dado.'))
    }elseif($supportedFileSystems -contains $fileSystem){
        $checks.Add((New-CrivoCompatibilityCheck 'Sistema de arquivos' 'Compatível' "$fileSystem está na lista documentada para este perfil."))
    }else{
        $checks.Add((New-CrivoCompatibilityCheck 'Sistema de arquivos' 'Incompatível' "$fileSystem não consta entre os sistemas aceitos pelo perfil." ("Documentado: "+($supportedFileSystems -join ', '))))
    }

    $rekordboxRoot=Join-Path $root 'PIONEER\rekordbox'
    $hasDeviceLibrary=Test-Path -LiteralPath (Join-Path $rekordboxRoot 'EXPORT.PDB') -PathType Leaf
    $hasOneLibrary=Test-Path -LiteralPath (Join-Path $rekordboxRoot 'exportLibrary.db') -PathType Leaf
    $libraryOk=switch([string]$profile.LibraryMode){'DeviceLibrary'{$hasDeviceLibrary}'OneLibrary'{$hasOneLibrary}default{$hasDeviceLibrary -or $hasOneLibrary}}
    if($libraryOk){
        $found=@();if($hasDeviceLibrary){$found+='Device Library'};if($hasOneLibrary){$found+='OneLibrary'}
        $checks.Add((New-CrivoCompatibilityCheck 'Biblioteca do Rekordbox' 'Compatível' (($found -join ' e ')+' encontrada(s).') 'Isso confirma a presença da estrutura, não a integridade de todas as playlists.'))
    }else{
        $required=switch([string]$profile.LibraryMode){'DeviceLibrary'{'Device Library'}'OneLibrary'{'OneLibrary'}default{'Device Library ou OneLibrary'}}
        $checks.Add((New-CrivoCompatibilityCheck 'Biblioteca do Rekordbox' 'Incompatível' "$required não foi encontrada." 'As tracks ainda podem existir como arquivos, mas a navegação das playlists pelo equipamento não está confirmada.'))
    }

    # A presença do banco não basta: uma biblioteca parcialmente danificada pode
    # ser reconhecida pelo equipamento e ainda assim exibir playlists incompletas.
    $structureIssues=0
    $analysisIssues=0
    if($HealthReport.PSObject.Properties['Audit'] -and $HealthReport.Audit){
        if($HealthReport.Audit.PSObject.Properties['StructureIssues']){$structureIssues=[int]$HealthReport.Audit.StructureIssues}
        if($HealthReport.Audit.PSObject.Properties['AnalysisIssues']){$analysisIssues=[int]$HealthReport.Audit.AnalysisIssues}
    }
    if($structureIssues -gt 0){
        $checks.Add((New-CrivoCompatibilityCheck 'Integridade da biblioteca' 'Pode apresentar problema' "$structureIssues parte(s) da biblioteca não puderam ser lidas com segurança." 'O equipamento pode reconhecer o dispositivo e ainda mostrar playlists ou tracks incompletas. Faça uma cópia segura antes de tentar recuperar.'))
    }else{
        $checks.Add((New-CrivoCompatibilityCheck 'Integridade da biblioteca' 'Compatível' 'Nenhum problema estrutural foi encontrado na parte da biblioteca que pôde ser verificada.' 'Isso não garante que todas as playlists estejam completas.'))
    }
    if($analysisIssues -gt 0){
        $checks.Add((New-CrivoCompatibilityCheck 'Dados de análise' 'Pode apresentar problema' "$analysisIssues dado(s) de análise estão ausentes ou não puderam ser lidos." 'A track pode tocar, mas forma de onda, grade, BPM ou pontos salvos podem não aparecer como esperado.'))
    }

    $audioRows=@($HealthReport.Audit.Rows|Where-Object{([string]$_.Codec).ToUpperInvariant() -notin @('DB','ANLZ','') -and $_.Exists})
    $extensions=@($profile.Extensions|ForEach-Object{([string]$_).ToUpperInvariant()})
    $unsupported=@($audioRows|Where-Object{$extensions -notcontains ([string]$_.Codec).ToUpperInvariant()})
    $uncertainExtensions=if($profile.PSObject.Properties['UncertainExtensions']){@($profile.UncertainExtensions|ForEach-Object{([string]$_).ToUpperInvariant()})}else{@()}
    $uncertain=@($audioRows|Where-Object{$uncertainExtensions -contains ([string]$_.Codec).ToUpperInvariant()})
    if($unsupported.Count){
        $examples=@($unsupported|Select-Object -First 4|ForEach-Object{"$($_.Title) (.$(([string]$_.Codec).ToLowerInvariant()))"}) -join '; '
        $checks.Add((New-CrivoCompatibilityCheck 'Formatos de áudio' 'Incompatível' "$($unsupported.Count) arquivo(s) têm extensão não aceita pelo perfil." $examples))
    }elseif($uncertain.Count){
        $checks.Add((New-CrivoCompatibilityCheck 'Formatos de áudio' 'Não foi possível confirmar' "$($uncertain.Count) arquivo(s) usam uma extensão que pode conter codecs diferentes." 'A extensão sozinha não permite confirmar se o conteúdo será decodificado pelo equipamento.'))
    }elseif($audioRows.Count){
        $checks.Add((New-CrivoCompatibilityCheck 'Formatos de áudio' 'Compatível' "As extensões dos $($audioRows.Count) áudio(s) estão na lista documentada." 'A extensão não garante sozinha o codec interno nem a reprodução integral.'))
    }else{
        $checks.Add((New-CrivoCompatibilityCheck 'Formatos de áudio' 'Não foi possível confirmar' 'Nenhum áudio legível entrou nesta comparação.'))
    }

    $maximum=[int]$profile.MaximumSampleRate
    $above=@($audioRows|Where-Object{[int]$_.SampleRate -gt $maximum})
    $unknownRate=@($audioRows|Where-Object{[int]$_.SampleRate -le 0})
    if($above.Count){
        $checks.Add((New-CrivoCompatibilityCheck 'Sample rate' 'Incompatível' "$($above.Count) arquivo(s) ultrapassam $maximum Hz." 'Converta somente a partir de uma cópia e preserve os originais.'))
    }elseif($unknownRate.Count){
        $checks.Add((New-CrivoCompatibilityCheck 'Sample rate' 'Não foi possível confirmar' "$($unknownRate.Count) arquivo(s) não informaram sample rate." "$($audioRows.Count-$unknownRate.Count) arquivo(s) ficaram dentro do limite conhecido."))
    }elseif($audioRows.Count){
        $checks.Add((New-CrivoCompatibilityCheck 'Sample rate' 'Compatível' "Todos os valores identificados ficaram em até $maximum Hz."))
    }else{
        $checks.Add((New-CrivoCompatibilityCheck 'Sample rate' 'Não foi possível confirmar' 'Não havia valores para comparar.'))
    }

    $mp3=@($audioRows|Where-Object{([string]$_.Codec).ToUpperInvariant() -eq 'MP3'})
    $invalidMp3=@($mp3|Where-Object{[int]$_.Bitrate -gt 0 -and ([int]$_.Bitrate -lt 32 -or [int]$_.Bitrate -gt 320)})
    $unknownMp3=@($mp3|Where-Object{[int]$_.Bitrate -le 0})
    if($invalidMp3.Count){$checks.Add((New-CrivoCompatibilityCheck 'Bitrate MP3' 'Incompatível' "$($invalidMp3.Count) MP3 ficaram fora de 32–320 kbps."))}
    elseif($unknownMp3.Count){$checks.Add((New-CrivoCompatibilityCheck 'Bitrate MP3' 'Não foi possível confirmar' "$($unknownMp3.Count) MP3 não informaram bitrate."))}
    elseif($mp3.Count){$checks.Add((New-CrivoCompatibilityCheck 'Bitrate MP3' 'Compatível' "$($mp3.Count) MP3 ficaram entre 32 e 320 kbps."))}
    else{$checks.Add((New-CrivoCompatibilityCheck 'Bitrate MP3' 'Não foi possível confirmar' 'Nenhum MP3 entrou na comparação.'))}

    $unreadable=@($HealthReport.Audit.Rows|Where-Object{$_.Exists -and -not$_.Readable -and ([string]$_.Codec).ToUpperInvariant() -notin @('DB','ANLZ')})
    if($unreadable.Count){$checks.Add((New-CrivoCompatibilityCheck 'Leitura dos arquivos' 'Incompatível' "$($unreadable.Count) arquivo(s) não puderam ser lidos com segurança."))}
    else{$checks.Add((New-CrivoCompatibilityCheck 'Leitura dos arquivos' 'Compatível' 'Nenhuma falha de leitura de áudio foi confirmada nesta verificação.' 'Isso não substitui a reprodução completa de todas as tracks.'))}

    $levels=@($checks|ForEach-Object{[string]$_.Level})
    $overall=if($levels -contains 'Incompatível'){'Incompatível'}elseif($levels -contains 'Pode apresentar problema'){'Pode apresentar problema'}elseif($levels -contains 'Não foi possível confirmar'){'Não foi possível confirmar'}else{'Compatível'}
    [pscustomobject]@{
        GeneratedAt=Get-Date;Root=$root;Profile=$profile;Overall=$overall;Checks=$checks.ToArray();ReadOnly=$true
        CompatibleCount=@($checks|Where-Object Level -eq 'Compatível').Count
        ProblemCount=@($checks|Where-Object Level -eq 'Incompatível').Count
        UnknownCount=@($checks|Where-Object Level -eq 'Não foi possível confirmar').Count
        Limitation='O resultado cobre somente requisitos documentados e dados que o CRIVO conseguiu ler. Ele não substitui um teste no equipamento real.'
    }
}

Export-ModuleMember -Function Get-CrivoEquipmentCatalog,Test-CrivoEquipmentCompatibility
