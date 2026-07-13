#!/bin/bash
# Bancada de screenshots. Abre a galeria num estado, espera assentar, recorta a
# janela pelo id (não por coordenada — coordenada quebra em monitor diferente).
#
#   ./shots.sh                 → todos os estados, dark e light
#   ./shots.sh popover dark    → um só
set -uo pipefail

BIN="$(swift build --show-bin-path)/MyTokensGallery"
OUT="$(cd "$(dirname "$0")" && pwd)/shots"
mkdir -p "$OUT"

shoot() {
  local shot="$1" mode="$2"
  local png="$OUT/${shot}-${mode}.png"
  local log; log="$(mktemp)"

  "$BIN" "$shot" "$mode" > "$log" 2>&1 &
  local pid=$!

  # o reset ANIMA por 1,5 s — capturar antes disso pegaria o meio do dreno
  local settle=1.6
  [ "$shot" = "reset" ] && settle=3.2

  local wid=""
  for _ in $(seq 1 40); do
    wid="$(grep -m1 '^WINDOW_ID' "$log" 2>/dev/null | awk '{print $2}')"
    [ -n "$wid" ] && break
    sleep 0.1
  done

  # `real` lê o disco de verdade: o primeiro scan varre ~1,4 GB e pode levar um minuto.
  # Capturar no relógio fotografaria o estado vazio e chamaria de real — espera o sinal.
  case "$shot" in real*)
    for _ in $(seq 1 300); do
      grep -qE '^REAL_(READY|FAILED)' "$log" 2>/dev/null && break
      sleep 0.5
    done
    grep -m1 -E '^REAL_(READY|FAILED)' "$log" 2>/dev/null
    ;;
  esac

  if [ -z "$wid" ]; then
    echo "✗ $shot/$mode — janela não abriu"; cat "$log"; kill "$pid" 2>/dev/null; return 1
  fi

  sleep "$settle"
  screencapture -x -o -l"$wid" "$png" 2>/dev/null
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  rm -f "$log"

  if [ -s "$png" ]; then
    echo "✓ $png  ($(sips -g pixelWidth -g pixelHeight "$png" 2>/dev/null | awk '/pixel/{printf "%s ", $2}'))"
  else
    echo "✗ $shot/$mode — screencapture vazio (falta permissão de Gravação de Tela?)"
    return 1
  fi
}

if [ $# -eq 2 ]; then
  shoot "$1" "$2"
else
  for shot in popover empty almost noHook reset overrun window windowAlmost lanes; do
    for mode in dark light; do
      shoot "$shot" "$mode"
    done
  done
fi
