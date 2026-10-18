# CRIVO DJ v1 — contrato técnico do Kit de ferramentas USB

## Objetivo

Adicionar ferramentas de preparação e recuperação para DJs sem apresentar suposições como garantias. A interface deve sempre diferenciar fatos observados, indícios, incompatibilidades confirmadas e itens que o CRIVO não conseguiu verificar.

## Escopo desta etapa

1. Teste de compatibilidade de equipamento.
2. Diagnóstico de saúde lógica do pendrive.
3. Kit de primeiros socorros com ações seguras e reversíveis.
4. Testes em unidades descartáveis e cenários controlados.

Ficam fora desta etapa a atualização do GitHub, os materiais de divulgação, o QR Code de doação e qualquer alteração da versão macOS.

## Linguagem da interface

O CRIVO não usará expressões como “pendrive saudável”, “recuperação garantida” ou “compatível com qualquer equipamento”.

Estados permitidos:

- **Compatível:** todos os requisitos conhecidos do perfil foram atendidos.
- **Pode apresentar problema:** foi encontrado um risco conhecido, mas o resultado também depende do equipamento ou da exportação.
- **Incompatível:** um requisito documentado do perfil não foi atendido.
- **Não foi possível confirmar:** faltam dados confiáveis para concluir.

Para o pendrive:

- **Nenhum problema encontrado nesta verificação:** não equivale a uma garantia física.
- **Atenção:** há indício que merece revisão.
- **Problema confirmado:** o arquivo, caminho ou estrutura falhou em uma verificação reproduzível.
- **Não verificado:** o sistema operacional ou dispositivo não forneceu informação suficiente.

## Limites técnicos explícitos

- Memórias USB normalmente não fornecem SMART confiável. O CRIVO não estimará desgaste físico sem evidência disponibilizada pelo dispositivo.
- A presença do arquivo não prova que todo o áudio pode ser decodificado.
- Um arquivo de áudio válido não prova que cues, loops, beatgrid ou waveform estejam disponíveis.
- A compatibilidade depende do modelo e, em alguns casos, da versão do firmware.
- Dados destruídos que não existam em banco, backup ou arquivos de análise não podem ser recriados fielmente.
- A reconstrução profunda do banco será tratada como experimental e nunca executada diretamente na única cópia do usuário.

## Fluxo técnico obrigatório

```text
selecionar fonte
    → identificar unidade e estrutura
    → escanear somente em leitura
    → classificar evidências
    → apresentar relatório
    → montar plano de ação
    → exigir backup quando houver escrita
    → executar em cópia ou área temporária
    → validar o resultado
    → permitir exportação consciente
```

## Teste de compatibilidade de equipamento

### Entrada

- modelo selecionado pelo usuário;
- pasta, playlist ou raiz de um pendrive;
- catálogo local versionado de capacidades conhecidas.

### Verificações

- contêiner e codec;
- taxa de amostragem;
- profundidade de bits;
- bitrate e VBR quando relevantes;
- sistema de arquivos do dispositivo;
- existência e leitura do arquivo;
- comprimento e caracteres do caminho;
- estrutura de exportação do Rekordbox;
- arquivos de análise quando o perfil exigir.

### Catálogo

Cada perfil deverá registrar modelo, fabricante, limitações conhecidas, data da revisão e fonte oficial. Quando um requisito não for conhecido, o mecanismo deve retornar **Não foi possível confirmar**, nunca presumir compatibilidade.

Para equipamentos AlphaTheta e Pioneer DJ, são aceitos como fonte técnica apenas manuais, especificações, páginas de suporte e históricos de firmware oficiais publicados pela AlphaTheta/Pioneer DJ. Fóruns, lojas, vídeos, listas comunitárias e memória de uso podem orientar a pesquisa, mas não podem alimentar uma regra de compatibilidade.

Cada perfil deve conter obrigatoriamente:

- fabricante e modelo exatos;
- endereço da documentação oficial;
- título e revisão do documento;
- data em que a fonte foi consultada;
- versão ou faixa de firmware, quando a limitação depender dela;
- formatos, codecs, sistemas de arquivos e limites expressamente documentados;
- campos desconhecidos mantidos como desconhecidos, sem inferência otimista.

Se duas fontes oficiais divergirem, o CRIVO adotará temporariamente a regra mais conservadora e indicará a divergência no diagnóstico até a revisão do perfil.

## Diagnóstico do pendrive

O diagnóstico inicial é estritamente somente leitura e deve registrar:

- unidade, capacidade, espaço livre e sistema de arquivos;
- possibilidade real de leitura;
- estrutura de exportação encontrada;
- banco ausente, ilegível ou inconsistente;
- referências para arquivos inexistentes;
- arquivos de áudio não referenciados;
- duplicatas exatas e possíveis duplicatas;
- arquivos truncados ou não decodificáveis;
- dados de análise ausentes;
- nomes e caminhos potencialmente incompatíveis.

O resultado deve registrar também quais testes não puderam ser executados.

## Kit de ferramentas USB implementado

A interface foi separada em quatro áreas que acompanham a ordem prática do trabalho, todas com linguagem voltada ao DJ:

- **Diagnóstico:** lê o dispositivo sem alterar arquivos e explica problemas, alertas e limites da verificação.
- **Cópia segura:** copia todo o conteúdo para outro local, compara a assinatura digital de cada arquivo e só chama a cópia de concluída depois da validação.
- **Recuperação:** trabalha em outro local, preserva o conteúdo original encontrado e cria playlists M3U8 recuperadas para revisão e importação no Rekordbox.
- **Compatibilidade:** compara o resultado com perfis conservadores baseados em documentação oficial e separa reconhecimento do formato de integridade da biblioteca.

### Entregue nesta etapa

- exportação do diagnóstico;
- cópia completa e validada, com relatório e registro técnico;
- inventário e assinaturas digitais SHA-256;
- reconstrução das playlists que puderam ser lidas com segurança;
- preservação explícita de cópias interrompidas, sem apresentá-las como concluídas;
- abertura direta da pasta de playlists recuperadas para importação manual no Rekordbox.

### Ainda não entregue

- reparo físico do pendrive;
- formatação ou escrita direta na unidade de origem;
- criação automática de um novo pendrive exportado e pronto para qualquer equipamento;
- reconstrução de dados que já foram destruídos e não existem em banco, backup ou arquivo de análise;
- garantia de que toda playlist ou track será recuperada.

## Regras de segurança

- Nenhuma escrita durante o escaneamento.
- A unidade de origem nunca é formatada pelo CRIVO.
- Operações sensíveis exigem destino diferente ou backup validado.
- Espaço livre é verificado antes da cópia.
- Toda ação produz registro e relatório final.
- Interrupções deixam os arquivos originais intactos.
- O botão de ação permanece desabilitado até o plano estar completo e revisado.

## Estrutura implementada

- `Modules/EquipmentCompatibility.psm1`: avaliação contra perfis conhecidos.
- `Modules/UsbHealth.psm1`: coleta somente leitura e classificação de evidências.
- `Modules/UsbBackup.psm1`: cópia integral, validação e tratamento de interrupções.
- `Modules/UsbRecovery.psm1`: plano de recuperação e reconstrução em outro local.
- `Config/equipamentos.json`: catálogo versionado com fontes e limites.
- `Tests/TestEquipmentCompatibility.ps1`: matriz de formatos e perfis.
- `Tests/TestUsbHealth.ps1`: cenários de diagnóstico.
- `Tests/TestUsbBackup.ps1`: cópia, assinaturas, destino inseguro e interrupção.
- `Tests/TestUsbRecovery.ps1`: cópia, interrupção, espaço insuficiente e validação.

## Portão de aceite da v1

A funcionalidade somente será considerada pronta quando:

- cada resultado puder explicar por que recebeu aquela classificação;
- arquivos originais permanecerem inalterados nos testes de diagnóstico;
- toda escrita tiver plano, confirmação e registro;
- falhas e remoção inesperada da unidade forem tratadas sem corromper a origem;
- os testes reproduzirem unidades saudáveis, incompletas, incompatíveis e corrompidas;
- a interface não prometer recuperação ou compatibilidade além do que foi comprovado.
