#!/bin/bash
# Compila, assina, notariza e empacota o MyTokens num DMG que abre na máquina DOS OUTROS.
#
# POR QUE ISTO EXISTE: o install.sh resolve "o app roda AQUI". Ele não resolve "o app roda
# LÁ". Entre os dois tem o Gatekeeper, e o Gatekeeper não negocia: um .app assinado ad-hoc
# (CODE_SIGN_IDENTITY = "-", que é o que este projeto usa hoje) baixado da internet abre na
# máquina do outro com "«MyTokens» está danificado e não pode ser aberto. Mova-o para o
# Lixo." — a mensagem mente sobre a causa, o usuário acredita nela, e o app morre ali.
#
# REGRA DURA DESTE SCRIPT: ele NUNCA produz um DMG ad-hoc fingindo que dá pra distribuir.
# Sem identidade de assinatura ou sem credencial de notarização, ele FALHA e diz o que
# falta. Um artefato que o Gatekeeper barra é PIOR que artefato nenhum — porque parece
# pronto. O DMG que sai daqui ou passa no `spctl`, ou não existe.
#
#   ./scripts/release.sh            release de verdade: assina + notariza + DMG
#   ./scripts/release.sh --check    só o diagnóstico: o que tenho, o que falta. Não compila.
#   ./scripts/release.sh --local    DMG NÃO-ASSINADO, explicitamente só pra esta máquina
#
# ─────────────────────────────────────────────────────────────────────────────
# O QUE ELE PRECISA (e que hoje, 2026-07-13, esta máquina NÃO tem):
#
#   SIGN_IDENTITY   nome do cert "Developer ID Application: Fulano (TEAMID)".
#                   Se não passar, o script procura sozinho no chaveiro.
#   TEAM_ID         os 10 caracteres do Team ID. Se não passar, é extraído do parêntese
#                   do nome da identidade.
#   NOTARY_PROFILE  nome do perfil do notarytool guardado no chaveiro (default: mytokens).
#                   Alternativa: APPLE_ID + APPLE_PASSWORD (app-specific) + TEAM_ID.
#
# Nada disso é hardcodado. Nenhum Team ID mora neste repositório.
# O passo a passo pra obter cada um: docs/DISTRIBUICAO.md
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="release"
case "${1:-}" in
  --check) MODE="check" ;;
  --local) MODE="local" ;;
  "")      MODE="release" ;;
  *) echo "uso: $0 [--check|--local]" >&2; exit 2 ;;
esac

NOTARY_PROFILE="${NOTARY_PROFILE:-mytokens}"
DIST="dist"
DD="$DIST/DerivedData"          # DerivedData própria: caminho previsível, build limpo.
STAGE="$DIST/stage"             # o que vira o DMG.

# ─── diagnóstico: o que existe nesta máquina, agora ──────────────────────────
# Rodado ANTES de compilar. Descobrir que falta o certificado depois de 2 minutos de
# xcodebuild é desrespeito com quem está esperando.

find_identity() {
  # O nome exato do cert, sem o hash e sem as aspas. Vazio se não houver nenhum.
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
    | head -1
}

explique_falta_de_identidade() {
  cat >&2 <<'FIM'

✗ NÃO HÁ IDENTIDADE "Developer ID Application" NESTE CHAVEIRO.

  Sem ela não existe release distribuível. Não é um passo que dá pra pular, contornar
  ou fingir: o Gatekeeper valida a assinatura contra a Apple, e a Apple só emite esse
  certificado pra quem tem conta paga.

  O QUE PROVA QUE FALTA:
      $ security find-identity -v -p codesigning
      0 valid identities found

  O QUE FAZER (nesta ordem — o 1 custa dinheiro, o resto custa 15 minutos):

  1. Conta no Apple Developer Program — US$ 99/ano.
         https://developer.apple.com/programs/enroll/
     (A conta grátis NÃO serve: ela só emite "Apple Development", que assina pra rodar
      na sua máquina — exatamente o que o ad-hoc já faz. Ela não emite Developer ID.)

  2. Criar o certificado "Developer ID Application":
         Xcode → Settings → Accounts → (sua conta) → Manage Certificates
         → botão +  → "Developer ID Application"
     Ele nasce direto no chaveiro. Confira:
         $ security find-identity -v -p codesigning     # tem que listar 1 valid identity

  3. Guardar a credencial de notarização (uma vez só, fica no chaveiro):
         $ xcrun notarytool store-credentials "mytokens" \
             --apple-id "voce@exemplo.com" \
             --team-id "SEUTEAMID" \
             --password "xxxx-xxxx-xxxx-xxxx"    # app-specific, de appleid.apple.com
     A senha NÃO é a do Apple ID. É uma app-specific password:
         https://account.apple.com  → Sign-In and Security → App-Specific Passwords

  4. Rodar de novo:  ./scripts/release.sh

  Enquanto isso, pra usar o app AQUI:   ./scripts/install.sh
  E pra gerar um DMG que só serve AQUI: ./scripts/release.sh --local
  Detalhes: docs/DISTRIBUICAO.md
FIM
}

explique_falta_de_notarizacao() {
  cat >&2 <<FIM

✗ TENHO O CERTIFICADO, MAS NÃO TENHO CREDENCIAL DE NOTARIZAÇÃO VÁLIDA.

  Assinar sem notarizar não resolve. Desde o macOS 10.15 o Gatekeeper exige o TICKET da
  Apple, não só a assinatura: um .app assinado e não-notarizado, baixado da internet,
  ainda é barrado. Meio caminho aqui vale zero.

  O QUE PROVA QUE FALTA:
      \$ xcrun notarytool history --keychain-profile "$NOTARY_PROFILE"
      (erro de autenticação, ou o perfil não existe)

  O QUE FAZER — guarde a credencial no chaveiro, uma vez só:
      \$ xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
          --apple-id "voce@exemplo.com" \\
          --team-id "\${TEAM_ID:-SEUTEAMID}" \\
          --password "xxxx-xxxx-xxxx-xxxx"

  A senha é uma APP-SPECIFIC PASSWORD (não a senha do Apple ID), criada em:
      https://account.apple.com → Sign-In and Security → App-Specific Passwords

  Ou, sem chaveiro, exporte no ambiente:
      \$ APPLE_ID=... APPLE_PASSWORD=... TEAM_ID=... ./scripts/release.sh

  Detalhes: docs/DISTRIBUICAO.md
FIM
}

# Monta os argumentos de autenticação do notarytool e PROVA que eles funcionam.
# Não basta o perfil existir: perfil com senha revogada existe e não autentica.
notary_args() {
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${TEAM_ID:-}" ]; then
    printf '%s\n' --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$TEAM_ID"
  else
    printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
  fi
}

notary_ok() {
  local args=(); while IFS= read -r a; do args+=("$a"); done < <(notary_args)
  xcrun notarytool history "${args[@]}" --output-format json >/dev/null 2>&1
}

# ─── --check / preflight ─────────────────────────────────────────────────────
SIGN_IDENTITY="${SIGN_IDENTITY:-$(find_identity)}"

if [ "$MODE" = "check" ]; then
  echo "==> diagnóstico de release — $(date '+%Y-%m-%d %H:%M')"
  echo
  if [ -n "$SIGN_IDENTITY" ]; then
    echo "  ✓ identidade de assinatura: $SIGN_IDENTITY"
  else
    echo "  ✗ identidade de assinatura: NENHUMA (security find-identity -v -p codesigning)"
  fi
  if notary_ok; then
    echo "  ✓ credencial de notarização: autentica (notarytool history respondeu)"
  else
    echo "  ✗ credencial de notarização: não autentica (perfil '$NOTARY_PROFILE' ausente ou inválido)"
  fi
  echo
  if [ -n "$SIGN_IDENTITY" ] && notary_ok; then
    echo "  → dá pra distribuir. Rode: ./scripts/release.sh"
    exit 0
  fi
  echo "  → NÃO dá pra distribuir. Veja docs/DISTRIBUICAO.md."
  echo "    Build local (só esta máquina): ./scripts/release.sh --local"
  exit 1
fi

if [ "$MODE" = "release" ]; then
  [ -n "$SIGN_IDENTITY" ] || { explique_falta_de_identidade; exit 1; }

  # Team ID: do ambiente, ou do parêntese do nome do cert — "…: Fulano (A1B2C3D4E5)".
  if [ -z "${TEAM_ID:-}" ]; then
    TEAM_ID="$(printf '%s' "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
  fi
  [ -n "$TEAM_ID" ] || {
    echo "✗ não consegui extrair o TEAM_ID de '$SIGN_IDENTITY'. Passe TEAM_ID=... no ambiente." >&2
    exit 1
  }

  echo "==> credencial de notarização: verificando ANTES de compilar"
  notary_ok || { explique_falta_de_notarizacao; exit 1; }
  echo "    ✓ autentica"
fi

# ─── build ───────────────────────────────────────────────────────────────────
rm -rf "$DIST"
mkdir -p "$STAGE"

XCARGS=(-project MyTokens.xcodeproj -scheme MyTokens -configuration Release
        -derivedDataPath "$DD")

if [ "$MODE" = "release" ]; then
  echo "==> compilando (Release) e assinando com: $SIGN_IDENTITY"
  # Os overrides vão na LINHA DE COMANDO de propósito: é a precedência mais alta do
  # xcodebuild, ganha do CODE_SIGN_IDENTITY = "-" que está no alvo, e não exige tocar no
  # pbxproj. O build ad-hoc de todo dia continua byte a byte o que era.
  # --timestamp: sem timestamp seguro a notarização é RECUSADA.
  # ENABLE_HARDENED_RUNTIME já é YES no projeto; fica explícito porque é requisito.
  # CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: xcodebuild sem archive injeta get-task-allow
  # (entitlement de debug) nos base entitlements. A Apple recusa notarização com ele
  # presente — "The executable requests the com.apple.security.get-task-allow entitlement".
  XCARGS+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
           DEVELOPMENT_TEAM="$TEAM_ID"
           CODE_SIGN_STYLE=Manual
           ENABLE_HARDENED_RUNTIME=YES
           CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
           OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
else
  echo "==> compilando (Release) SEM assinatura de distribuição — modo --local"
  # Nenhum override: é exatamente o build de hoje, ad-hoc.
fi

# O STATUS DO XCODEBUILD, E NÃO O DO GREP. Este cuidado não é paranoia de estilo — foi
# bug real neste script, pego na primeira execução: `xcodebuild | grep … || true` devolve o
# status do GREP, o `|| true` engole o resto, e um BUILD FAILED passava batido. O script
# seguia em frente, encontrava o esqueleto do .app que o xcodebuild deixa pra trás (bundle
# montado, Info.plist no lugar, Contents/MacOS/ VAZIO) e empacotava aquilo num DMG,
# anunciando sucesso. Um DMG com um app sem binário dentro. Exatamente o tipo de artefato
# que este script existe pra não produzir.
set +e
xcodebuild "${XCARGS[@]}" clean build 2>&1 | tee "$DIST/build.log" | grep -E "error:|warning:|BUILD"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
[ "$BUILD_STATUS" -eq 0 ] || {
  echo >&2
  echo "✗ BUILD FAILED (xcodebuild saiu $BUILD_STATUS). Log completo: $DIST/build.log" >&2
  echo "  Nenhum DMG foi gerado — um app que não compila não vira release." >&2
  exit 1
}

APP="$DD/Build/Products/Release/MyTokens.app"
[ -d "$APP" ] || { echo "✗ não achei o app em $APP" >&2; exit 1; }
# Cinto e suspensório: bundle sem executável dentro é casca. Já aconteceu (ver acima).
[ -x "$APP/Contents/MacOS/MyTokens" ] || {
  echo "✗ $APP não tem executável em Contents/MacOS/ — é uma casca, não um app." >&2
  exit 1
}

VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
DMG="$DIST/MyTokens-$VERSION.dmg"
echo "==> MyTokens $VERSION"

# ─── modo --local: DMG que NÃO sai desta máquina ─────────────────────────────
if [ "$MODE" = "local" ]; then
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "MyTokens $VERSION" -srcfolder "$STAGE" \
                 -ov -format UDZO -quiet "$DMG"
  rm -rf "$STAGE"
  cat <<FIM

  ⚠  DMG LOCAL — NÃO DISTRIBUÍVEL:  $DMG

  Este DMG contém um app assinado AD-HOC. Ele funciona nesta máquina e SÓ nesta máquina.
  Em qualquer outro Mac o Gatekeeper vai barrar — provavelmente com a mensagem mentirosa
  "está danificado e não pode ser aberto".

  NÃO mande este arquivo pra ninguém. Ele parece um release e não é.
  Pra fazer um que preste: ./scripts/release.sh (requer Developer ID — docs/DISTRIBUICAO.md)
FIM
  exit 0
fi

# ─── assinatura: verificar o que o xcodebuild fez ────────────────────────────
echo "==> verificando a assinatura do .app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|flags"

# ─── notarização, passo 1: o .app ────────────────────────────────────────────
# POR QUE NOTARIZAR O APP E O DMG (duas idas à Apple, e não uma):
# grampear só o DMG deixa o .app SEM ticket próprio. Enquanto o usuário abre direto do
# DMG, tudo bem. Mas ele arrasta o app pra /Applications, e aí o app sozinho depende de
# consulta ONLINE ao ticket — primeira abertura offline falha. Grampear os dois custa uns
# minutos a mais e remove essa classe inteira de "às vezes não abre".
NOTARY=(); while IFS= read -r a; do NOTARY+=("$a"); done < <(notary_args)

ZIP="$DIST/MyTokens-$VERSION.zip"
echo "==> notarizando o .app (isto conversa com a Apple; costuma levar 1-5 min)"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"     # ditto, não zip: preserva a assinatura.
xcrun notarytool submit "$ZIP" "${NOTARY[@]}" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# ─── DMG ─────────────────────────────────────────────────────────────────────
echo "==> montando o DMG"
cp -R "$APP" "$STAGE/"                  # o app JÁ grampeado.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MyTokens $VERSION" -srcfolder "$STAGE" \
               -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "==> assinando o DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "==> notarizando o DMG"
xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait
xcrun stapler staple "$DMG"

# ─── a prova ─────────────────────────────────────────────────────────────────
# Se qualquer uma destas falhar, o `set -e` mata o script e o DMG não é anunciado como
# pronto. É o ponto inteiro: o artefato só existe se o Gatekeeper concordar que existe.
echo
echo "==> PROVA (é isto que a máquina do outro vai rodar)"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl -a -vvv "$APP"
spctl -a -vvv -t open --context context:primary-signature "$DMG"
codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "  ✓ $DMG  ($(du -h "$DMG" | cut -f1))"
echo "    assinado, notarizado, grampeado. Passa no Gatekeeper em máquina limpa."
echo "    Confira você mesmo, do outro lado:  spctl -a -vvv /Applications/MyTokens.app"
