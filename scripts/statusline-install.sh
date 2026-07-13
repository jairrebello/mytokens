#!/bin/bash
# Instala o hook statusLine do MyTokens — a ÚNICA fonte do "quanto resta" do Claude.
#
#   ./scripts/statusline-install.sh            instala
#   ./scripts/statusline-uninstall.sh          desfaz, byte a byte
#
# O MyTokens.app faz a MESMA coisa por um botão ("conectar" na pista do Claude), e lá ele
# mostra o diff antes de escrever. Este script é o caminho de quem prefere o terminal —
# os dois geram o MESMO wrapper, byte a byte, no MESMO lugar. Não são dois mundos.
#
# ─────────────────────────────────────────────────────────────────────────────
# O QUE ISTO ESCREVE NA SUA CASA (é tudo, e é só isto):
#
#   ~/.mytokens/statusline.sh          ← NOVO. O wrapper.
#   ~/.claude/settings.json            ← UMA linha muda: statusLine.command
#   ~/.mytokens/backups/settings-*.json ← cópia do seu settings.json ANTES da mudança
#   ~/.mytokens/inserted-block.txt     ← só se você NÃO tinha statusLine (ver abaixo)
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
BLOCO="$MYDIR/inserted-block.txt"

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
# Gerado em python, não em heredoc de bash, por DOIS motivos:
#
#   1. A aspa simples. Um statusLine com uma aspa no meio (um `awk '{...}'`, digamos) faria
#      `ORIGINAL='...'` explodir — e a statusline do usuário sumiria por causa da NOSSA
#      citação preguiçosa. Aqui a aspa é escapada com o truque do '\'' , sempre.
#   2. Byte a byte igual ao que o MyTokens.app gera (App/StatusLineHook.swift,
#      `wrapperSource`). Dois instaladores que produzem arquivos DIFERENTES são dois bugs
#      esperando a vez.
python3 - "$WRAPPER" "$ORIGINAL" <<'PY'
import sys
wrapper, original = sys.argv[1], sys.argv[2]
shq = "'" + original.replace("'", "'\\''") + "'"
open(wrapper, "w").write(f"""#!/bin/sh
# GERADO PELO MyTokens. Não edite à mão — reinstalar sobrescreve.
#
# O Claude Code entrega o JSON da statusline no stdin. Dentro dele vem `rate_limits`,
# que é o ÚNICO lugar do mundo onde existe o "quanto resta" do Claude — ele não é
# gravado em disco nenhum. Este script guarda esse JSON e passa a bola adiante, intacta.
#
# Ele NÃO chama o MyTokens.app. Apague o app, mova o app, jogue o Mac pela janela: a
# sua statusline continua desenhando exatamente como antes.

# MYTOKENS_SNAP existe pro INSTALADOR poder testar este script sem contaminar o arquivo
# de verdade. Um teste que grava um número inventado no lugar onde o app lê a verdade
# não é um teste — é o bug que ele deveria pegar.
SNAP="${{MYTOKENS_SNAP:-$HOME/Library/Application Support/MyTokens/statusline.json}}"
input=$(cat)

# Despejo. Falha aqui NUNCA derruba a statusline: se der errado, segue o baile.
{{
  mkdir -p "$(dirname "$SNAP")" && \\
  printf '%s' "$input" > "$SNAP.tmp" && mv -f "$SNAP.tmp" "$SNAP"
}} 2>/dev/null || true

# O SEU comando, com o MESMO stdin, stdout e código de saída.
ORIGINAL={shq}
[ -n "$ORIGINAL" ] || exit 0
printf '%s' "$input" | eval "$ORIGINAL"
""")
PY
chmod +x "$WRAPPER"

# ── 3. TESTA o wrapper ANTES de mexer no settings.json ──────────────────────
# Trocar a config e SÓ ENTÃO descobrir que o wrapper está quebrado é deixar o usuário sem
# statusline. O teste é a diferença entre uma instalação e uma aposta.
#
# MAS: O SEU COMANDO NUNCA É EXECUTADO COM DADO INVENTADO.
#
# A versão anterior deste teste rodava o wrapper INTEIRO — que chama o seu statusLine — com
# um payload sintético (42,5%, sessão "teste"). O despejo do MyTokens estava protegido (ia
# pra um mktemp), mas o que corre RIO ABAIXO não estava: o statusLine de uma pessoa é um
# programa qualquer, e programas escrevem. O do Jair grava um arquivo-ponte a cada turno
# (~/.claude/hooks/gsd-statusline.js:342). Ali o estrago foi nulo por SORTE — o caminho é
# chaveado pelo session_id, e "teste" não colide com UUID nenhum. Se aquele script gravasse
# num caminho FIXO (um cache, um log, um arquivo de estado), instalar o MyTokens teria
# enfiado um 42,5% inventado lá dentro.
#
# Escrever um número que ninguém mediu, onde outra coisa lê a verdade, é a mentira exata que
# este app existe pra não contar. O instalador não vai ser o primeiro a contá-la.
echo "==> testando o wrapper (sem tocar no settings.json ainda)"

# ATO 1 — a sintaxe, sem executar NADA. É o que pega o modo de falha real: uma aspa simples
# no seu comando estourando a citação (era o bug de verdade daqui).
if ! sh -n "$WRAPPER" 2>/tmp/mytokens-shn.$$; then
  echo "✗ o wrapper não é shell válido — a citação do SEU comando quebrou:"
  sed 's/^/    /' /tmp/mytokens-shn.$$ ; rm -f /tmp/mytokens-shn.$$
  echo "  NADA foi alterado no settings.json. Isto é bug NOSSO — reporte."
  exit 1
fi
rm -f /tmp/mytokens-shn.$$
echo "    ✓ sintaxe do wrapper ok (seu comando citado corretamente)"

# ATO 2 — o NOSSO cano, sozinho: uma cópia do wrapper com o comando de baixo VAZIO. Prova o
# despejo, o mkdir -p, a escrita atômica e o código de saída, sem tocar numa linha do seu
# programa.
PROVA='{"hook_event_name":"Status","session_id":"smoke","rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":9999999999}}}'
FALSO="$(mktemp)"
COPIA="$(mktemp)"
trap 'rm -f "$FALSO" "$COPIA"' EXIT

sed "s|^ORIGINAL=.*|ORIGINAL=''|" "$WRAPPER" > "$COPIA"
chmod +x "$COPIA"

set +e
printf '%s' "$PROVA" | MYTOKENS_SNAP="$FALSO" "$COPIA" >/dev/null 2>&1
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
[ -n "$ORIGINAL" ] && echo "    ℹ seu comando NÃO foi executado aqui (nenhum dado falso passou"
[ -n "$ORIGINAL" ] && echo "      por ele). O primeiro turno real do Claude Code é que o exercita."

# ── 4. settings.json — troca CIRÚRGICA de uma string só ─────────────────────
STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUPS/settings-$STAMP.json"

python3 - "$SETTINGS" "$WRAPPER" "$BLOCO" <<'PY'
import json, os, sys, tempfile
settings, wrapper, bloco_path = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(settings).read()
d = json.loads(raw)
sl = d.get("statusLine")
atual = (sl or {}).get("command", "")

# `ensure_ascii=False`: o arquivo foi escrito pelo Claude Code, que grava UTF-8 cru. Se eu
# procurasse \uXXXX num arquivo que tem "é", não acharia nada — e trocaria a coisa errada,
# ou nenhuma. (O MyTokens.app usa a mesma regra em StatusLineHook.jsonLiteral.)
lit = lambda s: json.dumps(s, ensure_ascii=False)

if atual == wrapper:
    print("    (settings.json já apontava pro wrapper — nada a fazer)")
    sys.exit(0)

if atual:
    # Substitui APENAS o valor da string, no texto cru. O resto do arquivo — indentação,
    # ordem das chaves, e TODA chave que eu não conheço — fica byte a byte igual.
    alvo, novo = lit(atual), lit(wrapper)
    if raw.count(alvo) != 1:
        print(f"    ✗ esperava achar exatamente 1 ocorrência do comando atual, achei {raw.count(alvo)}")
        sys.exit(1)
    novo_raw = raw.replace(alvo, novo)
    if os.path.exists(bloco_path):
        os.remove(bloco_path)     # marcador velho mente; some
elif sl is None:
    # Você não tem statusLine. Então o bloco INTEIRO é inserido — e os bytes exatos que
    # entraram ficam guardados, porque desfazer "mais ou menos" não é desfazer.
    virgula = "" if not d else ","      # objeto vazio não leva vírgula: ela sobraria
    bloco = ('\n  "statusLine": {\n    "type": "command",\n'
             f'    "command": {lit(wrapper)}\n  }}{virgula}')
    i = raw.index("{")
    novo_raw = raw[:i + 1] + bloco + raw[i + 1:]
    open(bloco_path, "w").write(bloco)
else:
    print("    ✗ você tem um bloco `statusLine` sem `command`. Não sei mexer nisso sem")
    print("      adivinhar, e adivinhar na configuração dos outros não é coisa que eu faça.")
    sys.exit(1)

json.loads(novo_raw)              # não escrevo JSON quebrado na casa de ninguém

# Atômico: temp + rename, no MESMO diretório. Nunca truncar por cima — se a máquina cair no
# meio, o usuário fica com o arquivo velho INTEIRO, não com meio arquivo.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(settings), prefix=".settings-", suffix=".tmp")
os.write(fd, novo_raw.encode())
os.close(fd)
os.chmod(tmp, os.stat(settings).st_mode & 0o777)
os.replace(tmp, settings)
print("    ✓ statusLine.command " + ("inserido" if not atual else "trocado"))
PY

echo
echo "==> pronto. Backup em $BACKUPS/settings-$STAMP.json"
echo "    Desfazer:  ./scripts/statusline-uninstall.sh"
echo
echo "    O número do 'quanto resta' aparece no MyTokens no PRÓXIMO turno do Claude Code"
echo "    (o hook só dispara quando a statusline é redesenhada)."
