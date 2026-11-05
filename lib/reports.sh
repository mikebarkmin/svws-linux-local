# shellcheck shell=bash
# Report collections from github.com/SVWS-NRW, downloaded to cache/reports/<repo> and
# linked into C:\SVWS-Arbeitsverzeichnis\Schild-Reports\<folder> of the Wine prefix.

# Latest commit of the default branch (GitHub API, 60 requests/h without login – plenty)
repo_head() {
  curl -sf -H 'Accept: application/vnd.github.sha' "https://api.github.com/repos/SVWS-NRW/$1/commits/HEAD" || true
}

repo_fetch() {  # repo → cache/reports/<repo> at the latest commit
  local repo=$1 dir=$CACHE/reports/$1 head have tmp zip
  head=$(repo_head "$repo")
  have=$(cat "$dir/.commit" 2>/dev/null || true)
  if [[ -d $dir && ( -z $head || $head == "$have" ) ]]; then return 0; fi
  tmp=$(mktemp -d "$CACHE/.reports.XXXX"); zip=$tmp/repo.zip
  curl -sfL -o "$zip" "https://github.com/SVWS-NRW/$repo/archive/${head:-HEAD}.zip" || { rm -rf "$tmp"; die "download failed: $repo"; }
  py_unzip "$zip" "$tmp/x"
  mkdir -p "$CACHE/reports"; rm -rf "$dir"
  mv "$tmp"/x/*/ "$dir"; rm -rf "$tmp"
  echo "${head:-unknown}" > "$dir/.commit"
}

reports_sync() {
  [[ -d $WORKDIR ]] || die "SchILD is not installed – run: ./svws setup"
  local dest=$WORKDIR/Schild-Reports repo target extra p src entries total=0 n
  step "Linking reports into C:\\SVWS-Arbeitsverzeichnis\\Schild-Reports"
  mkdir -p "$dest"
  while IFS='|' read -r repo target extra; do
    repo=$(echo "$repo" | xargs); target=$(echo "$target" | xargs); extra=$(echo "$extra" | xargs)
    [[ -z $repo || $repo == \#* ]] && continue
    repo_fetch "$repo"
    src=$CACHE/reports/$repo
    entries=()
    if [[ -f $src/.zipallow ]]; then   # official release content of the repo
      while IFS= read -r p || [[ -n $p ]]; do p=${p%$'\r'}; [[ -n $p && -e $src/$p ]] && entries+=("$p"); done < "$src/.zipallow"
    fi
    for p in $extra; do [[ -e $src/$p ]] && entries+=("$p"); done
    rm -rf "${dest:?}/$target"; mkdir -p "$dest/$target"
    for p in "${entries[@]}"; do ln -s "$src/$p" "$dest/$target/$p"; done
    n=$(find -L "$dest/$target" -iname '*.rtm' | wc -l); total=$((total + n))
    printf '    %-30s → %-24s %4d reports  (%.7s)\n' "$repo" "$target" "$n" "$(cat "$src/.commit")"
  done < "$ROOT/config/reports.conf"
  ok "$total reports available"
}
