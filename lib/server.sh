# shellcheck shell=bash
# SVWS-Server (podman), TLS certificate, SVWS-Tools.

env_init() {
  if [[ -f $ROOT/.env ]]; then ok ".env exists"; return; fi
  step "Creating .env with random passwords"
  local f=$ROOT/.env pw
  cp "$ROOT/.env.example" "$f"
  for v in MARIADB_ROOT_PASSWORD MARIADB_PASSWORD SVWS_TLS_KEYSTORE_PASSWORD; do
    pw=$(openssl rand -hex 12)
    sed -i "s|^$v=.*|$v=$pw|" "$f"
  done
  chmod 600 "$f"
  set -a; . "$f"; set +a
  ok ".env created"
}

# Resolve SVWS_VERSION=auto to the version SchILD expects and pin it in .env
server_version_resolve() {
  local want=$SVWS_VERSION
  if [[ $want == auto ]]; then
    want=$(schild_expected_server)
    [[ -n $want ]] || die "cannot determine server version (SchILD not installed?) – set SVWS_VERSION in .env"
    info "SchILD-NRW $(schild_installed_version) expects SVWS-Server $want"
  fi
  SVWS_VERSION=$want; export SVWS_VERSION
}

# Self-signed certificate with SAN (localhost, 127.0.0.1, ::1) → PKCS12 keystore for the server
cert_init() {
  local d=$DATA/certs
  if [[ -f $d/svws.crt && -f $DATA/svws/keystore ]]; then ok "TLS certificate exists"; return; fi
  step "Generating TLS certificate"
  mkdir -p "$d" "$DATA/svws"
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout "$d/svws.key" -out "$d/svws.crt" \
    -subj "/O=SVWS Linux Local/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" \
    -addext "extendedKeyUsage=serverAuth" 2>/dev/null
  openssl pkcs12 -export -in "$d/svws.crt" -inkey "$d/svws.key" -name "$SVWS_TLS_KEY_ALIAS" \
    -passout "pass:$SVWS_TLS_KEYSTORE_PASSWORD" -out "$DATA/svws/keystore"
  chmod 600 "$d/svws.key"
  ok "certificate: $d/svws.crt"
}

server_up() {  # [import-test-data]
  mkdir -p "$DATA/mariadb" "$DATA/svws" "$DATA/apps"
  [[ ${1:-} == import ]] && export IMPORT_TEST_DATA=true
  compose up -d >/dev/null 2>&1 || compose up -d
  unset IMPORT_TEST_DATA
  wait_server
}

server_first_start() {
  if [[ -d $DATA/mariadb/${MARIADB_DATABASE:-svwsdb} ]]; then
    step "Starting SVWS-Server $SVWS_VERSION"; server_up
  else
    step "Starting SVWS-Server $SVWS_VERSION and importing test data (first start, ~1 min)"
    server_up import
  fi
  ok "https://localhost:$SVWS_PORT"
}

# Recreate the server container (needed after changing image/env); never imports test data
server_recreate() {
  podman rm -f svws-local-server >/dev/null 2>&1 || true
  server_up
}

server_reset_db() {
  step "Resetting database to the SVWS test data"
  compose down >/dev/null 2>&1 || true
  podman unshare rm -rf "$DATA/mariadb"
  server_up import
  ok "test data imported"
}

tools_install() {
  local tag ver zip tmp d name
  if [[ ${SVWS_TOOLS_VERSION:-latest} == latest ]]; then tag=$(gh_latest_tag SVWS-NRW/SVWS-Tools)
  else tag=v${SVWS_TOOLS_VERSION#v}; fi
  ver=${tag#v}
  step "Installing SVWS-Tools $ver"
  zip=$CACHE/downloads/svws-tools-$ver.zip
  fetch "https://github.com/SVWS-NRW/SVWS-Tools/releases/download/$tag/svws-tools-$ver.zip" "$zip"
  tmp=$(mktemp -d); unzip -q "$zip" -d "$tmp"
  mkdir -p "$DATA/apps"
  for d in "$tmp"/*/; do
    name=$(basename "$d")
    rsync -a --delete --exclude sichtbarkeit.js "$d" "$DATA/apps/$name/"
    info "/app/$name/"
  done
  cp "$tmp/versions.json" "$DATA/apps/" 2>/dev/null || true
  rm -rf "$tmp"
  # local tile visibility (kept across updates)
  if [[ ! -f $DATA/apps/start/sichtbarkeit.js && -f $ROOT/config/sichtbarkeit.js ]]; then
    cp "$ROOT/config/sichtbarkeit.js" "$DATA/apps/start/sichtbarkeit.js"
  fi
  # the server scans /app/ only at startup
  if podman container exists svws-local-server; then podman restart svws-local-server >/dev/null; wait_server; fi
  ok "start page: https://localhost:$SVWS_PORT/app/start/"
}
