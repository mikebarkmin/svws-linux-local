# shellcheck shell=bash
# Shared settings and helpers. Sourced by ./svws.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DATA=$ROOT/data          # runtime data (gitignored): prefix, database, server config, apps
CACHE=$ROOT/cache        # downloads, Wine build, report collections (gitignored)

# Load .env (created by `./svws setup` from .env.example)
if [[ -f $ROOT/.env ]]; then set -a; . "$ROOT/.env"; set +a; fi

: "${SCHILD_VERSION:=latest}"
: "${SVWS_VERSION:=auto}"
: "${SVWS_TOOLS_VERSION:=latest}"
: "${WINE_URL:=https://github.com/Kron4ek/Wine-Builds/releases/download/11.20/wine-11.20-amd64-wow64.tar.xz}"
: "${FONT_SRC:=$HOME/.local/share/fonts/Microsoft}"
: "${SVWS_PORT:=8443}"
: "${DB_PORT:=3306}"
FONT_SRC=${FONT_SRC/#\~/$HOME}

POD=svws-local

c_bold=$'\e[1m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_off=$'\e[0m'
step() { echo "${c_bold}==> $*${c_off}"; }
info() { echo "    $*"; }
ok()   { echo "    ${c_green}✓${c_off} $*"; }
warn() { echo "    ${c_yellow}!${c_off} $*" >&2; }
die()  { echo "${c_red}error:${c_off} $*" >&2; exit 1; }

need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing program: $c"; done; }

# Latest release tag (vX.Y.Z) of a GitHub repo, via the redirect (no API rate limit)
gh_latest_tag() {
  curl -sI "https://github.com/$1/releases/latest" \
    | sed -n 's|^location: .*/tag/\([^[:space:]]*\).*|\1|Ip' | tr -d '\r'
}

# Download once into the cache
fetch() {  # url dest
  [[ -s $2 ]] && return 0
  mkdir -p "$(dirname "$2")"
  info "download $(basename "$2")"
  curl -fL --progress-bar -o "$2.part" "$1" || die "download failed: $1"
  mv "$2.part" "$2"
}

check_md5() {  # file md5
  [[ $(md5sum < "$1" | cut -d' ' -f1) == "$2" ]] || { rm -f "$1"; die "checksum mismatch: $(basename "$1")"; }
}

py_json_get() {  # file key
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2" 2>/dev/null
}

py_unzip() {  # zip dest
  python3 -I -m zipfile -e "$1" "$2"
}

server_alive() { curl -sk -m 3 "https://localhost:$SVWS_PORT/status/alive" >/dev/null; }

wait_server() {
  local i
  for i in $(seq 1 150); do server_alive && return 0; sleep 2; done
  die "SVWS-Server did not come up – see: ./svws logs"
}
