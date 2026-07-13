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
# `xcodebuild | grep … || true` devolve o status do GREP, não o do xcodebuild — um
# BUILD FAILED passava batido aqui. E o `[ -d "$BUILT" ]` lá embaixo NÃO pegava: quando a
# compilação quebra, o xcodebuild deixa pra trás o esqueleto do bundle (Info.plist no
# lugar, Contents/MacOS/ VAZIO). O teste de diretório passava e o install.sh copiava por
# cima do /Applications/MyTokens.app que funcionava uma CASCA SEM BINÁRIO — trocando um
# app bom por um que não abre, e dizendo "instalado". Peguei isto rodando o release.sh.
set +e
xcodebuild -project MyTokens.xcodeproj \
           -scheme MyTokens \
           -configuration Release \
           build 2>&1 | grep -E "error:|warning:|BUILD"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
[ "$BUILD_STATUS" -eq 0 ] || {
  echo "✗ BUILD FAILED (xcodebuild saiu $BUILD_STATUS) — nada foi instalado."
  echo "  O que está em /Applications continua intacto."
  exit 1
}

BUILT="$(xcodebuild -project MyTokens.xcodeproj -scheme MyTokens -configuration Release \
          -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/MyTokens.app"

[ -d "$BUILT" ] || { echo "✗ não achei o app em $BUILT"; exit 1; }
[ -x "$BUILT/Contents/MacOS/MyTokens" ] || {
  echo "✗ $BUILT não tem executável dentro — é casca, não app. Nada foi instalado."
  exit 1
}

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
