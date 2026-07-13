#!/bin/bash
# Instala o hook statusLine do MyTokens — a ÚNICA fonte do "quanto resta" do Claude.
#
#   ./scripts/statusline-install.sh            instala
#   ./scripts/statusline-uninstall.sh          desfaz, byte a byte
#
# ─────────────────────────────────────────────────────────────────────────────
# O QUE ISTO ESCREVE NA SUA CASA (é tudo, e é só isto):
#
#   ~/.mytokens/statusline.sh          ← NOVO. O wrapper.
#   ~/.claude/settings.json            ← UMA linha muda: statusLine.command
#   ~/.mytokens/backups/settings-*.json ← cópia do seu settings.json ANTES da mudança
#
# NÃO toca no seu gsd-statusline.js. NÃO reformata o settings.json (a troca é cirúrgica,
# só a string do comando muda — as outras 180 linhas ficam byte a byte iguais).
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUE O WRAPPER É UM SHELL SCRIPT E NÃO UM BINÁRIO NOSSO:
#
# A objeção honesta contra este caminho (docs/STATUSLINE.md, opção A) era:
# "viramos ponto único de falha da statusline dele — se nosso binário travar ou demorar,
# a statusline some". Verdade. Então não existe binário nosso no caminho.
#
# O wrapper é um shell script de 5 linhas que despeja o stdin num arquivo e executa o SEU
# comando original, intacto, repassando stdout e código de saída. Ele NÃO depende do
# MyTokens.app existir. Desinstale o MyTokens, apague o app, jogue o Mac pela janela: a sua
# statusline continua funcionando exatamente como antes.
#
# O pior que pode acontecer é o despejo falhar (disco cheio, permissão) — e aí ele falha em
# SILÊNCIO, com `|| true`, e o seu comando roda mesmo assim. O app degrada pra "não sei
# quanto sobra", que é um estado que ele já sabe mostrar com honestidade. Nunca pra tela
# em branco.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
MYDIR="$HOME/.mytokens"
WRAPPER="$MYDIR/statusline.sh"
SNAP="$HOME/Library/Application Support/MyTokens/statusline.json"
BACKUPS="$MYDIR/backups"

[ -f "$SETTINGS" ] || { echo "✗ não achei $SETTINGS"; exit 1; }

# ── 1. Qual é o comando de hoje? ────────────────────────────────────────────
ORIGINAL="$(python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print((d.get("statusLine") or {}).get("command", ""))
PY
)"

if [ "$ORIGINAL" = "$WRAPPER" ]; then
  echo "==> o wrapper já está instalado. Regerando (idempotente)."
  ORIGINAL="$(cat "$MYDIR/original-command.txt" 2>/dev/null || true)"
elif [ -n "$ORIGINAL" ]; then
  echo "==> statusLine atual (será PRESERVADO e chamado pelo wrapper):"
  echo "    $ORIGINAL"
else
  echo "==> você não tem statusLine hoje. O wrapper só vai despejar o dado, sem imprimir nada."
fi

mkdir -p "$MYDIR" "$BACKUPS" "$(dirname "$SNAP")"
printf '%s' "$ORIGINAL" > "$MYDIR/original-command.txt"

# ── 2. O wrapper ────────────────────────────────────────────────────────────
cat > "$WRAPPER" <<WRAP
#!/bin/sh
# GERADO PELO MyTokens (scripts/statusline-install.sh). Não edite à mão.
#
# O Claude Code entrega o JSON da statusline no stdin. Dentro dele vem \`rate_limits\`,
# que é o ÚNICO lugar do mundo onde existe o "quanto resta" do Claude — ele não é gravado
# em disco nenhum. Este script guarda esse JSON e passa a bola adiante, intacta.

# MYTOKENS_SNAP existe pro INSTALADOR poder testar este script sem contaminar o arquivo
# de verdade. Um teste que grava um número inventado no lugar onde o app lê a verdade
# não é um teste — é o bug que ele deveria pegar.
SNAP="\${MYTOKENS_SNAP:-\$HOME/Library/Application Support/MyTokens/statusline.json}"
input=\$(cat)

# Despejo. Falha aqui NUNCA derruba a statusline: se der errado, segue o baile.
{
  mkdir -p "\$(dirname "\$SNAP")" && \\
  printf '%s' "\$input" > "\$SNAP.tmp" && mv -f "\$SNAP.tmp" "\$SNAP"
} 2>/dev/null || true

# O SEU comando, com o MESMO stdin, stdout e código de saída.
ORIGINAL='$ORIGINAL'
[ -n "\$ORIGINAL" ] || exit 0
printf '%s' "\$input" | eval "\$ORIGINAL"
WRAP
chmod +x "$WRAPPER"

# ── 3. TESTA o wrapper ANTES de mexer no settings.json ──────────────────────
# Trocar a config e SÓ ENTÃO descobrir que o wrapper está quebrado é deixar o usuário sem
# statusline. O teste é a diferença entre uma instalação e uma aposta.
echo "==> testando o wrapper (sem tocar no settings.json ainda)"
PROVA='{"hook_event_name":"Status","session_id":"teste","model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":9999999999}}}'

# O despejo do teste vai pra um arquivo DESCARTÁVEL. O payload acima é INVENTADO — se ele
# caísse no arquivo real, o app leria 42,5% e diria "medido" sobre um número que eu criei.
# Seria a mentira exata que este app existe pra não contar.
FALSO="$(mktemp)"
trap 'rm -f "$FALSO"' EXIT

set +e
SAIDA="$(printf '%s' "$PROVA" | MYTOKENS_SNAP="$FALSO" "$WRAPPER" 2>/dev/null)"
CODIGO=$?
set -e

if [ $CODIGO -ne 0 ]; then
  echo "✗ o wrapper saiu com código $CODIGO. NADA foi alterado no settings.json."
  exit 1
fi
if ! grep -q "rate_limits" "$FALSO" 2>/dev/null; then
  echo "✗ o wrapper não gravou o despejo, ou gravou sem rate_limits. NADA foi alterado."
  exit 1
fi
echo "    ✓ despejo gravado, rate_limits presente"
[ -n "$ORIGINAL" ] && echo "    ✓ seu comando rodou e imprimiu ${#SAIDA} caracteres"

# ── 4. settings.json — troca CIRÚRGICA de uma string só ─────────────────────
STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUPS/settings-$STAMP.json"

python3 - "$SETTINGS" "$WRAPPER" <<'PY'
import json, sys
settings, wrapper = sys.argv[1], sys.argv[2]
raw = open(settings).read()
d = json.loads(raw)
atual = (d.get("statusLine") or {}).get("command", "")

if atual == wrapper:
    print("    (settings.json já apontava pro wrapper — nada a fazer)")
    sys.exit(0)

# Substitui APENAS o valor da string, no texto cru. O resto do arquivo — indentação,
# ordem das chaves, comentários de espaçamento — fica byte a byte igual.
alvo = json.dumps(atual)          # a string COM as aspas e escapes, como está no arquivo
novo = json.dumps(wrapper)
if raw.count(alvo) != 1:
    print(f"    ✗ esperava achar exatamente 1 ocorrência do comando atual, achei {raw.count(alvo)}")
    sys.exit(1)

novo_raw = raw.replace(alvo, novo)
json.loads(novo_raw)              # não escrevo JSON quebrado na casa de ninguém
open(settings, "w").write(novo_raw)
print("    ✓ statusLine.command trocado")
PY

echo
echo "==> pronto. Backup em $BACKUPS/settings-$STAMP.json"
echo "    Desfazer:  ./scripts/statusline-uninstall.sh"
echo
echo "    O número do 'quanto resta' aparece no MyTokens no PRÓXIMO turno do Claude Code"
echo "    (o hook só dispara quando a statusline é redesenhada)."
