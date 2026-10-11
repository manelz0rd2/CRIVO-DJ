# CRIVO DJ para macOS

Porte independente do CRIVO DJ para macOS. A versão Windows permanece intacta na pasta
`CRIVO DJ`.

## Escolha do pacote

- `CRIVO-DJ-macOS-Apple-Silicon.zip`: Macs com processador da linha M, como M1, M2, M3, M4 ou mais recente;
- `CRIVO-DJ-macOS-Intel.zip`: Macs anteriores com processador Intel.

O usuário final só precisa extrair o ZIP e abrir `CRIVO DJ.app`. Na primeira execução,
deve clicar com o botão direito no aplicativo, escolher **Abrir** e confirmar.

## Estado

Esta base já inclui:

- interface nativa baseada em Qt;
- fila de links do YouTube, SoundCloud e Spotify;
- leitura e organização de arquivos de áudio existentes;
- descoberta automática do `master.db` do Rekordbox 6/7 no macOS;
- auditoria somente leitura da biblioteca;
- criação ou atualização de playlist diretamente no banco;
- bloqueio da escrita enquanto Rekordbox ou rekordboxAgent estiverem abertos;
- backup verificado, transação, conferência posterior e restauração automática em caso de falha.

## Executar durante o desenvolvimento

Requer macOS 12 ou mais recente e Python 3.11 ou 3.12.

```bash
cd "CRIVO DJ macOS"
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m crivo_dj
```

O FFmpeg é empacotado junto com as dependências da aplicação. O usuário final não
precisa instalar Homebrew, Python ou ferramentas adicionais depois que o `.app` estiver
montado.

## Gerar o aplicativo

```bash
chmod +x scripts/build_macos.sh
./scripts/build_macos.sh
```

O resultado será criado em `dist/CRIVO DJ.app`. O build precisa acontecer no macOS;
PyInstaller não produz um aplicativo macOS a partir do Windows.

## Testes

```bash
PYTHONPATH=src python -m pytest -q
```

Para testar leitura e escrita numa cópia isolada de uma biblioteca real:

```bash
export CRIVO_REKORDBOX_TEST_DB="$HOME/Library/Application Support/Pioneer/rekordbox/master.db"
PYTHONPATH=src python -m pytest -q tests/test_rekordbox_sandbox.py
```

Esse teste copia o banco para um diretório temporário, cria uma playlist, repete a
operação para verificar que não há duplicação e compara o hash do banco real antes e
depois.

## Rekordbox

O CRIVO procura o banco nos diretórios padrão dentro de
`~/Library/Application Support/Pioneer` e também consulta o `options.json` do
rekordboxAgent. Uma localização diferente pode ser escolhida manualmente.

A auditoria é somente leitura. Para escrever uma playlist, Rekordbox e rekordboxAgent
precisam estar fechados. O CRIVO cria uma cópia dos arquivos do banco em
`~/Library/Application Support/CRIVO DJ/Backups/Rekordbox` antes de iniciar.

