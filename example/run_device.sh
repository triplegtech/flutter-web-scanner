#!/usr/bin/env bash
#
# Serve o exemplo e o expõe por HTTPS através de um Cloudflare Quick Tunnel,
# para testar a câmera em um celular real.
#
# A câmera do navegador só é liberada em contexto seguro (HTTPS ou localhost).
# Abrir o dev server pelo IP da LAN — http://192.168.x.x:8787 — falha com
# ScannerFailureKind.insecureContext, por isso o túnel, e não um QR do IP local.
#
# Uso:
#   ./run_device.sh                 # debug, porta 8787
#   ./run_device.sh --release       # build de release (mais lento, mais fiel)
#   ./run_device.sh --port 9000
#   ./run_device.sh -- --dart-define=FOO=bar   # tudo após -- vai para o flutter run
#
set -euo pipefail

readonly EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TUNNEL_TIMEOUT_SECONDS=45

PORT=8787
BUILD_MODE="--debug"
FLUTTER_EXTRA_ARGS=()

log()  { printf '\033[36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: ./run_device.sh [opções] [-- args extras do flutter run]

  --port <n>     Porta do dev server local (padrão: 8787)
  --release      Compila em release
  --profile      Compila em profile
  -h, --help     Mostra esta ajuda

Requer: flutter e cloudflared (brew install cloudflared).
Gera uma URL *.trycloudflare.com efêmera, pública enquanto o script roda.
Túneis nomeados/com domínio próprio não são cobertos aqui.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)     PORT="${2:-}"; [[ -n "$PORT" ]] || die "--port exige um valor"; shift 2 ;;
    --release)  BUILD_MODE="--release"; shift ;;
    --profile)  BUILD_MODE="--profile"; shift ;;
    -h|--help)  usage; exit 0 ;;
    --)         shift; FLUTTER_EXTRA_ARGS=("$@"); break ;;
    *)          die "Opção desconhecida: $1 (use --help)" ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || die "Porta inválida: $PORT"

command -v flutter >/dev/null 2>&1 || die "flutter não encontrado no PATH."
command -v cloudflared >/dev/null 2>&1 \
  || die "cloudflared não encontrado. Instale com: brew install cloudflared"

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  die "Porta $PORT já está em uso. Use --port <outra>."
fi

TUNNEL_LOG="$(mktemp -t flutter-web-scanner-cloudflared)"
TUNNEL_PID=""

cleanup() {
  if [[ -n "$TUNNEL_PID" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    log "Encerrando o túnel…"
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  rm -f "$TUNNEL_LOG"
}
trap cleanup EXIT INT TERM

cd "$EXAMPLE_DIR"

log "flutter pub get"
flutter pub get >/dev/null

# O túnel sobe antes do dev server: o Quick Tunnel se registra na Cloudflare
# mesmo sem origem respondendo, então a URL já pode ser exibida e escaneada
# enquanto o Flutter ainda compila. Até lá o celular vê 502 — basta recarregar.
log "Abrindo o Cloudflare Quick Tunnel para http://127.0.0.1:$PORT"
cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" \
  >"$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

PUBLIC_URL=""
for _ in $(seq 1 "$TUNNEL_TIMEOUT_SECONDS"); do
  if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
    warn "cloudflared saiu antes de criar o túnel:"
    tail -n 20 "$TUNNEL_LOG" >&2
    die "Falha ao abrir o túnel."
  fi
  PUBLIC_URL="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
  [[ -n "$PUBLIC_URL" ]] && break
  sleep 1
done

if [[ -z "$PUBLIC_URL" ]]; then
  tail -n 20 "$TUNNEL_LOG" >&2
  die "Túnel não respondeu em ${TUNNEL_TIMEOUT_SECONDS}s."
fi

printf '\n'
printf '\033[32m  %s\033[0m\n' "$PUBLIC_URL"
printf '\n'

if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ANSIUTF8 -m 2 -- "$PUBLIC_URL"
else
  warn "Instale qrencode (brew install qrencode) para ver a URL como QR aqui."
fi

log "Abra a URL no celular. HTTPS é o que libera a câmera; a permissão"
log "é pedida na primeira vez e vale para este domínio efêmero."
log "Hot reload: 'r' e 'R' continuam funcionando neste terminal."
printf '\n'

# Em primeiro plano de propósito: mantém as teclas de hot reload do flutter run.
# Ao sair, o trap derruba o cloudflared.
flutter run "$BUILD_MODE" \
  -d web-server \
  --web-hostname 127.0.0.1 \
  --web-port "$PORT" \
  ${FLUTTER_EXTRA_ARGS[@]+"${FLUTTER_EXTRA_ARGS[@]}"}
