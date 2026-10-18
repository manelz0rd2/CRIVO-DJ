#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $app 'Modules\EquipmentCompatibility.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Compatibility-'+[guid]::NewGuid().ToString('N'))

try{
    [IO.Directory]::CreateDirectory((Join-Path $root 'PIONEER\rekordbox'))|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $root 'PIONEER\rekordbox\EXPORT.PDB'),[byte[]](1,2,3))
    $rows=@(
        [pscustomobject]@{Title='Faixa MP3';Codec='MP3';Bitrate=320;SampleRate=44100;Exists=$true;Readable=$true},
        [pscustomobject]@{Title='Faixa FLAC';Codec='FLAC';Bitrate=0;SampleRate=96000;Exists=$true;Readable=$true}
    )
    $health=[pscustomobject]@{Root=$root;Device=[pscustomobject]@{FileSystem='FAT32'};Audit=[pscustomobject]@{Rows=$rows;StructureIssues=0;AnalysisIssues=0}}
    $catalog=Get-CrivoEquipmentCatalog
    $expectedProfiles=@('cdj-2000','cdj-2000nxs2','cdj-3000','cdj-3000x','xdj-az','xdj-xz','xdj-rx2','xdj-rx3','xdj-rr','xdj-1000mk2')
    foreach($expected in $expectedProfiles){if(-not@($catalog.Profiles|Where-Object Id -eq $expected).Count){throw "O perfil obrigatório '$expected' não foi carregado."}}
    foreach($profile in @($catalog.Profiles)){
        if([string]::IsNullOrWhiteSpace([string]$profile.SourceUrl) -or ([string]$profile.SourceUrl -notmatch 'pioneerdj\.com|alphatheta\.com')){throw "O perfil $($profile.Name) não aponta para fonte oficial."}
    }
    $old=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-2000'
    if($old.Overall -ne 'Incompatível' -or -not@($old.Checks|Where-Object{$_.Name -eq 'Formatos de áudio' -and $_.Level -eq 'Incompatível'}).Count){throw 'O FLAC não foi recusado no perfil conservador do CDJ-2000.'}
    $nxs2=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-2000nxs2'
    if($nxs2.Overall -ne 'Compatível'){throw "O cenário compatível do CDJ-2000NXS2 retornou: $($nxs2.Overall)"}
    $new=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-3000x'
    if($new.Overall -ne 'Incompatível' -or -not@($new.Checks|Where-Object{$_.Name -eq 'Biblioteca do Rekordbox' -and $_.Level -eq 'Incompatível'}).Count){throw 'A ausência de OneLibrary não foi indicada para o CDJ-3000X.'}
    [IO.File]::WriteAllBytes((Join-Path $root 'PIONEER\rekordbox\exportLibrary.db'),[byte[]](4,5,6))
    $new=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-3000x'
    if($new.Overall -ne 'Compatível'){throw "O cenário compatível do CDJ-3000X retornou: $($new.Overall)"}
    $health.Audit.StructureIssues=2
    $damaged=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-3000x'
    if($damaged.Overall -ne 'Pode apresentar problema' -or -not@($damaged.Checks|Where-Object{$_.Name -eq 'Integridade da biblioteca'}).Count){throw 'Uma biblioteca danificada foi apresentada como compatível.'}
    $health.Audit.StructureIssues=0
    $rx2=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'xdj-rx2'
    if($rx2.Overall -ne 'Incompatível' -or -not@($rx2.Checks|Where-Object{$_.Name -eq 'Formatos de áudio' -and $_.Level -eq 'Incompatível'}).Count){throw 'O perfil conservador do XDJ-RX2 aceitou FLAC.'}
    $rows[1].SampleRate=48000
    $xz=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'xdj-xz'
    if($xz.Overall -ne 'Não foi possível confirmar'){throw 'O XDJ-XZ não sinalizou a dependência de firmware para FLAC.'}
    $mk2=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'xdj-1000mk2'
    if($mk2.Overall -ne 'Compatível'){throw "O cenário documentado do XDJ-1000MK2 retornou: $($mk2.Overall)"}
    $az=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'xdj-az'
    if($az.Overall -ne 'Compatível'){throw "O cenário OneLibrary do XDJ-AZ retornou: $($az.Overall)"}
    $health.Device.FileSystem='NTFS'
    $ntfs=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-3000x'
    if(-not@($ntfs.Checks|Where-Object{$_.Name -eq 'Sistema de arquivos' -and $_.Level -eq 'Incompatível'}).Count){throw 'NTFS não foi recusado pelo perfil oficial.'}
    $health.Device.FileSystem='';$unknown=Test-CrivoEquipmentCompatibility -HealthReport $health -ProfileId 'cdj-3000x'
    if($unknown.Overall -ne 'Não foi possível confirmar'){throw 'A ausência do sistema de arquivos foi tratada como certeza.'}
    Write-Output 'COMPATIBILIDADE OK: catálogo oficial, cenários compatível, incompatível e não confirmado.'
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
