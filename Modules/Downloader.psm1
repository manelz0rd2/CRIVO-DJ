Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
$script:SoundCloudClientId = ''

function ConvertTo-ProcessArgument {
    param([string]$Value)
    if($null -eq $Value){return '""'}
    return '"'+($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'
}

function Read-SharedUtf8Text {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $encoding=New-Object Text.UTF8Encoding($false)
        $reader=New-Object IO.StreamReader($stream,$encoding,$true)
        try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
    } finally {$stream.Dispose()}
}

function Get-ODTObjectProperty {
    param($InputObject,[Parameter(Mandatory)][string]$Name,$Default='')
    if($null -eq $InputObject){return $Default}
    $property=$InputObject.PSObject.Properties[$Name]
    if($null -eq $property -or $null -eq $property.Value){return $Default}
    return $property.Value
}

function Find-DownloadedTrackFile {
    param([Parameter(Mandatory)]$Download)
    if(-not(Test-Path -LiteralPath $Download.OutputFolder -PathType Container)){return $null}
    $identity=([string]$Download.Title).ToLowerInvariant() -replace '[^\p{L}\p{Nd}]',''
    if($identity.Length -lt 3 -or $Download.Title -eq 'Lendo dados da faixa...'){return $null}
    foreach($file in @(Get-ChildItem -LiteralPath $Download.OutputFolder -File -ErrorAction SilentlyContinue)){
        if($file.Extension.ToLowerInvariant() -notin @('.mp3','.wav','.flac','.aiff','.aif','.m4a','.aac','.ogg','.opus','.webm')){continue}
        $candidate=$file.BaseName.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]',''
        if($candidate.Contains($identity)){return $file}
    }
    return $null
}

function Get-DownloadFailureDetail {
    param([string]$Text,[int]$ExitCode)
    $lines=@($Text -split '[\r\n]+' | ForEach-Object {($_ -replace '\x1B\[[0-?]*[ -/]*[@-~]','').Trim()} | Where-Object {$_})
    if($Text -match '(?is)\[soundcloud(?::set)?\].*(?:HTTP\s*Error\s*404|404\s*Not\s*Found|not found)'){
        return 'O resolvedor do SoundCloud recebeu 404 ao buscar os dados. Isso pode ser link privado/expirado, playlist removida ou uma indisponibilidade/alteração temporária da API (também pode afetar playlists públicas). Para privada, copie o link secreto completo pela opção Compartilhar; para pública, confirme que abre no navegador e tente novamente mais tarde.'
    }
    if($Text -match '(?is)\[soundcloud(?::set)?\].*(?:HTTP\s*Error\s*(?:401|403)|Unauthorized|Forbidden|private)'){
        return 'O SoundCloud recusou o acesso a esta playlist. Verifique se ela é pública ou cole o link secreto completo da playlist privada.'
    }
    $errors=@($lines | Where-Object {$_ -match '(^ERROR:|\[error\]|error|failed|unable)'})
    if($errors.Count){return $errors[$errors.Count-1]}
    if($lines.Count){return $lines[$lines.Count-1]}
    return "O downloader foi encerrado sem mensagem (codigo $ExitCode). Tente novamente."
}

function ConvertTo-ODTPlaylistResolverUrl {
    param([Parameter(Mandatory)][string]$Url)
    # Links secretos do SoundCloud podem vir com ?secret_token=..., enquanto
    # o extrator de playlists espera o token como último segmento do caminho.
    try {
        $uri=[Uri]$Url
        if($uri.Host -match '(?i)(^|\.)soundcloud\.com$' -and $uri.AbsolutePath -match '(?i)/sets/[^/]+/?$' -and $uri.Query -match '(?i)(?:\?|&)secret_token=([^&]+)') {
            $token=[Uri]::UnescapeDataString($Matches[1])
            if($token){return (($uri.GetLeftPart([UriPartial]::Path).TrimEnd('/')+'/'+$token))}
        }
    } catch {}
    return $Url
}

function Get-ODTSoundCloudBrowser {
    # A playlist personalizada só existe dentro da sessão do SoundCloud.
    # Preferimos o navegador padrão mais comum no Windows, sem usar cookies
    # para links públicos ou para qualquer outro domínio.
    if(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')){return 'edge'}
    if(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')){return 'chrome'}
    if(Test-Path -LiteralPath (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')){return 'firefox'}
    return ''
}

function Get-ODTSoundCloudClientId {
    if($script:SoundCloudClientId){return $script:SoundCloudClientId}
    try {
        $home=(Invoke-WebRequest -UseBasicParsing -Uri 'https://soundcloud.com/' -TimeoutSec 12).Content
        $scripts=@([regex]::Matches($home,'<script[^>]+src="([^"]+)"')|ForEach-Object{$_.Groups[1].Value})
        [array]::Reverse($scripts)
        foreach($asset in $scripts){
            try {
                $javascript=(Invoke-WebRequest -UseBasicParsing -Uri $asset -TimeoutSec 12).Content
                $match=[regex]::Match($javascript,'client_id\s*:\s*"([0-9a-zA-Z]{32})"')
                if($match.Success){$script:SoundCloudClientId=$match.Groups[1].Value;return $script:SoundCloudClientId}
            } catch {}
        }
    } catch {}
    return ''
}

function Get-ODTSoundCloudTrackMetadata {
    param([string[]]$Ids)
    $result=@{};$wanted=@($Ids|Where-Object{$_}|Select-Object -Unique)
    if(-not$wanted.Count){return $result}
    $clientId=Get-ODTSoundCloudClientId;if(-not$clientId){return $result}
    for($offset=0;$offset -lt $wanted.Count;$offset+=50){
        $last=[Math]::Min($offset+49,$wanted.Count-1);$batch=@($wanted[$offset..$last])
        try {
            $url='https://api-v2.soundcloud.com/tracks?ids='+($batch -join ',')+'&client_id='+$clientId
            $response=Invoke-RestMethod -Uri $url -Headers @{'User-Agent'='Mozilla/5.0';Accept='application/json'} -TimeoutSec 20
            foreach($track in $response){
                if($track.id){$result[[string]$track.id]=$track}
            }
        } catch {}
    }
    return $result
}

function Start-ODTDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$EnginePath,
        [string]$FFmpegPath='',
        [ValidateSet('Original','128','192','256','320')][string]$Quality='320',
        [string]$DisplayUrl='',
        [string]$InitialTitle='',
        [string]$InitialSource='',
        [string]$InitialDuration='',
        [string]$Provider='',
        [string]$InitialThumbnail=''
    )
    if($Url -notmatch '^(https?://|ytsearch\d*:)' ){throw 'O link ou consulta de busca nao e valido.'}
    if(-not(Test-Path -LiteralPath $EnginePath -PathType Leaf)){throw "Motor de download nao encontrado: $EnginePath"}
    $pending=$OutputRoot;[IO.Directory]::CreateDirectory($pending)|Out-Null
    $logRoot=Join-Path (Get-AppDataRoot) 'DownloadLogs';[IO.Directory]::CreateDirectory($logRoot)|Out-Null;$id=Get-Date -Format 'yyyyMMdd-HHmmssfff';$stdout=Join-Path $logRoot "$id.out.log";$stderr=Join-Path $logRoot "$id.err.log"
    $arguments=New-Object Collections.Generic.List[string]
    $outputTemplate='%(uploader)s - %(title)s.%(ext)s'
    if($InitialTitle -and $InitialSource){$outputTemplate="$InitialSource - $InitialTitle.%(ext)s"}
    foreach($value in @('--newline','--progress','--no-color','--windows-filenames','--no-playlist','--embed-metadata','--embed-thumbnail','--convert-thumbnails','jpg','--print','before_dl:ODT_META|%(title)s|%(uploader)s|%(duration_string)s|%(thumbnail)s','--print','after_move:ODT_FILE|%(filepath)s','-P',$pending,'-o',$outputTemplate)){$arguments.Add((ConvertTo-ProcessArgument $value))}
    if($FFmpegPath){$ffmpeg=if(Test-Path -LiteralPath $FFmpegPath -PathType Leaf){Split-Path -Parent $FFmpegPath}else{$FFmpegPath};$arguments.Add((ConvertTo-ProcessArgument '--ffmpeg-location'));$arguments.Add((ConvertTo-ProcessArgument $ffmpeg))}
    # O yt-dlp interpreta 0 como VBR de alta qualidade (normalmente ~245-260 kbps).
    # Um valor explícito como 320K solicita bitrate constante e mantém o rótulo da UI fiel ao arquivo gerado.
    if($Quality -eq 'Original'){$arguments.Add((ConvertTo-ProcessArgument '-f'));$arguments.Add((ConvertTo-ProcessArgument 'bestaudio/best'))}else{$arguments.Add((ConvertTo-ProcessArgument '-x'));$arguments.Add((ConvertTo-ProcessArgument '--audio-format'));$arguments.Add((ConvertTo-ProcessArgument 'mp3'));$arguments.Add((ConvertTo-ProcessArgument '--audio-quality'));$arguments.Add((ConvertTo-ProcessArgument "${Quality}K"))}
    $arguments.Add((ConvertTo-ProcessArgument $Url))
    $process=Start-Process -FilePath $EnginePath -ArgumentList ($arguments -join ' ') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $hostName=try{([Uri]$Url).Host}catch{'Busca externa'};$format=if($Quality -eq 'Original'){'Audio original'}else{"MP3 ${Quality} kbps"}
    $title=if($InitialTitle){$InitialTitle}else{'Lendo dados da faixa...'};$source=if($Provider){$Provider}elseif($InitialSource){$InitialSource}else{$hostName};$shownUrl=if($DisplayUrl){$DisplayUrl}else{$Url}
    return [pscustomobject]@{Kind='Download';Id=$id;IsSelected=$true;Title=$title;Source=$source;Duration=$InitialDuration;Thumbnail=$InitialThumbnail;Url=$shownUrl;DownloadUrl=$Url;LockMetadata=[bool]$InitialTitle;Quality=$format;QualityCode=$Quality;Status='Baixando';Progress='0%';ProgressValue=0;Detail='Conectando...';Process=$process;StdOutPath=$stdout;StdErrPath=$stderr;StartedAt=Get-Date;FinishedAt=$null;OutputFolder=$pending;FinalPath=''}
}

function Start-ODTSpotifyResolver {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$EnginePath,
        [string]$FFmpegPath='',
        [ValidateSet('Original','128','192','256','320')][string]$Quality='320'
    )
    if($Url -notmatch '^https?://(open\.)?spotify\.com/(playlist|album|track)/'){throw 'Use um link de faixa, album ou playlist do Spotify.'}
    if(-not(Test-Path -LiteralPath $EnginePath -PathType Leaf)){throw "Resolvedor Spotify nao encontrado: $EnginePath"}
    [IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
    $logRoot=Join-Path (Get-AppDataRoot) 'DownloadLogs';[IO.Directory]::CreateDirectory($logRoot)|Out-Null
    $id=Get-Date -Format 'yyyyMMdd-HHmmssfff';$stdout=Join-Path $logRoot "$id.spotify.out.log";$stderr=Join-Path $logRoot "$id.spotify.err.log";$saveFile=Join-Path $logRoot "$id.spotdl"
    $arguments=New-Object Collections.Generic.List[string]
    foreach($value in @('save',$Url,'--save-file',$saveFile,'--headless','--threads','8')){$arguments.Add((ConvertTo-ProcessArgument $value))}
    if($FFmpegPath){$arguments.Add((ConvertTo-ProcessArgument '--ffmpeg'));$arguments.Add((ConvertTo-ProcessArgument $FFmpegPath))}
    $process=Start-Process -FilePath $EnginePath -ArgumentList ($arguments -join ' ') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return [pscustomobject]@{Kind='SpotifyResolver';Id=$id;IsSelected=$true;Title='Lendo playlist do Spotify...';Source='Spotify';Duration='';Thumbnail='';Url=$Url;Quality=$(if($Quality -eq 'Original'){'Audio original'}else{"MP3 ${Quality} kbps"});QualityCode=$Quality;Status='Analisando';Progress='0%';ProgressValue=0;Detail='Separando a playlist em tracks';Process=$process;StdOutPath=$stdout;StdErrPath=$stderr;SaveFile=$saveFile;OutputFolder=$OutputRoot;StartedAt=Get-Date;TimeoutSeconds=300;FinishedAt=$null;Expanded=$false}
}

function Start-ODTPlaylistResolver {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][string]$EnginePath,[ValidateSet('Original','128','192','256','320')][string]$Quality='320',[switch]$SingleTrack)
    if(-not(Test-Path -LiteralPath $EnginePath -PathType Leaf)){throw "Motor de playlist nao encontrado: $EnginePath"}
    $logRoot=Join-Path (Get-AppDataRoot) 'DownloadLogs';[IO.Directory]::CreateDirectory($logRoot)|Out-Null;$id=Get-Date -Format 'yyyyMMdd-HHmmssfff';$stdout=Join-Path $logRoot "$id.playlist.out.log";$stderr=Join-Path $logRoot "$id.playlist.err.log"
    $resolverUrl=ConvertTo-ODTPlaylistResolverUrl -Url $Url
    $arguments=New-Object Collections.Generic.List[string];foreach($value in @('--flat-playlist','--dump-single-json','--no-warnings','--skip-download')){$arguments.Add((ConvertTo-ProcessArgument $value))};if($SingleTrack){$arguments.Add((ConvertTo-ProcessArgument '--no-playlist'))}
    if($Url -match '(?i)/discover/sets/personalized-tracks'){$browser=Get-ODTSoundCloudBrowser;if($browser){$arguments.Add((ConvertTo-ProcessArgument '--cookies-from-browser'));$arguments.Add((ConvertTo-ProcessArgument $browser))}}
    $arguments.Add((ConvertTo-ProcessArgument $resolverUrl))
    $process=Start-Process -FilePath $EnginePath -ArgumentList ($arguments -join ' ') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $source=try{([Uri]$Url).Host -replace '^www\.',''}catch{'Playlist'}
    return [pscustomobject]@{Kind='PlaylistResolver';Id=$id;IsSelected=$true;Title=$(if($SingleTrack){'Lendo dados da track...'}else{'Lendo playlist...'});Source=$source;Duration='';Thumbnail='';Url=$Url;ResolverUrl=$resolverUrl;Quality=$(if($Quality -eq 'Original'){'Audio original'}else{"MP3 ${Quality} kbps"});QualityCode=$Quality;Status='Analisando';Progress='0%';ProgressValue=0;Detail=$(if($SingleTrack){'Buscando título, artista e capa'}else{'Separando playlist em tracks'});Process=$process;EnginePath=$EnginePath;StdOutPath=$stdout;StdErrPath=$stderr;OutputFolder=$OutputRoot;StartedAt=Get-Date;TimeoutSeconds=$(if($SingleTrack){90}else{300});FinishedAt=$null;SingleTrack=[bool]$SingleTrack}
}

function Test-ResolverTimeout {
    param([Parameter(Mandatory)]$Resolver)
    $timeout=if($Resolver.PSObject.Properties['TimeoutSeconds']){[int]$Resolver.TimeoutSeconds}else{300}
    if($Resolver.Process.HasExited -or -not$Resolver.PSObject.Properties['StartedAt'] -or ((Get-Date)-[datetime]$Resolver.StartedAt).TotalSeconds -le $timeout){return $false}
    try{$Resolver.Process.Kill();$Resolver.Process.WaitForExit()}catch{}
    $Resolver.Status='Falhou';$Resolver.FinishedAt=Get-Date;$Resolver.Detail="A fonte não respondeu dentro de $timeout segundos. Tente novamente.";$Resolver.Progress='';$Resolver.ProgressValue=0
    return $true
}

function New-ODTSingleTrackFallback {
    param([Parameter(Mandatory)]$Resolver,[string]$Reason='')
    $single=[bool](Get-ODTObjectProperty $Resolver 'SingleTrack' $false)
    if(-not$single -or [string]$Resolver.Url -notmatch '^https?://'){return $null}
    try{$uri=[Uri][string]$Resolver.Url;$leaf=[Uri]::UnescapeDataString($uri.Segments[$uri.Segments.Count-1]).Trim('/')}catch{$leaf=''}
    $title=($leaf -replace '[-_]+',' ' -replace '\s+',' ').Trim()
    if(-not$title){return $null}
    $detail='Fonte original indisponível; será buscada em outra fonte ao baixar'
    $request=[pscustomobject]@{Kind='TrackRequest';IsSelected=$true;Title=$title;Artist='';Source=[string]$Resolver.Source;Duration='';Thumbnail='';Url=[string]$Resolver.Url;DownloadUrl="ytsearch1:$title audio";Quality=$Resolver.Quality;QualityCode=$Resolver.QualityCode;Status='Pronto';Progress='';ProgressValue=0;Detail=$detail;Process=$null;OutputFolder=$Resolver.OutputFolder;FallbackReason=$Reason}
    $Resolver.Status='Expandida';$Resolver.Progress='100%';$Resolver.ProgressValue=100;$Resolver.Detail='Track preparada com busca alternativa'
    return $request
}

function Complete-ODTPlaylistResolver {
    param([Parameter(Mandatory)]$Resolver)
    $Resolver.Process.Refresh();if(Test-ResolverTimeout -Resolver $Resolver){return @()};if(-not$Resolver.Process.HasExited){return @()};$Resolver.Process.WaitForExit();$Resolver.FinishedAt=Get-Date;$text=Read-SharedUtf8Text -Path $Resolver.StdOutPath;$exitCode=[int]$Resolver.Process.ExitCode
    if($exitCode -ne 0){
        $errorText=$text+"`n"+(Read-SharedUtf8Text -Path $Resolver.StdErrPath)
        if([string]$Resolver.Url -match '(?i)^https?://(?:www\.)?soundcloud\.com/[^/]+/sets/[^/?#]+/?(?:[?#].*)?$' -and $errorText -match '(?i)HTTP\s*Error\s*404|404\s*Not\s*Found'){
            $Resolver.Status='Link privado';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail='No SoundCloud, abra Compartilhar e copie o campo Link de Compartilhamento privado (o endereço contém /s-...). Depois cole esse link no CRIVO.';return @()
        }
        $failure=if([string]$Resolver.Url -match '(?i)/discover/sets/personalized-tracks'){'Não foi possível ler a playlist personalizada com a sessão local do navegador. Feche o Edge/Chrome e tente novamente; se continuar, use um link público/compartilhável do SoundCloud.'}else{Get-DownloadFailureDetail -Text $errorText -ExitCode $exitCode}
        $fallback=New-ODTSingleTrackFallback -Resolver $Resolver -Reason $failure;if($fallback){return @($fallback)};$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail=$failure;return @()
    }
    try{$json=$text|ConvertFrom-Json}catch{$failure='A resposta da fonte nao pode ser interpretada.';$fallback=New-ODTSingleTrackFallback -Resolver $Resolver -Reason $failure;if($fallback){return @($fallback)};$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail=$failure;return @()}
    if($null -eq $json){$errorText=Read-SharedUtf8Text -Path $Resolver.StdErrPath;$failure=if($errorText){Get-DownloadFailureDetail -Text $errorText -ExitCode $exitCode}else{'A fonte respondeu sem dados para essa track.'};$fallback=New-ODTSingleTrackFallback -Resolver $Resolver -Reason $failure;if($fallback){return @($fallback)};$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail=$failure;return @()}
    [object[]]$entries=@();$jsonEntries=Get-ODTObjectProperty -InputObject $json -Name 'entries' -Default $null;if($null -ne $jsonEntries){$entries=@($jsonEntries)}else{$entries=@($json)}
    $entryCount=($entries|Measure-Object).Count
    if($entryCount -eq 0){$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail='Nenhuma track utilizável foi encontrada nesse link.';return @()}
    $items=New-Object Collections.Generic.List[object];$index=0
    $isSoundCloud=[string]$Resolver.Source -match '(?i)soundcloud'
    $soundCloudMetadata=@{}
    if($isSoundCloud){$soundCloudMetadata=Get-ODTSoundCloudTrackMetadata -Ids @($entries|ForEach-Object{[string](Get-ODTObjectProperty $_ 'id' '')})}
    $parentTitle=[string](Get-ODTObjectProperty $json 'title' '');$parentArtist=[string](Get-ODTObjectProperty $json 'album_artist' '');if(-not$parentArtist){$parentArtist=[string](Get-ODTObjectProperty $json 'uploader' '')};$parentDuration=[string](Get-ODTObjectProperty $json 'duration_string' '');$parentThumbnail=[string](Get-ODTObjectProperty $json 'thumbnail' '')
    if(-not$parentThumbnail){$parentThumbnails=@(Get-ODTObjectProperty $json 'thumbnails' @());if(($parentThumbnails|Measure-Object).Count){$parentThumbnail=[string](Get-ODTObjectProperty $parentThumbnails[-1] 'url' '')}}
    foreach($entry in $entries){
        if($null -eq $entry){continue};$index++;$trackUrl=[string](Get-ODTObjectProperty $entry 'webpage_url' '');if(-not$trackUrl){$trackUrl=[string](Get-ODTObjectProperty $entry 'url' '')};if($trackUrl -notmatch '^https?://'){continue}
        $title=[string](Get-ODTObjectProperty $entry 'title' '');$artist=[string](Get-ODTObjectProperty $entry 'uploader' '');$duration=[string](Get-ODTObjectProperty $entry 'duration_string' '');$thumbnail=[string](Get-ODTObjectProperty $entry 'thumbnail' '')
        $entryId=[string](Get-ODTObjectProperty $entry 'id' '')
        if($isSoundCloud -and $entryId -and $soundCloudMetadata.ContainsKey($entryId)){
            $metadata=$soundCloudMetadata[$entryId];$title=[string]$metadata.title
            if($metadata.user){$artist=[string]$metadata.user.username}
            $thumbnail=[string]$metadata.artwork_url
            if($metadata.permalink_url){$trackUrl=[string]$metadata.permalink_url}
            if($metadata.duration){$seconds=[int][Math]::Round(([double]$metadata.duration)/1000);$duration='{0}:{1:00}' -f [int][Math]::Floor($seconds/60),($seconds%60)}
        }
        if(-not$thumbnail){$entryThumbnails=@(Get-ODTObjectProperty $entry 'thumbnails' @());if(($entryThumbnails|Measure-Object).Count){$thumbnail=[string](Get-ODTObjectProperty $entryThumbnails[-1] 'url' '')}}
        if($entryCount -eq 1){if(-not$title){$title=$parentTitle};if(-not$duration){$duration=$parentDuration}}
        if(-not$artist -and -not$isSoundCloud){$artist=$parentArtist}
        if(-not$thumbnail -and -not$isSoundCloud){$thumbnail=$parentThumbnail}
        if(-not$title){try{$leaf=[Uri]::UnescapeDataString(([Uri]$trackUrl).Segments[-1]).Trim('/');$title=($leaf -replace '[-_]+',' ' -replace '\s+',' ').Trim()}catch{$title=''}}
        if(-not$title){$title="Track $index"};$items.Add([pscustomobject]@{Kind='TrackRequest';IsSelected=$true;Title=$title;Artist=$artist;Source=$Resolver.Source;Duration=$duration;Thumbnail=$thumbnail;Url=$trackUrl;DownloadUrl=$trackUrl;Quality=$Resolver.Quality;QualityCode=$Resolver.QualityCode;Status='Pronto';Progress='';ProgressValue=0;Detail='Marque e clique em Iniciar download';Process=$null;OutputFolder=$Resolver.OutputFolder})
    }
    if(-not$items.Count){$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail='Nenhuma track utilizável foi encontrada nesse link.';return @()}
    $Resolver.Status='Expandida';$Resolver.Progress='100%';$Resolver.ProgressValue=100;$Resolver.Detail="$($items.Count) tracks encontradas";return $items.ToArray()
}

function Complete-ODTSpotifyResolver {
    param([Parameter(Mandatory)]$Resolver)
    $Resolver.Process.Refresh();if(Test-ResolverTimeout -Resolver $Resolver){return @()}
    $savedSignal=$false
    if(-not$Resolver.Process.HasExited){
        $liveText=(Read-SharedUtf8Text -Path $Resolver.StdOutPath)+"`n"+(Read-SharedUtf8Text -Path $Resolver.StdErrPath)
        $found=[regex]::Match($liveText,'Found\s+(\d+)\s+songs?',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if($found.Success){$Resolver.ProgressValue=[Math]::Max([int]$Resolver.ProgressValue,55);$Resolver.Progress="$($Resolver.ProgressValue)%";$Resolver.Detail="$($found.Groups[1].Value) tracks encontradas; carregando dados e capas"}
        elseif($liveText -match 'Processing query'){$Resolver.Detail='Consultando o Spotify…'}
        $savedSignal=($liveText -match '(?i)Saved\s+\d+\s+songs?\s+to') -and (Test-Path -LiteralPath $Resolver.SaveFile -PathType Leaf)
        if(-not$savedSignal){return @()}
        # Algumas versões empacotadas do spotDL mantêm um processo auxiliar vivo
        # depois de gravar o JSON. O arquivo e a mensagem Saved são a conclusão
        # real; encerramos apenas esse resolvedor já finalizado para liberar a lista.
        try{$Resolver.Process.Kill();$Resolver.Process.WaitForExit()}catch{}
    }
    $Resolver.Process.WaitForExit();$Resolver.FinishedAt=Get-Date;$text=(Read-SharedUtf8Text -Path $Resolver.StdOutPath)+"`n"+(Read-SharedUtf8Text -Path $Resolver.StdErrPath);$exitCode=[int]$Resolver.Process.ExitCode
    $savedOk=(Test-Path -LiteralPath $Resolver.SaveFile -PathType Leaf) -and ($exitCode -eq 0 -or $savedSignal -or $text -match '(?i)Saved\s+\d+\s+songs?\s+to')
    if(-not$savedOk){$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail=Get-DownloadFailureDetail -Text $text -ExitCode $exitCode;return @()}
    try{$parsedSongs=Get-Content -LiteralPath $Resolver.SaveFile -Raw -Encoding UTF8|ConvertFrom-Json;$songs=New-Object Collections.Generic.List[object];foreach($parsedSong in $parsedSongs){$songs.Add($parsedSong)}}catch{$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail='A lista do Spotify nao pode ser interpretada.';return @()}
    $items=New-Object Collections.Generic.List[object]
    foreach($song in $songs){
        if($null -eq $song){continue};$artist=[string](Get-ODTObjectProperty $song 'artist' '');if(-not$artist){$artist=@(Get-ODTObjectProperty $song 'artists' @())-join ', '};$title=[string](Get-ODTObjectProperty $song 'name' '');if(-not$title){continue}
        $seconds=0;[void][int]::TryParse([string](Get-ODTObjectProperty $song 'duration' 0),[ref]$seconds);$duration=if($seconds -gt 0){'{0}:{1:00}' -f [int][Math]::Floor($seconds/60),($seconds%60)}else{''}
        $thumbnail=[string](Get-ODTObjectProperty $song 'cover_url' '');if(-not$thumbnail){$thumbnail=[string](Get-ODTObjectProperty $song 'cover' '')};$songUrl=[string](Get-ODTObjectProperty $song 'url' '')
        $items.Add([pscustomobject]@{Kind='TrackRequest';IsSelected=$true;Title=$title;Artist=$artist;Source='Spotify';Duration=$duration;Thumbnail=$thumbnail;Url=$songUrl;DownloadUrl="ytsearch1:$artist - $title audio";Quality=$Resolver.Quality;QualityCode=$Resolver.QualityCode;Status='Pronto';Progress='';ProgressValue=0;Detail='Marque e clique em Iniciar download';Process=$null;OutputFolder=$Resolver.OutputFolder})
    }
    if(-not$items.Count){$Resolver.Status='Falhou';$Resolver.Progress='';$Resolver.ProgressValue=0;$Resolver.Detail='O Spotify não retornou nenhuma track utilizável.';return @()}
    $Resolver.Status='Expandida';$Resolver.Progress='100%';$Resolver.ProgressValue=100;$Resolver.Detail="$($items.Count) tracks adicionadas a fila";$Resolver.Expanded=$true
    return $items.ToArray()
}

function Get-ODTDownloadProgress {
    param([Parameter(Mandatory)]$Download)
    $text=Read-SharedUtf8Text -Path $Download.StdOutPath
    $errorText=Read-SharedUtf8Text -Path $Download.StdErrPath
    if($errorText){$text+="`n$errorText"}
    $meta=[regex]::Matches($text,'(?m)^ODT_META\|([^|\r\n]*)\|([^|\r\n]*)\|([^|\r\n]*)\|([^|\r\n]*)');if($meta.Count){$last=$meta[$meta.Count-1];if(-not$Download.LockMetadata){$Download.Title=$last.Groups[1].Value;$Download.Duration=$last.Groups[3].Value};if(-not$Download.Thumbnail){$Download.Thumbnail=$last.Groups[4].Value}}
    $fileMatches=[regex]::Matches($text,'(?m)^ODT_FILE\|([^\r\n]+)$');if($fileMatches.Count){$Download.FinalPath=$fileMatches[$fileMatches.Count-1].Groups[1].Value.Trim()}
    $matches=[regex]::Matches($text,'\[download\]\s+(\d{1,3}(?:\.\d+)?)%');$progressValue=if($matches.Count){[Math]::Min(100,[int][Math]::Round([double]$matches[$matches.Count-1].Groups[1].Value))}else{[int]$Download.ProgressValue};$progress="$progressValue%"
    $lines=@($text -split '[\r\n]+'|Where-Object{$_ -match '^\[download\]'});if($lines.Count){$Download.Detail=$lines[$lines.Count-1]}
    $Download.Process.Refresh();if($Download.Process.HasExited){
        $Download.FinishedAt=Get-Date
        $exitCode=[int]$Download.Process.ExitCode
        $existing=$null;if($Download.PSObject.Properties['FinalPath'] -and $Download.FinalPath -and (Test-Path -LiteralPath $Download.FinalPath -PathType Leaf)){$existing=Get-Item -LiteralPath $Download.FinalPath}else{$existing=Find-DownloadedTrackFile -Download $Download}
        if($existing){
            $Download.Status='Concluido';$progress='100%';$progressValue=100
            if($Download.PSObject.Properties['FinalPath']){$Download.FinalPath=$existing.FullName}else{$Download|Add-Member NoteProperty FinalPath $existing.FullName}
            $Download.Detail=if($exitCode -ne 0 -and $existing){'A faixa ja existia no destino'}else{'Pronto para organizar'}
        }else{
            $Download.Status='Falhou';$failure=Get-DownloadFailureDetail -Text $text -ExitCode $exitCode;$Download.Detail=if($exitCode -eq 0 -and $failure -notmatch '(?i)error|failed|unable|erro|falhou'){'O downloader terminou, mas o arquivo final não foi encontrado.'}else{$failure}
        }
    }
    $Download.Progress=$progress;$Download.ProgressValue=$progressValue;return $Download
}

Export-ModuleMember -Function Start-ODTDownload,Get-ODTDownloadProgress,Start-ODTSpotifyResolver,Complete-ODTSpotifyResolver,Start-ODTPlaylistResolver,Complete-ODTPlaylistResolver
