#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$app = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("ODT-Test-" + [guid]::NewGuid().ToString('N'))

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw "FALHOU: $Message" } }

try {
    $env:ODT_DATA_ROOT = Join-Path $testRoot 'Dados'
    $source = Join-Path $testRoot 'Pesquisa\Bandcamp\UKG'
    $destination = Join-Path $testRoot 'Saida'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $source 'Track A.mp3'), [byte[]](1,2,3,4))
    [IO.File]::WriteAllText((Join-Path $source 'ignorar.txt'), 'texto')
    $excludedFolder=Join-Path $testRoot 'Pesquisa\Samples'; [IO.Directory]::CreateDirectory($excludedFolder)|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $excludedFolder 'sample.wav'), [byte[]](0,0,0,0))

    Import-Module (Join-Path $app 'Modules\Scanner.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Metadata.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Duplicates.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Organizer.psm1') -Force
    Import-Module (Join-Path $app 'Modules\History.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Enrichment.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Inbox.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Downloader.psm1') -Force
    Import-Module (Join-Path $app 'Modules\Rekordbox.psm1') -Force
    $settings = Get-Content -LiteralPath (Join-Path $app 'Config\settings.json') -Raw | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath (Join-Path $app $settings.Acquisition.DownloaderPath) -PathType Leaf) 'o motor interno de download deve acompanhar o ODT'
    $downloaderCode=Get-Content -LiteralPath (Join-Path $app 'Modules\Downloader.psm1') -Raw
    Assert-True ($downloaderCode.Contains('$arguments.Add((ConvertTo-ProcessArgument "${Quality}K"))') -and -not$downloaderCode.Contains("ConvertTo-ProcessArgument '--postprocessor-args'")) 'MP3 320 deve usar bitrate explícito, sem o modo VBR 0 conflitante'

    $tempoFile=Join-Path $testRoot 'Tempo 128 BPM.mp3';[IO.File]::WriteAllBytes($tempoFile,[byte[]](1,2,3,4))
    $tempoMetadata=Get-AudioMetadata -File (Get-Item -LiteralPath $tempoFile) -Settings $settings
    Assert-True ($tempoMetadata.Bpm -eq 128) 'o BPM deve aceitar fallback explícito no nome do arquivo'
    Remove-Item -LiteralPath $tempoFile -Force

    $mp3FrameFile=Join-Path $testRoot 'Perfil 128.mp3';$frameBytes=New-Object byte[] (417*4)
    for($frame=0;$frame -lt 4;$frame++){$offset=$frame*417;$frameBytes[$offset]=0xFF;$frameBytes[$offset+1]=0xFB;$frameBytes[$offset+2]=0x90;$frameBytes[$offset+3]=0}
    [IO.File]::WriteAllBytes($mp3FrameFile,$frameBytes);$profile=Get-Mp3BitrateProfile -File (Get-Item -LiteralPath $mp3FrameFile)
    Assert-True ($profile.Mode -eq 'CBR' -and $profile.Minimum -eq 128 -and $profile.Maximum -eq 128 -and $profile.Frames -gt 0 -and $profile.Map.Length -eq 32) 'o mapa de bitrate deve analisar frames MP3'
    Remove-Item -LiteralPath $mp3FrameFile -Force

    $emptyHealth = Get-LibraryHealth -Tracks @()
    Assert-True ($emptyHealth.Total -eq 0) 'os contadores devem aceitar uma pasta recém-selecionada ainda sem análise'

    $tracks = @(Get-AudioFiles -Source (Join-Path $testRoot 'Pesquisa') -Settings $settings)
    Assert-True ($tracks.Count -eq 1) 'o scanner deve encontrar um arquivo de áudio'
    Assert-True (-not ($tracks.FullName -match 'Samples')) 'pastas de exceção devem ser ignoradas'
    $allFiles = @(Get-AudioFiles -Source (Join-Path $testRoot 'Pesquisa') -Settings $settings -OnlyAudio:$false)
    Assert-True ($allFiles.Count -eq 2 -and @($allFiles | Where-Object Extension -eq '.txt').Count -eq 1) 'desmarcar Somente áudio deve incluir extensões permitidas que não sejam áudio'
    Assert-True (-not ($allFiles.FullName -match 'Samples')) 'as pastas de exceção devem continuar ignoradas fora do modo Somente áudio'
    $hashedTracks = @(Get-AudioFiles -Source (Join-Path $testRoot 'Pesquisa') -Settings $settings -IncludeHash)
    Assert-True ($hashedTracks.Count -eq 1 -and $hashedTracks[0].Hash.Length -eq 64) 'o scanner deve calcular SHA-256 quando solicitado'
    $tracks[0].Genre = 'UKG'
    $tracks[0].MissingGenre = $false
    $tracks[0].Bpm = 132

    $tracks[0].Artist = 'Artista_Teste'
    $tracks[0].Title = 'Faixa Teste [320kbps]'
    $tracks[0].Album = 'Album Teste'; $tracks[0].Year = '2025'; $tracks[0].Key = '8A'; $tracks[0].Bitrate = 320; $tracks[0].SampleRate = 44100
    $plan = New-OrganizationPlan -Tracks $tracks -Source (Join-Path $testRoot 'Pesquisa') -Destination $destination -Template '{AAAA}\{GENERO}\{BPM_RANGE}' -TreeMode PreserveTree -Action Copy -Conflict Rename -RenameFiles -SeparateMissing -CreateReport -CreateRestore -Settings $settings
    Assert-True ($plan.Items.Count -eq 1) 'o plano deve conter um item'
    Write-Output ("Destino calculado: " + $plan.Items[0].Destination)
    Assert-True ($plan.Items[0].Destination -match 'UK Garage') 'o gênero deve ser normalizado'
    Assert-True ($plan.Items[0].Destination -match '130-134 BPM') 'a faixa de BPM deve ser resolvida'
    Assert-True ($plan.Items[0].Destination.Contains('Bandcamp\UKG')) 'a árvore original deve ser preservada'
    Assert-True ($plan.Items[0].Destination -match 'Artista Teste - Faixa Teste\.mp3$') 'o nome do arquivo deve ser normalizado'

    $flatPlan = New-OrganizationPlan -Tracks $tracks -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'SaidaPlana') -Template '{AAAA}\{GENERO}' -TreeMode FlattenSource -Action Copy -Conflict Rename -Settings $settings
    Assert-True (-not $flatPlan.Items[0].Destination.Contains('Bandcamp\UKG')) 'alterar estrutura deve ignorar as subpastas existentes'

    $allVariables = '{AAAA}\{AA}\{MES}\{MES_NUM}\{DIA}\{GENERO}\{ARTISTA}\{ALBUM}\{ANO}\{BPM}\{BPM_RANGE}\{KEY}\{EXTENSAO}\{FORMATO}\{PASTA_ORIGEM}\{PASTA_PAI}\{PASTA_RAIZ}\{NOME_ARQUIVO}\{TITULO}\{BITRATE}\{SAMPLE_RATE}'
    $variablesPlan = New-OrganizationPlan -Tracks $tracks -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Variaveis') -Template $allVariables -TreeMode FlattenSource -Action Copy -Conflict Rename -Settings $settings
    Assert-True ($variablesPlan.Items[0].Destination -notmatch '\{[^}]+\}') 'todas as variáveis previstas devem ser resolvidas'
    Assert-True ($variablesPlan.Items[0].Destination -match 'Bandcamp') 'a variável PASTA_RAIZ deve ser resolvida'
    $unknownRejected = $false
    try { New-OrganizationPlan -Tracks $tracks -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Erro') -Template '{VARIAVEL_INEXISTENTE}' -TreeMode FlattenSource -Settings $settings | Out-Null } catch { $unknownRejected = $true }
    Assert-True $unknownRejected 'variáveis desconhecidas não podem gerar pastas silenciosamente'

    $onlineTrack=$tracks[0].PSObject.Copy();$onlineTrack.Name='Disclosure - Latch.mp3';$onlineTrack.Title='Disclosure - Latch';$onlineTrack.Artist='';$onlineTrack.Album='';$onlineTrack.Genre='';$onlineTrack.Year='';$onlineTrack.MissingTitle=$true;$onlineTrack.MissingGenre=$true
    $parts=Get-OnlineSearchParts -Track $onlineTrack
    Assert-True ($parts.Artist -eq 'Disclosure' -and $parts.Title -eq 'Latch') 'a busca online deve extrair artista e título do nome do arquivo'
    $suggestion=[pscustomobject]@{Found=$true;Title='Latch';Artist='Disclosure';Album='Settle';Genre='UK Garage';Year='2013';ISRC='TEST123';Confidence=99;Source='Teste';MusicBrainzId='id';Error=''}
    Assert-True (Set-TrackSuggestion -Track $onlineTrack -Suggestion $suggestion -FillOnlyEmpty) 'uma sugestão aprovada deve ser aplicada'
    Assert-True ($onlineTrack.Artist -eq 'Disclosure' -and $onlineTrack.Genre -eq 'UK Garage' -and -not $onlineTrack.MissingGenre) 'a sugestão deve atualizar metadata e indicadores ausentes'
    $reviewResults=New-Object Collections.Generic.List[object];$reviewResults.Add([pscustomobject]@{Track=$onlineTrack;Suggestion=$suggestion})
    $reviewArray=$reviewResults.ToArray()
    Assert-True ($reviewArray.Count -eq 1 -and $reviewArray[0].Suggestion.Title -eq 'Latch') 'resultados online devem ser convertidos explicitamente para array no PowerShell 5.1'

    # Gravação de tags e undo em um WAV real e válido.
    function New-SilentTestWav([string]$Path){
        $sampleRate=8000;$channels=1;$bits=16;$dataLength=$sampleRate*2
        $stream=[IO.File]::Create($Path);$writer=New-Object IO.BinaryWriter($stream)
        try{
            $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([int](36+$dataLength));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
            $writer.Write([Text.Encoding]::ASCII.GetBytes('fmt '));$writer.Write([int]16);$writer.Write([int16]1);$writer.Write([int16]$channels);$writer.Write([int]$sampleRate)
            $writer.Write([int]($sampleRate*$channels*$bits/8));$writer.Write([int16]($channels*$bits/8));$writer.Write([int16]$bits)
            $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([int]$dataLength);$writer.Write((New-Object byte[] $dataLength))
        }finally{$writer.Dispose();$stream.Dispose()}
    }
    $tagWav=Join-Path $testRoot 'metadata.wav';$tagWav2=Join-Path $testRoot 'metadata-2.wav';New-SilentTestWav $tagWav;New-SilentTestWav $tagWav2
    $tagTrack=[pscustomobject]@{FullName=$tagWav;Title='Teste de Tag';Artist='MANELZ0RD';Album='CRIVO';Genre='House';Year='2026';Bpm=128;Key='8A'}
    $tagTrack2=[pscustomobject]@{FullName=$tagWav2;Title='Outra Tag';Artist='MANELZ0RD';Album='CRIVO';Genre='Tech House';Year='2026';Bpm=126;Key='9A'}
    $tagWrite=Write-ApprovedMetadata -Tracks @($tagTrack);$tagWrite2=Write-ApprovedMetadata -Tracks @($tagTrack2)
    Assert-True ($tagWrite.Updated -eq 1 -and $tagWrite.Errors -eq 0) 'a gravação aprovada deve escrever tags numa track compatível'
    Assert-True ($tagWrite.Operation.Id -ne $tagWrite2.Operation.Id) 'duas gravações rápidas de metadata devem ter IDs de histórico únicos'
    $tagged=[TagLib.File]::Create($tagWav);try{Assert-True ($tagged.Tag.Title -eq 'Teste de Tag' -and $tagged.Tag.BeatsPerMinute -eq 128) 'as tags gravadas devem ser legíveis no arquivo'}finally{$tagged.Dispose()}
    $tagUndo=@(Undo-Operation -Operation $tagWrite.Operation)
    Assert-True ($tagUndo.Count -eq 1 -and $tagUndo[0].Status -eq 'Metadata restaurada') 'o histórico deve desfazer a gravação de tags'
    $restored=[TagLib.File]::Create($tagWav);try{Assert-True ([string]::IsNullOrEmpty($restored.Tag.Title) -and $restored.Tag.BeatsPerMinute -eq 0) 'o undo deve restaurar os valores originais das tags'}finally{$restored.Dispose()}

    $aliasTrack=$tracks[0].PSObject.Copy();$aliasTrack.Genre='2-Step Garage';$aliasTrack.MissingGenre=$false
    $aliasPlan=New-OrganizationPlan -Tracks @($aliasTrack) -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Alias') -Template '{GENERO}' -TreeMode FlattenSource -Settings $settings
    Assert-True ($aliasPlan.Items[0].Destination -match 'UK Garage') 'aliases de gênero devem ser normalizados'

    $missingTrack=$tracks[0].PSObject.Copy();$missingTrack.Genre='_PENDENTE';$missingTrack.MissingGenre=$true;$missingTrack.Bpm=0
    $separatePlan=New-OrganizationPlan -Tracks @($missingTrack) -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Ausentes') -Template '{GENERO}\{BPM_RANGE}' -TreeMode FlattenSource -MissingMetadataPolicy Separate -Settings $settings
    Assert-True ($separatePlan.Items[0].Destination -match '_SEM GENERO') 'metadata ausente deve poder ser separada'
    Assert-True ($separatePlan.Items[0].Destination -match '_SEM BPM') 'BPM ausente deve usar a pasta prevista'
    $rootPlan=New-OrganizationPlan -Tracks @($missingTrack) -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Raiz') -Template '{GENERO}\{BPM_RANGE}' -TreeMode FlattenSource -MissingMetadataPolicy Root -Settings $settings
    Assert-True ($rootPlan.Items[0].Destination -notmatch '_(SEM|PENDENTE)') 'metadata ausente deve poder permanecer na raiz organizada'
    $skipPlan=New-OrganizationPlan -Tracks @($missingTrack) -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Pular') -Template '{GENERO}\{BPM_RANGE}' -TreeMode FlattenSource -MissingMetadataPolicy Skip -Settings $settings
    Assert-True ($skipPlan.Items[0].Status -eq 'Skip') 'metadata obrigatória ausente deve poder ser ignorada'

    $duplicateTrack=$tracks[0].PSObject.Copy();$duplicateTrack.FullName=Join-Path $source 'outra.mp3';$duplicateTrack.Name=$tracks[0].Name
    Assert-True (@(Find-AudioDuplicates -Tracks @($tracks[0],$duplicateTrack) -Level NameSize).Count -eq 2) 'duplicatas por nome e tamanho devem ser detectadas'
    $duplicateTrack.Hash='ABC';$tracks[0].Hash='ABC'
    Assert-True (@(Find-AudioDuplicates -Tracks @($tracks[0],$duplicateTrack) -Level Hash).Count -eq 2) 'duplicatas por hash devem ser detectadas'
    $collisionPlan=New-OrganizationPlan -Tracks @($tracks[0],$duplicateTrack) -Source (Join-Path $testRoot 'Pesquisa') -Destination (Join-Path $testRoot 'Colisoes') -Template '{GENERO}' -TreeMode FlattenSource -Conflict Rename -Settings $settings
    Assert-True ($collisionPlan.Items[0].Destination -ne $collisionPlan.Items[1].Destination) 'colisões internas devem gerar nomes diferentes'

    $inboxRoot=Join-Path $testRoot 'Inbox'; Initialize-ODTInbox -Root $inboxRoot | Out-Null
    $manifestPath=New-DownloadManifest -Root $inboxRoot -Url 'https://example.invalid/track' -Quality '320 kbps'
    $manifestPath2=New-DownloadManifest -Root $inboxRoot -Url 'https://example.invalid/track-2' -Quality '320 kbps'
    Assert-True ($manifestPath -ne $manifestPath2) 'manifestos criados no mesmo milissegundo devem ter IDs únicos'
    Remove-Item -LiteralPath $manifestPath2 -Force
    $pendingAudio=Join-Path (Join-Path $inboxRoot 'Pending') 'download.mp3'; [IO.File]::WriteAllBytes($pendingAudio,[byte[]](1,2,3))
    $inboxItems=@(Get-InboxItems -Root $inboxRoot)
    Assert-True ($inboxItems.Count -eq 1 -and $inboxItems[0].AudioFiles.Count -eq 1) 'a Inbox deve listar manifestos e áudios pendentes'
    $processedManifest=Complete-InboxManifest -Manifest $inboxItems[0] -Bucket Processed -Message 'Organizado'
    $processedData=Get-Content -LiteralPath $processedManifest -Raw | ConvertFrom-Json
    Assert-True ($processedData.Status -eq 'Processed' -and $processedData.Error -eq 'Organizado') 'a conclusão da Inbox deve persistir o status atualizado'
    Assert-True (-not (Test-Path -LiteralPath $manifestPath) -and @(Get-InboxItems -Root $inboxRoot).Count -eq 0) 'um manifesto concluído não pode continuar pendente'
    $rbTrack=[pscustomobject]@{FullName=$pendingAudio;Name='download.mp3';Title='Download';Artist='Artist';Album='Album';Genre='House';Year='2026';Bpm=124;Key='8A'}
    $rbPath=Join-Path $testRoot 'ODT-Rekordbox.xml'; Export-RekordboxXml -Tracks @($rbTrack) -Path $rbPath | Out-Null
    Assert-True (Test-Path -LiteralPath $rbPath) 'a exportação Rekordbox deve criar um XML novo'
    $rbTarget=[pscustomobject]@{FullName=$pendingAudio;Name='download.mp3';Title='';Artist='';Album='';Genre='';Year='';Bpm='';Key=''}
    $rbResult=Import-RekordboxXmlMetadata -Path $rbPath -Tracks @($rbTarget)
    Assert-True ($rbResult.Matched -gt 0 -and $rbTarget.Genre -eq 'House') 'a importação Rekordbox deve preencher metadata por caminho'
    $rbLibrary=Get-RekordboxXmlLibrary -Path $rbPath;$rbAudit=Get-RekordboxAudit -Library $rbLibrary -Settings $settings -LocalTracks @($rbTarget)
    Assert-True ($rbLibrary.Tracks.Count -eq 1 -and $rbLibrary.Playlists.Count -eq 1) 'a integração deve ler coleção e playlists do XML'
    Assert-True ($rbAudit.Total -eq 1 -and $rbAudit.MissingFiles -eq 0) 'a auditoria deve validar a presença dos arquivos'
    $localOnly=$rbTarget.PSObject.Copy();$localOnly.FullName=Join-Path $testRoot 'somente-no-computador.mp3';[IO.File]::WriteAllBytes($localOnly.FullName,[byte[]](1,2,3));$twoWayAudit=Get-RekordboxAudit -Library $rbLibrary -Settings $settings -LocalTracks @($rbTarget,$localOnly)
    Assert-True (@($twoWayAudit.Rows|Where-Object{$_.Issues -match 'fora da coleção'}).Count -eq 1) 'a auditoria deve mostrar arquivos que existem no computador e não no Rekordbox'
    $auditPath=Join-Path $testRoot 'auditoria.csv';Export-RekordboxAudit -Audit $rbAudit -Path $auditPath|Out-Null;Assert-True (Test-Path -LiteralPath $auditPath) 'a auditoria Rekordbox deve ser exportável'
    $usbRoot=Join-Path $testRoot 'USB DJ';$usbDb=Join-Path $usbRoot 'PIONEER\rekordbox\export.pdb';$usbAnlz=Join-Path $usbRoot 'PIONEER\USBANLZ\000\ANLZ0000.DAT';$usbAudio=Join-Path $usbRoot 'Contents\metadata.wav'
    foreach($folder in @((Split-Path -Parent $usbDb),(Split-Path -Parent $usbAnlz),(Split-Path -Parent $usbAudio))){[IO.Directory]::CreateDirectory($folder)|Out-Null};[IO.File]::WriteAllBytes($usbDb,[byte[]](1,2,3));[IO.File]::WriteAllBytes($usbAnlz,[byte[]](1,2,3));[IO.File]::Copy($tagWav,$usbAudio,$true)
    $usbAudit=Get-RekordboxUsbAudit -Root $usbRoot -Settings $settings
    Assert-True ($usbAudit.Total -eq 1 -and $usbAudit.StructureIssues -eq 0 -and $usbAudit.AnalysisFileCount -eq 1) 'a auditoria de pendrive deve validar áudio, banco e arquivos de análise'
    $m3uPath=Join-Path $testRoot 'playlist.m3u8';Export-RekordboxPlaylistM3U8 -Library $rbLibrary -PlaylistPath 'ROOT / CRIVO DJ — Organizado' -Path $m3uPath|Out-Null;Assert-True ((Get-Content -LiteralPath $m3uPath -Raw) -match 'download.mp3') 'uma playlist Rekordbox deve ser exportável em M3U8'

    $dryRunPath=Join-Path $testRoot 'simulacao.json'; Export-OrganizationPlan -Plan $plan -Path $dryRunPath | Out-Null
    Assert-True (Test-Path -LiteralPath $dryRunPath) 'o dry-run deve ser exportável em JSON'
    Assert-True ((Get-Content $dryRunPath -Raw) -match 'Origem') 'o dry-run deve incluir origem, destino e metadata'

    $result = Invoke-OrganizationPlan -Plan $plan
    Assert-True (Test-Path -LiteralPath $plan.Items[0].Destination) 'o arquivo deve ser copiado'
    Assert-True ($result.Success -eq 1) 'a operação deve terminar sem erro'
    Assert-True (Test-Path -LiteralPath $result.HistoryPath) 'o ponto de restauração deve ser criado'
    Assert-True (Test-Path -LiteralPath $result.ReportPath) 'o relatório CSV deve ser criado'
    Assert-True ($result.Operation.Counts.Total -eq 1) 'o histórico deve registrar contagens da execução'

    $undo = @(Undo-Operation -Operation $result.Operation)
    Assert-True (-not (Test-Path -LiteralPath $plan.Items[0].Destination)) 'o desfazer deve remover a cópia'
    Assert-True ($undo.Count -eq 1) 'o desfazer deve relatar um item'

    # Conflitos, substituição protegida, movimentação e undo defensivo.
    $replaceSource=Join-Path $testRoot 'ReplaceSource';[IO.Directory]::CreateDirectory($replaceSource)|Out-Null
    $replaceFile=Join-Path $replaceSource 'replace.mp3';[IO.File]::WriteAllBytes($replaceFile,[byte[]](9,8,7,6))
    $replaceTrack=$tracks[0].PSObject.Copy();$replaceTrack.FullName=$replaceFile;$replaceTrack.Directory=$replaceSource;$replaceTrack.Name='replace.mp3';$replaceTrack.OutputName='replace.mp3';$replaceTrack.Selected=$true
    $replacePlan=New-OrganizationPlan -Tracks @($replaceTrack) -Source $replaceSource -Destination (Join-Path $testRoot 'ReplaceDest') -Template '{GENERO}' -TreeMode FlattenSource -Action Copy -Conflict Replace -CreateRestore -CreateReport -Settings $settings
    [IO.Directory]::CreateDirectory((Split-Path -Parent $replacePlan.Items[0].Destination))|Out-Null
    [IO.File]::WriteAllBytes($replacePlan.Items[0].Destination,[byte[]](1,1,1))
    $replaceResult=Invoke-OrganizationPlan -Plan $replacePlan
    Assert-True (([IO.File]::ReadAllBytes($replacePlan.Items[0].Destination) -join ',') -eq '9,8,7,6') 'Substituir deve gravar a nova track'
    Assert-True ([bool]$replaceResult.Operation.Items[0].BackupPath -and (Test-Path -LiteralPath $replaceResult.Operation.Items[0].BackupPath)) 'Substituir com restauração deve preservar o arquivo anterior'
    $replaceUndo=@(Undo-Operation -Operation $replaceResult.Operation)
    Assert-True (([IO.File]::ReadAllBytes($replacePlan.Items[0].Destination) -join ',') -eq '1,1,1') 'o undo de Substituir deve restaurar o arquivo anterior'
    Assert-True ($replaceUndo[0].Status -match 'restaurado') 'o undo deve relatar a restauração da substituição'

    $moveSource=Join-Path $testRoot 'MoveSource';[IO.Directory]::CreateDirectory($moveSource)|Out-Null
    $moveFile=Join-Path $moveSource 'move.mp3';[IO.File]::WriteAllBytes($moveFile,[byte[]](4,5,6))
    $moveTrack=$tracks[0].PSObject.Copy();$moveTrack.FullName=$moveFile;$moveTrack.Directory=$moveSource;$moveTrack.Name='move.mp3';$moveTrack.OutputName='move.mp3';$moveTrack.Selected=$true
    $movePlan=New-OrganizationPlan -Tracks @($moveTrack) -Source $moveSource -Destination (Join-Path $testRoot 'MoveDest') -Template '{GENERO}' -TreeMode FlattenSource -Action Move -Conflict Rename -CreateRestore -Settings $settings
    $moveResult=Invoke-OrganizationPlan -Plan $movePlan
    Assert-True (-not(Test-Path -LiteralPath $moveFile) -and (Test-Path -LiteralPath $movePlan.Items[0].Destination)) 'Mover deve retirar a track da origem'
    [void]@(Undo-Operation -Operation $moveResult.Operation)
    Assert-True ((Test-Path -LiteralPath $moveFile) -and -not(Test-Path -LiteralPath $movePlan.Items[0].Destination)) 'o undo de Mover deve devolver a track à origem'

    $guardPlan=New-OrganizationPlan -Tracks @($replaceTrack) -Source $replaceSource -Destination (Join-Path $testRoot 'GuardDest') -Template '{GENERO}' -TreeMode FlattenSource -Action Copy -Conflict Rename -CreateRestore -Settings $settings
    $guardResult=Invoke-OrganizationPlan -Plan $guardPlan
    [IO.File]::WriteAllBytes($guardPlan.Items[0].Destination,[byte[]](0,0,0,0))
    $guardUndo=@(Undo-Operation -Operation $guardResult.Operation)
    Assert-True ($guardUndo[0].Status -eq 'Conflito' -and (Test-Path -LiteralPath $guardPlan.Items[0].Destination)) 'o undo deve preservar um destino modificado depois da organização'

    $renamePlan=New-OrganizationPlan -Tracks @($replaceTrack) -Source $replaceSource -Destination (Join-Path $testRoot 'RenameDest') -Template '{GENERO}' -TreeMode FlattenSource -Action Copy -Conflict Rename -CreateReport -Settings $settings
    [IO.Directory]::CreateDirectory((Split-Path -Parent $renamePlan.Items[0].Destination))|Out-Null
    [IO.File]::WriteAllBytes($renamePlan.Items[0].Destination,[byte[]](3,3,3))
    $renameResult=Invoke-OrganizationPlan -Plan $renamePlan
    $actualRename=[string]$renameResult.Operation.Items[0].Destination
    Assert-True ($actualRename -match ' \(2\)\.mp3$' -and (Test-Path -LiteralPath $actualRename)) 'Manter os dois deve criar um nome (2) no conflito real'
    $renameReport=Import-Csv -LiteralPath $renameResult.ReportPath
    Assert-True ($renameReport.Destino -eq $actualRename) 'o relatório deve registrar o destino efetivamente utilizado'

    # O progresso não pode anunciar sucesso se o motor terminou sem gerar arquivo.
    $fakeProcess=[pscustomobject]@{HasExited=$true;ExitCode=0};$fakeProcess|Add-Member ScriptMethod Refresh {} -Force
    $emptyOut=Join-Path $testRoot 'empty.out.log';$emptyErr=Join-Path $testRoot 'empty.err.log';[IO.File]::WriteAllText($emptyOut,'');[IO.File]::WriteAllText($emptyErr,'')
    $fakeDownload=[pscustomobject]@{Title='Faixa impossível';Duration='';Thumbnail='';LockMetadata=$false;StdOutPath=$emptyOut;StdErrPath=$emptyErr;ProgressValue=0;Progress='0%';Detail='';Process=$fakeProcess;FinishedAt=$null;OutputFolder=(Join-Path $testRoot 'FakeDownload');FinalPath='';Status='Baixando'}
    [IO.Directory]::CreateDirectory($fakeDownload.OutputFolder)|Out-Null
    $fakeDownload=Get-ODTDownloadProgress -Download $fakeDownload
    Assert-True ($fakeDownload.Status -eq 'Falhou') 'exit code zero sem arquivo final deve ser tratado como falha'
    $downloadedFile=Join-Path $fakeDownload.OutputFolder 'ok.mp3';[IO.File]::WriteAllBytes($downloadedFile,[byte[]](7,7,7))
    [IO.File]::WriteAllText($emptyOut,"ODT_FILE|$downloadedFile")
    $fakeDownload.Status='Baixando';$fakeDownload=Get-ODTDownloadProgress -Download $fakeDownload
    Assert-True ($fakeDownload.Status -eq 'Concluido' -and $fakeDownload.ProgressValue -eq 100 -and $fakeDownload.FinalPath -eq $downloadedFile) 'um arquivo final confirmado deve concluir o download em 100%'

    # Link de track individual deve resultar em uma única linha, não numa playlist fantasma.
    $resolverOut=Join-Path $testRoot 'resolver.out.log';$resolverErr=Join-Path $testRoot 'resolver.err.log'
    [IO.File]::WriteAllText($resolverOut,'{"title":"Faixa única","uploader":"Artista","webpage_url":"https://example.invalid/faixa","duration_string":"3:21"}')
    [IO.File]::WriteAllText($resolverErr,'')
    $fakeResolverProcess=[pscustomobject]@{HasExited=$true;ExitCode=0};$fakeResolverProcess|Add-Member ScriptMethod Refresh {} -Force;$fakeResolverProcess|Add-Member ScriptMethod WaitForExit {} -Force
    $fakeResolver=[pscustomobject]@{Kind='PlaylistResolver';Title='Lendo';Source='example.invalid';Url='https://example.invalid/faixa';Quality='MP3 320 kbps';QualityCode='320';Status='Analisando';Progress='0%';ProgressValue=0;Detail='';Process=$fakeResolverProcess;StdOutPath=$resolverOut;StdErrPath=$resolverErr;OutputFolder=$fakeDownload.OutputFolder;StartedAt=Get-Date;TimeoutSeconds=30;FinishedAt=$null}
    Assert-True ((Get-Command Start-ODTPlaylistResolver).Parameters.ContainsKey('SingleTrack')) 'o resolvedor deve permitir separar track única de playlist'
    $resolvedSingle=@(Complete-ODTPlaylistResolver -Resolver $fakeResolver)
    Assert-True ($resolvedSingle.Count -eq 1 -and $resolvedSingle[0].Title -eq 'Faixa única' -and $fakeResolver.Status -eq 'Expandida') 'um link de track deve gerar exatamente uma linha pronta'
    Assert-True ($resolvedSingle[0].Source -eq 'example.invalid') 'a fonte original deve permanecer estática depois da resolução'

    [IO.File]::WriteAllText($resolverOut,'{"title":"Playlist","entries":[{"title":"Track 1","uploader":"DJ 1","webpage_url":"https://example.invalid/1","thumbnail":"https://example.invalid/1.jpg"},{"title":"Track 2","webpage_url":"https://example.invalid/2","thumbnails":[{"url":"https://example.invalid/2.jpg"}]}]}')
    $fakeResolver.Status='Analisando';$fakeResolver.StartedAt=Get-Date;$fakeResolver.FinishedAt=$null
    $resolvedPlaylist=@(Complete-ODTPlaylistResolver -Resolver $fakeResolver)
    Assert-True ($resolvedPlaylist.Count -eq 2 -and $resolvedPlaylist[0].Thumbnail -match '1.jpg' -and $resolvedPlaylist[1].Thumbnail -match '2.jpg') 'uma playlist deve ser separada em tracks com capas individuais'

    [IO.File]::WriteAllText($resolverOut,'null');[IO.File]::WriteAllText($resolverErr,'ERROR: a fonte respondeu sem metadata')
    $fakeResolver.Status='Analisando';$fakeResolver.StartedAt=Get-Date;$fakeResolver.FinishedAt=$null
    [void]@(Complete-ODTPlaylistResolver -Resolver $fakeResolver)
    Assert-True ($fakeResolver.Status -eq 'Falhou' -and $fakeResolver.Detail -match 'metadata') 'JSON nulo deve virar falha da linha, sem interromper a fila inteira'
    $fallbackResolver=$fakeResolver.PSObject.Copy();$fallbackResolver.Url='https://soundcloud.com/dj/teste-da-track';$fallbackResolver.Status='Analisando';$fallbackResolver|Add-Member NoteProperty SingleTrack $true -Force
    $fallbackTracks=@(Complete-ODTPlaylistResolver -Resolver $fallbackResolver)
    Assert-True ($fallbackTracks.Count -eq 1 -and $fallbackTracks[0].Status -eq 'Pronto' -and $fallbackTracks[0].DownloadUrl -match '^ytsearch1:' -and $fallbackTracks[0].Source -eq 'example.invalid') 'uma track individual indisponível deve ser preparada para busca alternativa sem perder a fonte original'

    $spotifySave=Join-Path $testRoot 'spotify.spotdl';[IO.File]::WriteAllText($spotifySave,'[{"name":"Spotify Track","artists":["DJ Spotify"],"duration":180,"cover":"https://example.invalid/spotify.jpg","url":"https://open.spotify.com/track/test"}]')
    $spotifyResolver=[pscustomobject]@{Kind='SpotifyResolver';Title='Lendo';Source='Spotify';Url='https://open.spotify.com/track/test';Quality='MP3 320 kbps';QualityCode='320';Status='Analisando';Progress='0%';ProgressValue=0;Detail='';Process=$fakeResolverProcess;StdOutPath=$resolverOut;StdErrPath=$resolverErr;SaveFile=$spotifySave;OutputFolder=$fakeDownload.OutputFolder;StartedAt=Get-Date;TimeoutSeconds=30;FinishedAt=$null;Expanded=$false}
    [IO.File]::WriteAllText($resolverOut,'');[IO.File]::WriteAllText($resolverErr,'')
    $spotifyTracks=@(Complete-ODTSpotifyResolver -Resolver $spotifyResolver)
    Assert-True ($spotifyTracks.Count -eq 1 -and $spotifyTracks[0].Artist -eq 'DJ Spotify' -and $spotifyTracks[0].Thumbnail -match 'spotify.jpg') 'o Spotify deve aceitar artistas e capa mesmo com campos opcionais ausentes'

    [IO.File]::WriteAllText($resolverOut,'{"entries":[]}');$fakeResolver.Status='Analisando';$fakeResolver.StartedAt=Get-Date;$fakeResolver.FinishedAt=$null
    $resolvedEmpty=@(Complete-ODTPlaylistResolver -Resolver $fakeResolver)
    Assert-True ($resolvedEmpty.Count -eq 0 -and $fakeResolver.Status -eq 'Falhou') 'um resolvedor vazio deve encerrar como falha, sem deixar a fila presa'
    [IO.File]::WriteAllText($resolverOut,'falha da fonte');$fakeResolver.Status='Analisando';$fakeResolver.Progress='5%';$fakeResolver.ProgressValue=5;$fakeResolver.Process=[pscustomobject]@{HasExited=$true;ExitCode=1};$fakeResolver.Process|Add-Member ScriptMethod Refresh {} -Force;$fakeResolver.Process|Add-Member ScriptMethod WaitForExit {} -Force
    [void]@(Complete-ODTPlaylistResolver -Resolver $fakeResolver)
    Assert-True ($fakeResolver.Status -eq 'Falhou' -and $fakeResolver.ProgressValue -eq 0 -and [string]::IsNullOrEmpty($fakeResolver.Progress)) 'falha de metadata deve limpar o progresso intermediário'

    # Erros de playlists privadas ou removidas devem orientar a ação correta,
    # em vez de expor somente o texto bruto do yt-dlp.
    [IO.File]::WriteAllText($resolverOut,'');[IO.File]::WriteAllText($resolverErr,'ERROR: [soundcloud:set] emanuel-fraga-347305757/sets/privada: Unable to download JSON metadata: HTTP Error 404: Not Found')
    $privateResolver=$fakeResolver.PSObject.Copy();$privateResolver.Url='https://soundcloud.com/emanuel-fraga-347305757/sets/privada';$privateResolver.Status='Analisando';$privateResolver.Progress='10%';$privateResolver.ProgressValue=10;$privateResolver.Process=[pscustomobject]@{HasExited=$true;ExitCode=1};$privateResolver.Process|Add-Member ScriptMethod Refresh {} -Force;$privateResolver.Process|Add-Member ScriptMethod WaitForExit {} -Force
    [void]@(Complete-ODTPlaylistResolver -Resolver $privateResolver)
    Assert-True ($privateResolver.Status -eq 'Link privado' -and $privateResolver.Detail -match '(?i)Compartilhar.*Link de Compartilhamento privado|/s-') '404 de playlist privada do SoundCloud deve orientar o link secreto sem exibir falha genérica'

    $hungProcess=[pscustomobject]@{HasExited=$false;ExitCode=0;Killed=$false};$hungProcess|Add-Member ScriptMethod Refresh {} -Force;$hungProcess|Add-Member ScriptMethod Kill {$this.Killed=$true;$this.HasExited=$true} -Force;$hungProcess|Add-Member ScriptMethod WaitForExit {} -Force
    $hungResolver=[pscustomobject]@{Kind='PlaylistResolver';Title='Lendo';Source='example.invalid';Url='https://example.invalid/hung';Quality='MP3 320 kbps';QualityCode='320';Status='Analisando';Progress='20%';ProgressValue=20;Detail='';Process=$hungProcess;StdOutPath=$resolverOut;StdErrPath=$resolverErr;OutputFolder=$fakeDownload.OutputFolder;StartedAt=(Get-Date).AddSeconds(-10);TimeoutSeconds=1;FinishedAt=$null}
    [void]@(Complete-ODTPlaylistResolver -Resolver $hungResolver)
    Assert-True ($hungResolver.Status -eq 'Falhou' -and $hungProcess.Killed) 'um resolvedor travado deve ser encerrado por timeout e liberar a fila'

    # O executável usa Windows PowerShell 5.1. Um resolvedor ainda em execução
    # precisa devolver uma coleção vazia sem provocar PropertyNotFoundException.
    $waitingProcess=[pscustomobject]@{HasExited=$false;ExitCode=0};$waitingProcess|Add-Member ScriptMethod Refresh {} -Force
    $waitingResolver=[pscustomobject]@{Kind='PlaylistResolver';Title='Lendo';Source='soundcloud.com';Url='https://example.invalid/waiting';Quality='MP3 320 kbps';QualityCode='320';Status='Analisando';Progress='0%';ProgressValue=0;Detail='';Process=$waitingProcess;StdOutPath=$resolverOut;StdErrPath=$resolverErr;OutputFolder=$fakeDownload.OutputFolder;StartedAt=Get-Date;TimeoutSeconds=30;FinishedAt=$null}
    [object[]]$waitingResult=if($waitingResolver.Kind -eq 'SpotifyResolver'){@(Complete-ODTSpotifyResolver -Resolver $waitingResolver)}else{@(Complete-ODTPlaylistResolver -Resolver $waitingResolver)}
    Assert-True (@($waitingResult).Count -eq 0 -and $waitingResolver.Status -eq 'Analisando') 'um resolvedor ativo deve manter a fila rodando sem resultado prematuro'

    # Contrato visual: cada botão nomeado no XAML precisa estar ligado a um handler.
    [xml]$xaml=Get-Content -LiteralPath (Join-Path $app 'UI\MainWindow.xaml') -Raw
    $appCode=Get-Content -LiteralPath (Join-Path $app 'ODT.ps1') -Raw
    $downloadGrid=$xaml.SelectNodes('//*[local-name()="DataGrid"]')|Where-Object{$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') -eq 'DownloadQueueGrid'}|Select-Object -First 1
    $downloadHeaders=@($downloadGrid.SelectNodes('.//*[local-name()="DataGridTextColumn" or local-name()="DataGridTemplateColumn"]')|ForEach-Object{[string]$_.GetAttribute('Header')})
    Assert-True ($downloadHeaders -notcontains 'REKORDBOX') 'a fila de download não deve consultar nem exibir o Rekordbox'
    Assert-True ($appCode -notmatch 'Add-RekordboxKnowledgeToDownloadRequest -Request \$request') 'o timer de download não deve abrir a base do Rekordbox'
    $buttonNames=@($xaml.SelectNodes('//*[local-name()="Button"]')|ForEach-Object{$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')}|Where-Object{$_})
    $missingHandlers=@($buttonNames|Where-Object{$buttonName=$_;$appCode -notmatch ('\$'+[regex]::Escape($buttonName)+'\.Add_(Click|PreviewMouse|Drop)')})
    Assert-True ($buttonNames.Count -ge 30 -and $missingHandlers.Count -eq 0) 'todos os botões visíveis devem possuir um handler'

    Write-Output 'TODOS OS TESTES PASSARAM'
} finally {
    Remove-Item Env:ODT_DATA_ROOT -ErrorAction SilentlyContinue
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if (Test-Path -LiteralPath $testRoot) {
        1..4 | ForEach-Object {
            if (-not (Test-Path -LiteralPath $testRoot)) { return }
            Start-Sleep -Milliseconds 250
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
