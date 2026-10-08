# Componentes de terceiros

- **Chromaprint / fpcalc 1.6.1** — impressão digital de áudio. Projeto: https://acoustid.org/chromaprint — licença LGPL-2.1.
- **TagLibSharp 2.3.0** — leitura e gravação de tags. Pacote: https://www.nuget.org/packages/TagLibSharp/2.3.0 — licença LGPL-2.1-only.
- **MusicBrainz Web Service** — sugestões de metadata. Uso sujeito aos termos e limites do MusicBrainz: https://musicbrainz.org/doc/MusicBrainz_API.
- **AcoustID Web Service** — identificação opcional por fingerprint. Requer chave de cliente própria e está sujeito aos termos do AcoustID: https://acoustid.org/webservice.
- **yt-dlp 2026.08.19** — motor de aquisição por URL. Projeto: https://github.com/yt-dlp/yt-dlp — binário oficial para Windows e respectivas licenças incluídas pelo projeto.
- **FFmpeg** — extração e conversão de áudio. CRIVO DJ usa o executável configurado pelo usuário; projeto: https://ffmpeg.org/ — licença conforme a compilação utilizada.
- **Pyrekordbox 0.4.4** — acesso transacional ao banco local do Rekordbox 6/7. Projeto: https://github.com/dylanljones/pyrekordbox — licença MIT; integração não oficial e não afiliada à AlphaTheta/Pioneer DJ.
- **SQLCipher / sqlcipher3-wheels 0.5.7** — abertura do `master.db` criptografado, distribuído dentro do helper de integração direta; consulte as licenças incluídas pelos respectivos projetos.
- **SQLAlchemy 2.1.3** — camada transacional usada pelo helper do Rekordbox — licença MIT.

O CRIVO DJ não envia o arquivo de áudio. Quando o AcoustID é usado, o `fpcalc` gera localmente uma impressão digital compacta.
