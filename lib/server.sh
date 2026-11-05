# shellcheck shell=bash
# SVWS-Server + MariaDB as a podman pod, SVWS-Tools web apps.

env_init() {
  if [[ -f $ROOT/.env ]]; then ok ".env exists"; return; fi
  step "Creating .env (random root and keystore passwords)"
  local f=$ROOT/.env v
  cp "$ROOT/.env.example" "$f"
  for v in MARIADB_ROOT_PASSWORD SVWS_TLS_KEYSTORE_PASSWORD; do
    sed -i "s|^$v=.*|$v=$(python3 -I -c 'import secrets; print(secrets.token_hex(12))')|" "$f"
  done
  chmod 600 "$f"
  set -a; . "$f"; set +a
  ok ".env created"
}

# SVWS_VERSION=auto → the version SchILD expects
server_version_resolve() {
  if [[ $SVWS_VERSION == auto ]]; then
    SVWS_VERSION=$(schild_expected_server)
    [[ -n $SVWS_VERSION ]] || die "cannot determine the server version (SchILD not installed?) – set SVWS_VERSION in .env"
  fi
}

server_image() { echo "docker.io/svwsnrw/svws-server:$SVWS_VERSION"; }

# Both containers share the pod's network namespace: the server reaches MariaDB on 127.0.0.1.
# Ports are only published on 127.0.0.1.
server_up() {  # [import]
  local import=false
  [[ ${1:-} == import ]] && import=true
  mkdir -p "$DATA/mariadb" "$DATA/svws" "$DATA/apps"
  if ! podman pod exists "$POD"; then
    podman pod create --name "$POD" -p "127.0.0.1:$SVWS_PORT:8443" -p "127.0.0.1:$DB_PORT:3306" >/dev/null
  fi
  if ! podman container exists "$POD-mariadb"; then
    podman create --pod "$POD" --name "$POD-mariadb" --env-file "$ROOT/.env" \
      -v "$DATA/mariadb:/var/lib/mysql:Z" docker.io/library/mariadb:11 >/dev/null
  fi
  # The server imports the test data on every *new* container when IMPORT_TEST_DATA=true,
  # overwriting the database – so it is only set on the very first start and for reset-db.
  if ! podman container exists "$POD-server"; then
    podman create --pod "$POD" --name "$POD-server" --env-file "$ROOT/.env" \
      -e MARIADB_HOST=127.0.0.1 -e IMPORT_TEST_DATA=$import \
      -v "$DATA/svws:/opt/app/svws/conf:Z" -v "$DATA/apps:/opt/app/svws/apps:Z" \
      "$(server_image)" >/dev/null
  fi
  podman start "$POD-mariadb" >/dev/null
  local i
  for i in $(seq 1 60); do
    podman exec "$POD-mariadb" mariadb-admin ping -h 127.0.0.1 -uroot "-p$MARIADB_ROOT_PASSWORD" >/dev/null 2>&1 && break
    sleep 2
  done
  podman start "$POD-server" >/dev/null
  wait_server
}

server_down() { podman pod exists "$POD" && podman pod stop "$POD" >/dev/null; ok "stopped"; }

server_first_start() {
  if [[ -d $DATA/mariadb/${MARIADB_DATABASE:-svwsdb} ]]; then
    step "Starting SVWS-Server $SVWS_VERSION"; server_up
  else
    step "Starting SVWS-Server $SVWS_VERSION, importing test data (first start, 1–3 min)"
    server_up import
  fi
  ok "https://localhost:$SVWS_PORT"
}

# Recreate the server container (new image version); never imports test data
server_recreate() {
  podman rm -f "$POD-server" >/dev/null 2>&1 || true
  server_up
}

server_reset_db() {
  step "Replacing the database with fresh SVWS test data"
  podman pod rm -f "$POD" >/dev/null 2>&1 || true
  podman unshare rm -rf "$DATA/mariadb"
  server_up import
  ok "test data imported"
}

server_logs() { podman logs -f "$POD-server"; }

tools_install() {
  local tag ver zip tmp d name
  if [[ $SVWS_TOOLS_VERSION == latest ]]; then tag=$(gh_latest_tag SVWS-NRW/SVWS-Tools)
  else tag=v${SVWS_TOOLS_VERSION#v}; fi
  ver=${tag#v}
  step "Installing SVWS-Tools $ver"
  zip=$CACHE/downloads/svws-tools-$ver.zip
  fetch "https://github.com/SVWS-NRW/SVWS-Tools/releases/download/$tag/svws-tools-$ver.zip" "$zip"
  tmp=$(mktemp -d); py_unzip "$zip" "$tmp"
  for d in "$tmp"/*/; do
    name=$(basename "$d")
    # replace the shipped files, keep the local start/sichtbarkeit.js
    find "$DATA/apps/$name" -mindepth 1 -not -name sichtbarkeit.js -delete 2>/dev/null || true
    mkdir -p "$DATA/apps/$name"; cp -r "$d". "$DATA/apps/$name/"
    info "/app/$name/"
  done
  cp "$tmp/versions.json" "$DATA/apps/" 2>/dev/null || true
  rm -rf "$tmp"
  [[ -f $DATA/apps/start/sichtbarkeit.js ]] || cp "$ROOT/config/sichtbarkeit.js" "$DATA/apps/start/sichtbarkeit.js"
  # the server scans /app/ only at startup
  if podman container exists "$POD-server" && [[ $(podman inspect -f '{{.State.Running}}' "$POD-server") == true ]]; then
    podman restart "$POD-server" >/dev/null; wait_server
  fi
  ok "start page: https://localhost:$SVWS_PORT/app/start/"
}
