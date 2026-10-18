# Histórico de versões

Todas as mudanças relevantes do CRIVO DJ serão registradas neste arquivo.

## [0.9.9] — 2026-10-18

### Fluxo principal

- fila de downloads revisada para só marcar uma track como concluída depois de confirmar o arquivo no destino;
- suporte a tracks e playlists com capas e dados próprios de cada música;
- organizador simplificado, com lista pesquisável, filtros de dados faltantes e revisão manual mais clara;
- nome da playlist do Rekordbox ligado ao resultado da organização ou definido pelo usuário;
- textos e mensagens revisados para linguagem acessível ao usuário final.

### Auditoria e Kit USB

- auditoria do Rekordbox e de pendrives com playlist, diagnóstico, formato e qualidade na lista;
- tratamento de bibliotecas incompletas e bancos ausentes sem interromper toda a análise;
- novo Kit de Ferramentas USB com diagnóstico, cópia segura, recuperação em outro local e comparação de compatibilidade;
- recuperação conservadora, sem reconstruir ou sobrescrever diretamente o dispositivo original;
- novas verificações automatizadas de interface, downloads, organização e auditoria.

### Plataforma

- pacote v0.9.9 completo para Windows;
- versão para macOS retirada das releases enquanto o fluxo completo permanece em desenvolvimento.

## [0.9.0-beta.1] — 2026-10-08

### Adicionado

- download e expansão de tracks e playlists do YouTube, SoundCloud e Spotify;
- capas, título, artista, duração e progresso individual na fila;
- organização por data, gênero e BPM com pré-visualização e desfazer;
- edição manual e enriquecimento de metadados com MusicBrainz e AcoustID opcional;
- integração transacional com o banco do Rekordbox, com backup e verificação;
- auditoria da coleção e de mídias exportadas, incluindo arquivos ausentes, duplicatas, análise e qualidade;
- exibição das playlists do Rekordbox na lista da auditoria;
- verificação de ambiente e diagnóstico sanitizado para suporte;
- armazenamento portátil com dados mutáveis isolados em `%LOCALAPPDATA%\CRIVO DJ`.

### Segurança e estabilidade

- execução destrutiva bloqueada até a validação completa do plano;
- modo copiar como padrão;
- escrita no Rekordbox protegida por transação, backup e restauração automática;
- testes de regressão, stress, runtime da auditoria e sandbox do Rekordbox.

[0.9.0-beta.1]: https://github.com/manelz0rd2/CRIVO-DJ/releases/tag/v0.9.0-beta.1
[0.9.9]: https://github.com/manelz0rd2/CRIVO-DJ/releases/tag/v0.9.9
