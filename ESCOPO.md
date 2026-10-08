# Matriz de aceite do escopo

1. **Normalização:** aliases editáveis em Regras e formatos; inclui UKG/2-Step e Deep House.
2. **Metadata ausente:** separar em `_SEM...`, manter na raiz, aplicar prioridades ou ignorar.
3. **Exceções:** pastas e extensões editáveis; padrões incluem `_BACKUP`, `Pesquisa Organizada`, `Rekordbox` e `Samples`.
4. **Tipos de arquivo:** lista de formatos de áudio editável e chave “Somente arquivos de áudio”; extensões explicitamente ignoradas continuam excluídas em ambos os modos.
5. **Duplicatas:** nome, nome+tamanho, SHA-256 e metadata semelhante.
6. **Conflitos:** pular, substituir, manter ambos com `(2)` ou comparar hash.
7. **Qualidade:** codec, bitrate, sample rate, bit depth, limites editáveis e indicador de suspeita.
8. **Auditoria:** título, artista, gênero, BPM, tonalidade, duplicatas, corrupção e acesso.
9. **Antes/depois:** dry-run CSV/JSON e relatório CSV final com origem, destino, regra, metadata, status e erro.
10. **Histórico:** data, configuração usada, origem/destino e contagens.
11. **Undo real:** botão permite escolher qualquer execução ainda não desfeita.
12. **Dry-run:** `Exportar simulação`; não copia nem move.
13. **Drag and drop:** uma pasta pode ser arrastada para a janela.
14. **Watch Folder:** monitora a origem e recalcula o plano quando chegam músicas; nunca executa sozinho.
15. **Favoritos:** atalhos configuráveis em `Pastas favoritas`.
16. **Busca:** pesquisa direta por nome ou título da track.
17. **Filtros:** chave simples para mostrar somente tracks com metadata faltando; diagnósticos completos ficam em Auditoria.
18. **Edição:** nome final, artista, gênero e destino antes da execução; os demais campos permanecem disponíveis nas regras, auditoria e relatórios.
19. **Prioridades:** metadata → pasta de origem → `_PENDENTE`, editável em JSON exportado.
20. **BPM configurável:** faixas editáveis em Regras e formatos.
21. **Tonalidade:** leitura e campo de pasta `{KEY}`; aceita Camelot ou tradicional.
22. **Conversão de nomes:** underscores, capitalização, repetições e termos removidos.
23. **Nomes inválidos:** caracteres do Windows, nomes reservados e limite de caminho.
24. **Portátil:** inicia por `CRIVO DJ.exe`, com ícone próprio e sem console; preferências, histórico, cache e backups ficam em `%LOCALAPPDATA%\CRIVO DJ`, sem exigir instalação ou permissão administrativa.
25. **Backup de configuração:** importar/exportar JSON.
26. **Log:** modo simples ou detalhado.
27. **Dashboard:** auditoria e resumo da última execução.
28. **Metadata online:** MusicBrainz por texto, AcoustID opcional por fingerprint, cache, confiança, revisão, gravação de tags e undo.
29. **Baixar músicas:** fila interna por link, playlists dissecadas em tracks, seleção individual, capas, duas transferências simultâneas, saída MP3 320 kbps e destino persistente.
30. **Rekordbox:** leitura e auditoria do `master.db`, comparação com pasta/HD, diagnóstico de ANLZ, playlist de resgate e gravação transacional direta via Pyrekordbox/SQLCipher com backup e verificação.

Não existem perfis obrigatórios ou estado oculto entre usos: cada uso parte da parametrização visível. O JSON é apenas backup/importação opcional das regras.
