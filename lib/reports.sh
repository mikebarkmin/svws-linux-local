# shellcheck shell=bash
# Sync the SVWS-NRW report repositories into the SchILD working directory of the bottle.
# Files are copied (not symlinked): the Bottles flatpak cannot see this repository.

reports_sync() {
  require_bottle
  local dest=$WORKDIR/Schild-Reports repo target extra p entries total=0 n
  step "Syncing reports into C:\\SVWS-Arbeitsverzeichnis\\Schild-Reports"
  mkdir -p "$dest"
  while IFS='|' read -r repo target extra; do
    repo=$(echo "$repo" | xargs); target=$(echo "$target" | xargs); extra=$(echo "$extra" | xargs)
    [[ -z $repo || $repo == \#* ]] && continue
    git_sync "$repo"
    local src=$CACHE/repos/$repo
    entries=()
    if [[ -f $src/.zipallow ]]; then
      while IFS= read -r p || [[ -n $p ]]; do p=${p%$'\r'}; [[ -n $p && -e $src/$p ]] && entries+=("$p"); done < "$src/.zipallow"
    fi
    for p in $extra; do [[ -e $src/$p ]] && entries+=("$p"); done
    mkdir -p "$dest/$target"
    for p in "${entries[@]}"; do rsync -a --delete "$src/$p" "$dest/$target/"; done
    n=$(find "$dest/$target" -iname '*.rtm' | wc -l); total=$((total + n))
    printf '    %-30s → %-26s %4d reports  (%s)\n' "$repo" "$target" "$n" "$(git -C "$src" log -1 --format='%h %cs')"
  done < "$ROOT/config/reports.conf"
  ok "$total reports available"
}
