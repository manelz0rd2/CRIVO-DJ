#requires -Version 5.1
[CmdletBinding()]
param([int]$TrackCount = 300)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$app = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CRIVO-Organizer-Stress-' + [guid]::NewGuid().ToString('N'))

function Assert-True { param([bool]$Condition,[string]$Message) if(-not$Condition){throw "FALHOU: $Message"} }

try {
    $env:ODT_DATA_ROOT = Join-Path $testRoot 'Dados'
    Import-Module (Join-Path $app 'Modules\Organizer.psm1') -Force
    Import-Module (Join-Path $app 'Modules\History.psm1') -Force
    $settings = Get-Content -LiteralPath (Join-Path $app 'Config\settings.json') -Raw | ConvertFrom-Json
    $source = Join-Path $testRoot 'Origem'
    $destination = Join-Path $testRoot 'Destino'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.Directory]::CreateDirectory($destination) | Out-Null

    $tracks = New-Object Collections.Generic.List[object]
    for($i=1;$i -le $TrackCount;$i++){
        $path=Join-Path $source ("track-{0:D4}.mp3" -f $i)
        [IO.File]::WriteAllBytes($path,[byte[]]([byte]($i % 251),2,3,4))
        $tracks.Add([pscustomobject]@{
            Selected=($i%6 -ne 0);Name=[IO.Path]::GetFileName($path);OutputName='Mesmo Nome.mp3';FullName=$path;Directory=$source;Extension='.mp3';Size=4
            Created=(Get-Date '2026-02-03');Modified=(Get-Date '2026-02-03');Title='Nome: inválido / teste';Artist='CON';Album='Álbum';Genre='House/Deep';Year='2026'
            Bpm=128;Key='8A';Bitrate=320;SampleRate=44100;BitDepth=16;Codec='MP3';Duration='00:01';ISRC='';MetadataError='';BitrateMin=320;BitrateMax=320
            BitrateAverage=320;BitrateMode='CBR';BitrateMap='';MissingTitle=$false;MissingGenre=$false;IsCorrupt=$false;QualityStatus='OK';Hash='';Status='Analisado';Destination='';Rule='';Error=''
        })
    }

    $timer=[Diagnostics.Stopwatch]::StartNew()
    $plan=New-OrganizationPlan -Tracks $tracks.ToArray() -Source $source -Destination $destination -Template '{AAAA}\{GENERO}\{BPM_RANGE}\{ARTISTA}' -TreeMode FlattenSource -Action Copy -Conflict Rename -RenameFiles -Settings $settings
    $timer.Stop()
    $expected=$TrackCount-[Math]::Floor($TrackCount/6)
    Assert-True ($plan.Items.Count -eq $expected) 'o plano deve respeitar todas as marcações do grid'
    Assert-True (@($tracks|Where-Object{-not$_.Selected -and ($_.Status -ne 'Desmarcada' -or $_.Destination)}).Count -eq 0) 'tracks desmarcadas não podem conservar destino ou status de plano anterior'
    Assert-True (@($plan.Items|Select-Object -ExpandProperty Destination -Unique).Count -eq $expected) 'colisões em lote devem gerar destinos únicos'
    $destinationPrefix=[IO.Path]::GetFullPath($destination).TrimEnd('\')+'\'
    Assert-True (@($plan.Items|Where-Object{-not$_.Destination.StartsWith($destinationPrefix,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 0) 'nenhum destino pode escapar da raiz escolhida'
    Assert-True ($timer.Elapsed.TotalSeconds -lt 15) 'o cálculo de um lote grande deve permanecer responsivo'

    $result=Invoke-OrganizationPlan -Plan $plan
    Assert-True ($result.Success -eq $expected -and $result.Errors -eq 0 -and $result.Skipped -eq 0) 'a aplicação em lote deve contar somente tracks realmente copiadas'
    Assert-True (@(Get-ChildItem -LiteralPath $destination -File -Recurse).Count -eq $expected) 'todas as tracks marcadas devem existir no destino'

    $missing=$tracks[0].PSObject.Copy();$missing.FullName=Join-Path $source 'apagada.mp3';$missing.Name='apagada.mp3';$missing.OutputName='apagada.mp3';$missing.Selected=$true
    $missingPlan=New-OrganizationPlan -Tracks @($missing) -Source $source -Destination (Join-Path $testRoot 'Ausente') -Template '{GENERO}' -TreeMode FlattenSource -Settings $settings
    Assert-True ($missingPlan.Items[0].Status -eq 'Error') 'origem removida após o scan deve bloquear a execução no plano'

    $outsidePath=Join-Path $testRoot 'fora.mp3';[IO.File]::WriteAllBytes($outsidePath,[byte[]](1,2,3));$outside=$tracks[0].PSObject.Copy();$outside.FullName=$outsidePath;$outside.Directory=$testRoot;$outside.Name='fora.mp3';$outside.OutputName='fora.mp3';$outside.Selected=$true
    $outsideRejected=$false;try{New-OrganizationPlan -Tracks @($outside) -Source $source -Destination (Join-Path $testRoot 'Escape') -Template '{GENERO}' -TreeMode PreserveTree -Settings $settings|Out-Null}catch{$outsideRejected=$true}
    Assert-True $outsideRejected 'uma track fora da origem selecionada deve ser recusada'

    $conflictSource=Join-Path $source 'conflito.mp3';[IO.File]::WriteAllBytes($conflictSource,[byte[]](9,8,7));$conflict=$tracks[0].PSObject.Copy();$conflict.FullName=$conflictSource;$conflict.Directory=$source;$conflict.Name='conflito.mp3';$conflict.OutputName='conflito.mp3';$conflict.Selected=$true
    $skipDestination=Join-Path $testRoot 'Skip';$skipPlan=New-OrganizationPlan -Tracks @($conflict) -Source $source -Destination $skipDestination -Template '{GENERO}' -TreeMode FlattenSource -Conflict Skip -Settings $settings
    [IO.Directory]::CreateDirectory((Split-Path -Parent $skipPlan.Items[0].Destination))|Out-Null;[IO.File]::WriteAllBytes($skipPlan.Items[0].Destination,[byte[]](0))
    $skipResult=Invoke-OrganizationPlan -Plan $skipPlan
    Assert-True ($skipResult.Success -eq 0 -and $skipResult.Skipped -eq 1) 'um conflito pulado não pode ser apresentado como sucesso'

    $faultDestination=Join-Path $testRoot 'Falha';$good=$conflict.PSObject.Copy();$good.Name='bom.mp3';$good.OutputName='bom.mp3';$good.FullName=Join-Path $source 'bom.mp3';[IO.File]::WriteAllBytes($good.FullName,[byte[]](1));$good.Genre='Good'
    $bad=$conflict.PSObject.Copy();$bad.Name='ruim.mp3';$bad.OutputName='ruim.mp3';$bad.FullName=Join-Path $source 'ruim.mp3';[IO.File]::WriteAllBytes($bad.FullName,[byte[]](2));$bad.Genre='Bad'
    $faultPlan=New-OrganizationPlan -Tracks @($good,$bad) -Source $source -Destination $faultDestination -Template '{GENERO}' -TreeMode FlattenSource -Conflict Rename -Settings $settings
    [IO.Directory]::CreateDirectory($faultDestination)|Out-Null;[IO.File]::WriteAllBytes((Join-Path $faultDestination 'Bad'),[byte[]](5))
    $faultResult=Invoke-OrganizationPlan -Plan $faultPlan
    $badDone=@($faultResult.Operation.Items|Where-Object Source -eq $bad.FullName)[0]
    Assert-True ($badDone.Result -eq 'Error' -and $badDone.Destination -eq $faultPlan.Items[1].Destination) 'uma falha de diretório deve registrar o destino da própria track, nunca o item anterior'

    [xml]$xaml=Get-Content -LiteralPath (Join-Path $app 'UI\MainWindow.xaml') -Raw
    $organizeTab=@($xaml.SelectNodes('//*[local-name()="TabItem"]')|Where-Object{$_.GetAttribute('Header') -eq 'ORGANIZAR'})[0]
    $organizeText=$organizeTab.OuterXml
    Assert-True ($organizeText -notmatch 'ANÁLISE PRÉVIA') 'o botão removido de análise prévia não pode reaparecer na aba Organizar'
    Assert-True ($organizeText -match 'TRACKS AO TODO' -and $organizeText -match 'EDITAR DADOS FALTANTES' -and $organizeText -match 'TRACKS COM DADOS FALTANTES' -and $organizeText -match '05 / REGRAS E SEGURANÇA' -and $organizeText -match 'Verificar tracks repetidas') 'os nomes e a ordem acordados da aba Organizar devem permanecer visíveis'
    Assert-True ($organizeText -notmatch 'TRATATIVA DE ERRO') 'o título antigo da seção 03 não pode reaparecer'
    Assert-True ($organizeText -match 'Text="\{\}\{AAAA\} - \{MES_NUM\}') 'o modelo inicial deve manter o escape XAML e exibir a variável de ano corretamente'

    Write-Output ("ORGANIZER STRESS OK: {0} tracks, {1:N2}s no plano, {2} cópias verificadas" -f $TrackCount,$timer.Elapsed.TotalSeconds,$result.Success)
} finally {
    Remove-Item Env:ODT_DATA_ROOT -ErrorAction SilentlyContinue
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
