#!/bin/bash
# Instala o MyTokens em /Applications.
#
# POR QUE ISTO EXISTE: um app que só roda de dentro do DerivedData não é um app instalado.
# O macOS SE RECUSA a registrá-lo pra abrir no login (SMAppService devolve `.notFound`), o
# caminho dele muda a cada build, e ele some quando o Xcode limpa o cache. Enquanto o app
# morar lá, ele é um binário de teste — não um programa.
#
#   ./scripts/install.sh            instala (ou atualiza) e abre
#   ./scripts/install.sh --no-open  só instala
#
# ASSINATURA: hoje é ad-hoc (CODE_SIGN_IDENTITY = "-"). Serve pra rodar NESTA máquina.
# Pra distribuir a outra pessoa é preciso Developer ID + notarização (docs/… e uma conta
# paga da Apple) — não tem identidade de assinatura instalada aqui, e sem ela o Gatekeeper
# barra o app na máquina do outro. Este script não finge o contrário.
set -euo pipefail

cd "$(dirname "$0")/.."

DEST="/Applications/MyTokens.app"

echo "==> compilando (Release)"
xcodebuild -project MyTokens.xcodeproj \
           -scheme MyTokens \
           -configuration Release \
           build 2>&1 | grep -E "error:|warning:|BUILD" || true

BUILT="$(xcodebuild -project MyTokens.xcodeproj -scheme MyTokens -configuration Release \
          -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/MyTokens.app"

[ -d "$BUILT" ] || { echo "✗ não achei o app em $BUILT"; exit 1; }

# O app rodando segura o próprio bundle. Fecha antes de trocar o binário debaixo dele.
if pgrep -f "MyTokens.app/Contents/MacOS/MyTokens" > /dev/null; then
  echo "==> fechando a versão que está rodando"
  pkill -f "MyTokens.app/Contents/MacOS/MyTokens" || true
  sleep 1
fi

echo "==> instalando em $DEST"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

# Sem isto o Gatekeeper trata a cópia como "baixada da internet" e mostra o susto.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?') instalado"

if [ "${1:-}" != "--no-open" ]; then
  open "$DEST"
  echo "==> aberto. O ícone está na barra de menu (o app não tem Dock — é LSUIElement)."
  echo "    'Abrir no login' agora funciona: está no menu ⋯ do rodapé do popover."
fi
