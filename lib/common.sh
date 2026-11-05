# shellcheck shell=bash
# Shared settings and helpers. Sourced by ./svws.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DATA=$ROOT/data          # runtime data (gitignored)
CACHE=$ROOT/cache        # downloads + git clones (gitignored)

# Load .env (created by `./svws setup` from .env.example)
if [[ -f $ROOT/.env ]]; then set -a; . "$ROOT/.env"; set +a; fi

: "${SCHILD_VERSION:=latest}"                  # SchILD-NRW 3 installer release (e.g. 3.6.0) or latest
: "${SVWS_VERSION:=auto}"                      # server image tag; auto = what SchILD expects (server.json)
: "${BOTTLE_NAME:=SchILD3}"
: "${WINE_RUNNER:=kron4ek-wine-11.20-amd64}"
: "${WINE_RUNNER_URL:=https://github.com/Kron4ek/Wine-Builds/releases/download/11.20/wine-11.20-amd64.tar.xz}"
: "${FONT_SRC:=$HOME/.local/share/fonts/Microsoft}"
: "${SVWS_PORT:=8443}"
: "${DB_PORT:=3306}"

FLATPAK_APP=com.usebottles.bottles
BOTTLES_DATA=$HOME/.var/app/$FLATPAK_APP/data/bottles
RUNNER_DIR=$BOTTLES_DATA/runners/$WINE_RUNNER

c_bold=$'\e[1m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_off=$'\e[0m'
step() { echo "${c_bold}==> $*${c_off}"; }
info() { echo "    $*"; }
ok()   { echo "    ${c_green}✓${c_off} $*"; }
warn() { echo "    ${c_yellow}!${c_off} $*" >&2; }
die()  { echo "${c_red}error:${c_off} $*" >&2; exit 1; }

need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing command: $c"; done; }

compose() { (cd "$ROOT" && podman-compose -p svws-local "$@"); }

# Latest release tag (vX.Y.Z) of a GitHub repo without using the API (no rate limit)
gh_latest_tag() {
  curl -sI "https://github.com/$1/releases/latest" \
    | sed -n 's|^location: .*/tag/\([^[:space:]]*\).*|\1|Ip' | tr -d '\r'
}

# Download to cache once
fetch() {  # url dest
  [[ -s $2 ]] && return 0
  mkdir -p "$(dirname "$2")"
  info "download $(basename "$2")"
  curl -fL --progress-bar -o "$2.part" "$1" && mv "$2.part" "$2"
}

# Clone or fast-forward a SVWS-NRW repo into cache/repos
git_sync() {  # repo
  local dir=$CACHE/repos/$1
  if [[ -d $dir/.git ]]; then git -C "$dir" pull -q --ff-only
  else mkdir -p "$CACHE/repos"; git clone -q --depth 1 "https://github.com/SVWS-NRW/$1.git" "$dir"; fi
}

server_alive() { curl -sk -m 3 "https://localhost:$SVWS_PORT/status/alive" >/dev/null; }

wait_server() {
  local i
  for i in $(seq 1 120); do server_alive && return 0; sleep 2; done
  die "SVWS-Server did not come up – see: ./svws logs"
}
