# Segurança

## Versões suportadas

Durante o beta fechado, apenas a versão mais recente recebe correções de segurança.

## Como relatar uma vulnerabilidade

Não abra uma issue pública com chaves, bancos, links privados, cookies ou caminhos pessoais. Use o canal privado de contato do mantenedor no GitHub e inclua apenas o mínimo necessário para reproduzir o problema.

O diagnóstico gerado pelo aplicativo remove caminhos do perfil, parâmetros sensíveis de URLs e tokens conhecidos. Mesmo assim, revise o arquivo antes de compartilhá-lo.

## Modelo de segurança

- a análise é somente leitura;
- copiar é o modo padrão de organização;
- mover exige confirmação explícita;
- a escrita no Rekordbox exige que os processos estejam fechados;
- o banco é copiado antes da transação e restaurado se a verificação falhar;
- segredos e preferências do usuário não pertencem ao repositório.

