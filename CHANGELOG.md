# Histórico de versões

Todas as mudanças relevantes do CRIVO DJ serão registradas neste arquivo.

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
