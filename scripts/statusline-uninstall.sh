#!/bin/bash
# Desfaz o statusline-install.sh. Devolve o settings.json ao comando de antes.
#
# Este script foi escrito ANTES do instalador rodar pela primeira vez. Um caminho de volta
# que nunca foi testado não é um caminho de volta — é uma intenção.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
MYDIR="$HOME/.mytokens"
WRAPPER="$MYDIR/statusline.sh"

[ -f "$SETTINGS" ] || { echo "✗ não achei $SETTINGS"; exit 1; }

ORIGINAL="$(cat "$MYDIR/original-command.txt" 2>/dev/null || true)"

python3 - "$SETTINGS" "$WRAPPER" "$ORIGINAL" <<'PY'
import json, sys
settings, wrapper, original = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(settings).read()
d = json.loads(raw)
atual = (d.get("statusLine") or {}).get("command", "")

if atual != wrapper:
    print(f"==> o statusLine NÃO aponta pro MyTokens (é: {atual or 'vazio'}). Nada a desfazer.")
    sys.exit(0)

if not original:
    print("✗ não sei qual era o seu comando original (~/.mytokens/original-command.txt sumiu).")
    print("  Restaure à mão de ~/.mytokens/backups/ — os backups estão todos lá.")
    sys.exit(1)

alvo, novo = json.dumps(atual), json.dumps(original)
assert raw.count(alvo) == 1
novo_raw = raw.replace(alvo, novo)
json.loads(novo_raw)
open(settings, "w").write(novo_raw)
print(f"==> statusLine devolvido para: {original}")
PY

rm -f "$WRAPPER"
echo "==> wrapper removido."
echo "    O despejo em ~/Library/Application Support/MyTokens/ ficou (é DADO SEU, não lixo)."
echo "    Pra apagar também:  rm -rf ~/Library/Application\\ Support/MyTokens"
echo
echo "    O MyTokens volta a dizer 'não sei quanto sobra' — que continua sendo verdade."
