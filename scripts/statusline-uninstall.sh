#!/bin/bash
# Desfaz o statusline-install.sh. Devolve o settings.json ao comando de antes.
#
# Este script foi escrito ANTES do instalador rodar pela primeira vez. Um caminho de volta
# que nunca foi testado não é um caminho de volta — é uma intenção.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
MYDIR="$HOME/.mytokens"
WRAPPER="$MYDIR/statusline.sh"
BACKUPS="$MYDIR/backups"
BLOCO="$MYDIR/inserted-block.txt"

[ -f "$SETTINGS" ] || { echo "✗ não achei $SETTINGS"; exit 1; }

ORIGINAL="$(cat "$MYDIR/original-command.txt" 2>/dev/null || true)"

# Backup ANTES de desfazer. Sim: desfazer também é MEXER, e mexer sem rede é aposta.
mkdir -p "$BACKUPS"
cp "$SETTINGS" "$BACKUPS/settings-$(date +%Y%m%d-%H%M%S)-pre-uninstall.json"

python3 - "$SETTINGS" "$WRAPPER" "$ORIGINAL" "$BLOCO" <<'PY'
import json, os, sys, tempfile
settings, wrapper, original, bloco_path = sys.argv[1:5]
raw = open(settings).read()
d = json.loads(raw)
atual = (d.get("statusLine") or {}).get("command", "")
lit = lambda s: json.dumps(s, ensure_ascii=False)

if atual != wrapper:
    print(f"==> o statusLine NÃO aponta pro MyTokens (é: {atual or 'vazio'}). Nada a desfazer.")
    sys.exit(0)

if original:
    alvo, novo = lit(atual), lit(original)
    if raw.count(alvo) != 1:
        print(f"✗ esperava 1 ocorrência do wrapper no texto, achei {raw.count(alvo)}. Não mexo.")
        sys.exit(1)
    novo_raw = raw.replace(alvo, novo)
    print(f"==> statusLine devolvido para: {original}")
else:
    # Você não tinha statusLine: a gente INSERIU um bloco. Agora tira EXATAMENTE os bytes que
    # entraram — é pra isso que eles foram guardados. Remover "mais ou menos" deixaria uma
    # vírgula órfã ou uma linha em branco onde antes não havia nada.
    bloco = open(bloco_path).read() if os.path.exists(bloco_path) else ""
    if not bloco or raw.count(bloco) != 1:
        print("✗ você não tinha statusLine antes, e eu não acho mais o bloco exato que inseri.")
        print("  Restaure à mão de ~/.mytokens/backups/ — os backups estão todos lá.")
        sys.exit(1)
    novo_raw = raw.replace(bloco, "")
    print("==> bloco statusLine removido (você não tinha um antes).")

json.loads(novo_raw)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(settings), prefix=".settings-", suffix=".tmp")
os.write(fd, novo_raw.encode())
os.close(fd)
os.chmod(tmp, os.stat(settings).st_mode & 0o777)
os.replace(tmp, settings)
PY

rm -f "$WRAPPER" "$BLOCO"
echo "==> wrapper removido."
echo "    O despejo em ~/Library/Application Support/MyTokens/ ficou (é DADO SEU, não lixo)."
echo "    Pra apagar também:  rm -rf ~/Library/Application\\ Support/MyTokens"
echo
echo "    O MyTokens volta a dizer 'não sei quanto sobra' — que continua sendo verdade."
