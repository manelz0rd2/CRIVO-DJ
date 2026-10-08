<p align="center">
  <img src="Assets/CRIVO-DJ.png" width="144" alt="Ícone do CRIVO DJ">
</p>

<h1 align="center">CRIVO DJ</h1>

<p align="center"><strong>Curadoria, Revisão, Identificação, Validação e Organização</strong></p>

<p align="center">
  <img alt="Versão" src="https://img.shields.io/badge/versão-0.9.0--beta.1-111111">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-PowerShell%205.1-111111">
  <img alt="Estado" src="https://img.shields.io/badge/estado-beta%20fechada-6f6b63">
  <img alt="Instalação" src="https://img.shields.io/badge/instalação-portátil-111111">
  <img alt="Validação" src="https://github.com/manelz0rd2/CRIVO-DJ/actions/workflows/validate.yml/badge.svg">
</p>

<p align="center"><strong>CRIVO DJ por MANELZ0RD</strong></p>

Aplicativo portátil para Windows que conecta aquisição, curadoria, organização e Rekordbox em um fluxo único. O CRIVO DJ pode cuidar do caminho completo — do link até uma playlist pronta no Rekordbox — ou trabalhar separadamente com uma pasta de músicas que você já possui e com a auditoria da sua biblioteca.

> **Beta fechado:** use sempre cópias ou backups durante os testes. A escrita direta no Rekordbox possui backup, transação e verificação, mas não substitui uma biblioteca bem protegida.

## Download

A versão portátil completa, com as dependências necessárias, é distribuída pela seção [**Releases**](https://github.com/manelz0rd2/CRIVO-DJ/releases). Baixe o ZIP da versão mais recente, extraia em uma pasta comum e abra `CRIVO DJ.exe`. Não é necessário instalar nem executar como administrador.

O repositório guarda o código-fonte, testes e documentação. Binários de terceiros e o pacote pronto ficam anexados à Release para manter o histórico Git leve e auditável.

## Visão geral

### Baixar

![Fila de download do CRIVO DJ](docs/screenshots/01-baixar-tracks.png)

### Organizar

![Planejamento de organização do CRIVO DJ](docs/screenshots/02-organizar-biblioteca.png)

### Auditoria

![Auditoria da biblioteca do Rekordbox](docs/screenshots/03-auditoria-rekordbox.png)

## O que o CRIVO DJ faz

### Workflow completo: baixar → revisar → organizar → Rekordbox

O CRIVO DJ aceita tracks individuais e playlists do YouTube, SoundCloud e Spotify. Uma playlist é separada em tracks dentro do grid, com capa, título, artista, duração, origem e progresso independentes. Depois do download, as músicas seguem para a organização sem precisar remontar a seleção manualmente.

Na etapa de organização, o programa monta uma prévia da estrutura de pastas, identifica dados faltantes e permite corrigir manualmente título, artista, álbum, gênero, ano e outros campos antes de aplicar qualquer mudança. Ao concluir, os arquivos ficam organizados no computador e, opcionalmente, são registrados na coleção e em uma playlist do Rekordbox com o nome escolhido no CRIVO.

```text
track ou playlist → fila com capas → revisão de dados → organização física → playlist no Rekordbox
```

O arquivo de áudio permanece no destino organizado; o Rekordbox recebe a referência correta para a track. A integração direta cria backup do banco, usa transação e confere o resultado antes de encerrar.

### Somente organizar músicas existentes

O download não é obrigatório. Você pode apontar o CRIVO DJ para qualquer pasta que já contenha sua pesquisa musical, revisar como cada arquivo ficará, editar dados faltantes e organizar por data, gênero, BPM ou uma combinação desses critérios. O modo padrão copia os arquivos e preserva os originais; mover é uma escolha explícita. Essa organização também pode terminar em uma playlist criada diretamente no Rekordbox.

### Auditoria independente da biblioteca

A Auditoria funciona como uma ferramenta separada do fluxo de download e organização. Ela lê a biblioteca do Rekordbox em modo somente leitura durante o escaneamento e ajuda a localizar:

- tracks sem arquivo físico, com caminho inacessível ou fora da coleção;
- metadados incompletos e possíveis problemas de qualidade;
- tracks sem dados de análise do Rekordbox;
- duplicatas exatas ou prováveis;
- arquivos órfãos e inconsistências entre o banco, as pastas e um pendrive exportado;
- as playlists e pastas de playlists das quais cada track faz parte.

Os resultados podem ser pesquisados, filtrados e exportados. O escaneamento não corrige nada automaticamente: a revisão e qualquer gravação posterior são decisões explícitas do usuário.

### Onde entra o Rekordbox

O CRIVO DJ prepara, organiza, registra playlists e audita a biblioteca. O Rekordbox continua responsável pela análise musical definitiva — waveform, beatgrid, BPM e tonalidade — e pela exportação final para pendrives e equipamentos.

## Recursos

- MP3, WAV, FLAC, AIFF/AIF, M4A, AAC, OGG e WMA, com formatos editáveis;
- aliases de gênero e prioridades de fallback editáveis;
- metadata ausente separada em `_SEM GENERO`, `_SEM DATA` e `_SEM BPM`, mantida na raiz, resolvida por prioridade ou ignorada;
- exceções de pastas e extensões;
- duplicatas por nome, nome + tamanho, hash SHA-256 ou metadata semelhante;
- conflitos: pular, substituir, manter ambos com `(2)` ou comparar hash;
- auditoria de título, artista, gênero, BPM, tonalidade, corrupção e qualidade;
- BPM lido da tag, da propriedade nomeada do Windows, de comentários compatíveis ou do nome do arquivo; campo vazio significa que o valor não foi gravado na faixa;
- bitrate, sample rate, bit depth e codec, com destaque de qualidade suspeita;
- mapa de bitrate por amostragem de frames MP3, com mínimo, máximo, média e modo CBR/VBR;
- relatório CSV depois da execução e dry-run em CSV ou JSON antes dela;
- histórico com contagens e desfazer de qualquer execução preservada;
- busca por track, filtro de metadata faltando e edição antes de aplicar;
- faixas de BPM, normalização de nomes e termos removidos configuráveis;
- proteção de nomes reservados, caracteres inválidos e caminhos longos;
- pastas favoritas, arrastar e soltar e monitoramento de novas músicas;
- importar/exportar todas as regras em JSON;
- logs simples ou detalhados;
- painel inicial/auditoria;
- enriquecimento online com MusicBrainz, cache local, confiança e revisão;
- identificação opcional por fingerprint AcoustID, sem envio do áudio;
- gravação opcional das tags aprovadas, com histórico e undo;
- destino de download selecionável e persistente; **Organizar concluídos** envia essa pasta diretamente ao core;
- integração direta com o banco do Rekordbox por Pyrekordbox e SQLCipher, além de XML/M3U8 como formatos auxiliares;
- funcionamento portátil e sem instalação no Windows PowerShell 5.1; preferências, relatórios, histórico, cache e backups ficam em `%LOCALAPPDATA%\CRIVO DJ`;
- verificação do ambiente e exportação de diagnóstico sem caminhos pessoais, links privados ou chaves;
- auditoria informa em quais playlists e pastas de playlists do Rekordbox cada track aparece.

O monitoramento apenas detecta novas músicas e recalcula o plano. Ele nunca organiza automaticamente.

## Aquisição e Rekordbox

O CRIVO DJ possui uma fila interna baseada no yt-dlp. Links podem ser arrastados diretamente para o grid ou colados no campo. Ao adicionar, o app consulta título, artista, capa e, quando necessário, separa a playlist em tracks; o download do áudio só começa após **Iniciar download**. Cada linha pode ser marcada ou desmarcada. Antes de baixar, o campo **Salvar tracks em** permite escolher qualquer pasta e guarda essa escolha para o próximo uso. O áudio é processado pelo FFmpeg, recebe a metadata disponibilizada pela fonte e é salvo como MP3 320 kbps; **Organizar concluídos** leva essa pasta ao core do CRIVO DJ. Converter uma fonte de baixa qualidade para 320 kbps não recupera informação perdida. Use o recurso apenas em conteúdos que você tenha autorização para baixar.

Links de faixa, álbum ou playlist do Spotify são analisados pelo spotDL e expandidos em uma linha por track. O CRIVO DJ usa somente a metadata do Spotify e monta uma busca individual em fonte externa; ele não extrai o stream de áudio do Spotify. A resolução ocorre em segundo plano e no máximo duas tracks são baixadas ao mesmo tempo.

A fila de download apresenta cada link como uma faixa, com capa, título detectado, fonte, duração, barra de progresso, detalhe da transferência e status. A aba Baixar não consulta a coleção do Rekordbox; duplicidades da biblioteca são tratadas pela Auditoria. Se a faixa já estiver no destino, ela é reconhecida como concluída. Falhas reais permanecem na fila com a causa apresentada na própria linha e não encerram o aplicativo.

No menu lateral de **Organizar**, a opção **Gravar playlist diretamente no Rekordbox** libera o campo de nome da playlist. O botão **Escolher**, logo abaixo, permite indicar e memorizar o `rekordbox.exe`. Ao terminar a organização, o CRIVO DJ exige que `rekordbox.exe` e `rekordboxAgent.exe` estejam fechados, cria um backup datado do banco, abre o `master.db` criptografado por SQLCipher, cria ou atualiza a playlist, inclui na coleção as tracks ainda inexistentes, grava tudo em uma transação e reabre o banco para verificar o resultado. Se qualquer etapa falhar, o backup é restaurado automaticamente. O XML e a M3U8 continuam sendo gerados como formatos auxiliares de recuperação.

Na aba **Auditoria**, o Pyrekordbox lê diretamente o `master.db`, cuja localização é detectada automaticamente. Uma pasta, biblioteca ou HD pode ser escolhida opcionalmente para comparação. O painel resume coleção, problemas, arquivos ausentes e tracks locais fora da coleção; a tabela mostra também todas as playlists e pastas de playlists às quais cada track pertence. Ela pode ser pesquisada e filtrada por tipo de diagnóstico, inclusive ausência de arquivos ANLZ de waveform/beatgrid. As tracks locais ainda desconhecidas pelo Rekordbox podem ser enviadas para uma playlist de resgate por uma gravação transacional com backup e verificação. O resultado informa quantas já preservaram análise e quantas precisam passar pelo comando **Analyze Track** do Rekordbox. O relatório completo continua exportável em CSV ou JSON.

## Buscar dados ausentes

Depois de analisar uma pasta, clique em **Buscar dados ausentes**. O CRIVO DJ consulta somente as faixas selecionadas que tenham título, artista, álbum, gênero ou ano ausentes. Os resultados aparecem em uma comparação entre **Dados atuais** e **Encontrado online**, com confiança e fonte. Nada é aplicado sem aprovação, e o arquivo só é alterado quando a gravação de tags for escolhida.

A busca textual no MusicBrainz funciona sem conta. Para identificação pelo áudio, registre uma chave de cliente em https://acoustid.org/api-key e cole-a em **Regras e formatos → Chave de cliente AcoustID**. A impressão digital é calculada localmente; o áudio não é enviado.

Na revisão, a opção **Gravar tags aprovadas nos arquivos** escreve os campos usando TagLibSharp e registra os valores anteriores no histórico. Essa execução pode ser escolhida em **Desfazer execução**.

## Variáveis de pasta

`{AAAA}`, `{AA}`, `{MES}`, `{MES_NUM}`, `{DIA}`, `{GENERO}`, `{ARTISTA}`, `{ALBUM}`, `{ANO}`, `{BPM}`, `{BPM_RANGE}`, `{KEY}`, `{EXTENSAO}`, `{FORMATO}`, `{PASTA_ORIGEM}`, `{PASTA_PAI}`, `{PASTA_RAIZ}`, `{NOME_ARQUIVO}`, `{TITULO}`, `{BITRATE}` e `{SAMPLE_RATE}`.

Exemplo: `{AAAA} - {MES_NUM} - {MES} - {GENERO} - {BPM_RANGE}`.

## Segurança

- Calcular e exportar a simulação não altera nenhum arquivo.
- O plano inteiro é validado antes da execução.
- `Copiar` é o padrão.
- Cada execução pode gerar um manifesto para desfazer.
- Pastas de saída e pastas excluídas não retornam ao scanner.
- O modo **Mover** exige confirmação explícita.

## Leitura e gravação de metadata

O CRIVO DJ inclui o TagLibSharp para ler e gravar tags nos formatos compatíveis. Quando uma tag é alterada pela revisão online, os valores anteriores são registrados no histórico para permitir o desfazer.

## Testes

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\RunTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\TestRekordboxSandbox.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Tests\TestAuditRuntime.ps1
```

O segundo teste escreve apenas numa cópia temporária do `master.db`, confere a playlist, repete a importação para detectar duplicação e verifica por hash que o banco real permaneceu intacto. O terceiro percorre exatamente a rotina do botão **Analisar agora** em modo somente leitura e confirma indicadores e grid.

## Estrutura do projeto

```text
Assets/       identidade visual e ícones
Config/       configuração padrão sanitizada
Modules/      scanner, metadata, downloads, organização e Rekordbox
Tests/        regressão, stress, runtime e sandbox
Tools/        fontes dos launchers e da integração direta
UI/           interface WPF
ODT.ps1       aplicação principal
```

Consulte também o [histórico de versões](CHANGELOG.md), as [orientações para contribuir](CONTRIBUTING.md), a [política de segurança](SECURITY.md) e as [dependências de terceiros](THIRD-PARTY.md).

## Licença

Este repositório ainda não possui uma licença pública de reutilização. Todos os direitos permanecem reservados a MANELZ0RD até a definição da licença do projeto. As dependências mantêm suas próprias licenças, listadas em `THIRD-PARTY.md`.
