# shellcheck shell=bash
# Bottles (flatpak) bottle with SchILD-NRW 3.

bottles_cli() { flatpak run --command=bottles-cli "$FLATPAK_APP" "$@" 2> >(grep -v '(INFO)' >&2); }

# Absolute path of the bottle prefix (empty if it does not exist)
bottle_path() {
  local p
  p=$(bottles_cli -j list bottles 2>/dev/null | python3 -I -c '
import json,sys
d=json.load(sys.stdin); b=d.get(sys.argv[1])
print(b["Path"] if b else "")' "$BOTTLE_NAME" 2>/dev/null) || true
  [[ -n $p ]] && echo "$BOTTLES_DATA/bottles/$p"
}

require_bottle() {
  PREFIX=$(bottle_path)
  [[ -n $PREFIX && -d $PREFIX ]] || die "bottle '$BOTTLE_NAME' not found – run: ./svws setup"
  SCHILD_DIR=$PREFIX/drive_c/Program\ Files\ \(x86\)/SchILD-NRW3
  WORKDIR=$PREFIX/drive_c/SVWS-Arbeitsverzeichnis
}

# Run the runner's wine inside the Bottles flatpak sandbox against the bottle.
# Every `flatpak run` gets its own /tmp and therefore its own wineserver, which writes
# registry changes to disk only after it exits. `wineserver -w` waits for that –
# otherwise the next call reads a stale registry and can overwrite the changes.
bwine() {
  local cmd ws
  printf -v cmd '%q ' "$RUNNER_DIR/bin/wine" "$@"
  printf -v ws '%q' "$RUNNER_DIR/bin/wineserver"
  [[ -n ${BWINE_TIMEOUT:-} ]] && cmd="timeout -s KILL $BWINE_TIMEOUT $cmd"
  flatpak run --command=bash "$FLATPAK_APP" -c "export WINEPREFIX=$(printf %q "$PREFIX") WINEDEBUG=\${WINEDEBUG:--all}; $cmd; rc=\$?; $ws -w; exit \$rc"
}

runner_install() {
  if [[ -x $RUNNER_DIR/bin/wine ]]; then ok "runner $WINE_RUNNER present"; return; fi
  step "Installing Wine runner $WINE_RUNNER"
  local tar=$CACHE/downloads/$(basename "$WINE_RUNNER_URL") tmp
  fetch "$WINE_RUNNER_URL" "$tar"
  tmp=$(mktemp -d "$BOTTLES_DATA/runners/.tmp.XXXX")
  tar -xf "$tar" -C "$tmp"
  mv "$tmp"/*/ "$RUNNER_DIR"; rmdir "$tmp"
  ok "runner installed to $RUNNER_DIR"
}

bottle_create() {
  if [[ -n $(bottle_path) ]]; then
    ok "bottle '$BOTTLE_NAME' exists"
    bottles_cli edit -b "$BOTTLE_NAME" --runner "$WINE_RUNNER" >/dev/null
  else
    step "Creating bottle '$BOTTLE_NAME' (takes a few minutes)"
    bottles_cli new --bottle-name "$BOTTLE_NAME" --environment application --arch win64 --runner "$WINE_RUNNER" >/dev/null
  fi
  require_bottle
  ok "prefix: $PREFIX"
}

# Visual Basic 6 SP6 runtime (same as the Bottles dependency "vbrun6"). SchILD's
# IT-NRW\ASDStatistik.dll is a VB6 COM component – without msvbvm60.dll the SchILD
# installer fails at regsvr32 (exit code 3) and rolls back the whole installation.
vb6_install() {
  require_bottle
  local dll=$PREFIX/drive_c/windows/syswow64/msvbvm60.dll
  if [[ -f $dll ]]; then ok "VB6 runtime present"; return; fi
  step "Installing Visual Basic 6 SP6 runtime"
  local exe=$CACHE/downloads/VB6.0-KB290887-X86.exe tmp
  fetch "https://web.archive.org/web/20070204154430/https://download.microsoft.com/download/5/a/d/5ad868a0-8ecd-4bb0-a882-fe53eb7ef348/VB6.0-KB290887-X86.exe" "$exe"
  [[ $(md5sum < "$exe" | cut -d' ' -f1) == ef5b83c4cc60e246bf627d85f6d7397b ]] || { rm -f "$exe"; die "VB6.0-KB290887-X86.exe checksum mismatch"; }
  tmp=$(mktemp -d)
  cabextract -q -d "$tmp" -F vbrun60sp6.exe "$exe"
  cabextract -q -d "$tmp" -F msvbvm60.dll "$tmp/vbrun60sp6.exe"
  cp "$tmp/msvbvm60.dll" "$dll"; rm -rf "$tmp"
  ok "msvbvm60.dll installed"
}

# Microsoft Jet 4.0 SP8 (same as the Bottles dependency "jet40"): Jet/ODBC drivers.
jet40_install() {
  require_bottle
  if [[ -f $PREFIX/drive_c/windows/syswow64/msjet40.dll ]]; then ok "Jet 4.0 present"; return; fi
  step "Installing Microsoft Jet 4.0 SP8"
  local exe=$CACHE/downloads/Jet40SP8_9xNT.exe
  fetch "https://web.archive.org/web/20210225171713/http://download.microsoft.com/download/4/3/9/4393c9ac-e69e-458d-9f6d-2fe191c51469/Jet40SP8_9xNT.exe" "$exe"
  [[ $(md5sum < "$exe" | cut -d' ' -f1) == d1028c0f98b4ffe5ede854327b77fbb9 ]] || { rm -f "$exe"; die "Jet40SP8_9xNT.exe checksum mismatch"; }
  cp "$exe" "$PREFIX/drive_c/jet40.exe"
  bwine 'C:\jet40.exe' /q >/dev/null 2>&1 || true
  rm -f "$PREFIX/drive_c/jet40.exe"
  [[ -f $PREFIX/drive_c/windows/syswow64/msjet40.dll ]] || die "Jet 4.0 installation failed"
  ok "Jet 4.0 installed"
}

schild_release_tag() {
  if [[ $SCHILD_VERSION == latest ]]; then gh_latest_tag SVWS-NRW/Schild-NRW-3; else echo "v${SCHILD_VERSION#v}"; fi
}

schild_installed_version() {
  [[ -f $SCHILD_DIR/Schild3_Versionen.txt ]] || return 0
  grep -m1 -oE 'Version [0-9]+\.[0-9]+\.[0-9]+' "$SCHILD_DIR/Schild3_Versionen.txt" | cut -d' ' -f2
}

schild_install() {
  require_bottle
  local tag ver exe installed
  tag=$(schild_release_tag); ver=${tag#v}
  installed=$(schild_installed_version)
  if [[ $installed == "$ver" ]]; then ok "SchILD-NRW $ver installed"; return; fi
  step "Installing SchILD-NRW $ver${installed:+ (was $installed)}"
  exe=$CACHE/downloads/Setup_SchILD3_$tag.exe
  fetch "https://github.com/SVWS-NRW/Schild-NRW-3/releases/download/$tag/Setup_SchILD3_$tag.exe" "$exe"
  cp "$exe" "$PREFIX/drive_c/schild-setup.exe"
  bwine 'C:\schild-setup.exe' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART '/LOG=C:\schild_setup.log' >/dev/null 2>&1 || true
  rm -f "$PREFIX/drive_c/schild-setup.exe"
  [[ -f $SCHILD_DIR/SchILD30.exe ]] || die "SchILD installation failed – see $PREFIX/drive_c/schild_setup.log"
  bottles_cli add -b "$BOTTLE_NAME" -n SchILD30 -p "$SCHILD_DIR/SchILD30.exe" >/dev/null 2>&1 || true
  bottles_cli add -b "$BOTTLE_NAME" -n SchILD_DBConfig -p "$SCHILD_DIR/SchILD_DBConfig.exe" >/dev/null 2>&1 || true
  ok "SchILD-NRW $(schild_installed_version) installed"
}

# Server version SchILD expects (C:\Program Files (x86)\SchILD-NRW3\server.json)
schild_expected_server() {
  [[ -f $SCHILD_DIR/server.json ]] || return 0
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("server_version",""))' "$SCHILD_DIR/server.json"
}

# Trust the SVWS-Server certificate in the bottle (Wine reports untrusted certs as 12157).
# Imported into the *user* Root store: Wine re-syncs the machine Root store with the
# Linux CA certificates and may drop certificates added there.
bottle_trust_cert() {
  require_bottle
  local reg=$PREFIX/drive_c/svws-root.reg
  python3 -I - "$DATA/certs/svws.crt" "$reg" <<'EOF'
import base64, hashlib, struct, sys
pem = open(sys.argv[1]).read()
der = base64.b64decode("".join(l for l in pem.splitlines() if l and not l.startswith("-----")))
thumb = hashlib.sha1(der).hexdigest().upper()
blob = struct.pack("<III", 0x20, 1, len(der)) + der           # CERT_CERT_PROP_ID
hx = ",".join(f"{b:02x}" for b in blob)
key = r"HKEY_CURRENT_USER\Software\Microsoft\SystemCertificates\Root\Certificates" + "\\" + thumb
open(sys.argv[2], "w", newline="").write(f'REGEDIT4\r\n\r\n[{key}]\r\n"Blob"=hex:{hx}\r\n')
EOF
  bwine regedit /S 'C:\svws-root.reg' >/dev/null 2>&1
  rm -f "$reg"
  ok "certificate trusted in bottle"
}

# Fonts: SchILD uses Segoe UI + Tahoma. Use Microsoft fonts from $FONT_SRC if available,
# otherwise map Segoe UI to Wine's built-in Tahoma (never to Times New Roman).
bottle_fonts() {
  require_bottle
  local reg=$PREFIX/drive_c/schild-fonts.reg f n have=()
  local -A F=(
    [segoeui.ttf]="Segoe UI" [segoeuib.ttf]="Segoe UI Bold" [segoeuii.ttf]="Segoe UI Italic" [segoeuiz.ttf]="Segoe UI Bold Italic"
    [segoeuil.ttf]="Segoe UI Light" [SEGOEUISL.TTF]="Segoe UI Semilight" [seguisb.ttf]="Segoe UI Semibold" [seguisym.ttf]="Segoe UI Symbol"
    [tahoma.ttf]="Tahoma" [tahomabd.ttf]="Tahoma Bold"
    [verdana.ttf]="Verdana" [verdanab.ttf]="Verdana Bold" [verdanai.ttf]="Verdana Italic" [verdanaz.ttf]="Verdana Bold Italic"
    [calibri.ttf]="Calibri" [calibrib.ttf]="Calibri Bold" [calibrii.ttf]="Calibri Italic" [calibriz.ttf]="Calibri Bold Italic"
    [arial.ttf]="Arial" [arialbd.ttf]="Arial Bold" [ariali.ttf]="Arial Italic" [arialbi.ttf]="Arial Bold Italic"
    [times.ttf]="Times New Roman" [timesbd.ttf]="Times New Roman Bold" [timesi.ttf]="Times New Roman Italic" [timesbi.ttf]="Times New Roman Bold Italic"
    [cour.ttf]="Courier New" [courbd.ttf]="Courier New Bold" [couri.ttf]="Courier New Italic" [courbi.ttf]="Courier New Bold Italic"
    [micross.ttf]="Microsoft Sans Serif" [lucon.ttf]="Lucida Console"
    [trebuc.ttf]="Trebuchet MS" [trebucbd.ttf]="Trebuchet MS Bold" [trebucit.ttf]="Trebuchet MS Italic" [trebucbi.ttf]="Trebuchet MS Bold Italic"
    [pala.ttf]="Palatino Linotype" [palab.ttf]="Palatino Linotype Bold" [palai.ttf]="Palatino Linotype Italic" [palabi.ttf]="Palatino Linotype Bold Italic"
  )
  {
    printf 'REGEDIT4\r\n\r\n[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]\r\n'
    for f in "${!F[@]}"; do
      n=$(find "$FONT_SRC" -maxdepth 1 -iname "$f" -print -quit 2>/dev/null)
      [[ -n $n ]] || continue
      cp "$n" "$PREFIX/drive_c/windows/Fonts/$f"; have+=("$f")
      printf '"%s (TrueType)"="%s"\r\n' "${F[$f]}" "$f"
    done
    printf '\r\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\r\n'
    printf '"Palatino Linotype"=-\r\n"Verdana"=-\r\n'
    if [[ -f $PREFIX/drive_c/windows/Fonts/segoeui.ttf ]]; then
      printf '"Segoe UI"=-\r\n"Segoe UI Semibold"=-\r\n'
    else
      printf '"Segoe UI"="Tahoma"\r\n"Segoe UI Semibold"="Tahoma"\r\n"Segoe UI Light"="Tahoma"\r\n'
    fi
    printf '\r\n[HKEY_CURRENT_USER\\Control Panel\\Desktop]\r\n"FontSmoothing"="2"\r\n"FontSmoothingType"=dword:00000002\r\n"FontSmoothingGamma"=dword:00000578\r\n"FontSmoothingOrientation"=dword:00000001\r\n'
  } > "$reg"
  bwine regedit /S 'C:\schild-fonts.reg' >/dev/null 2>&1
  rm -f "$reg"
  if ((${#have[@]})); then ok "${#have[@]} Microsoft fonts installed from $FONT_SRC"
  else warn "no Microsoft fonts in $FONT_SRC – Segoe UI is mapped to Tahoma (see README)"; fi
}

# WinHTTP check from inside the bottle (what SchILD_DBConfig's REST test does)
bottle_test() {
  require_bottle
  cp "$ROOT/lib/winhttp_test.js" "$PREFIX/drive_c/winhttp_test.js"
  local out
  out=$(BWINE_TIMEOUT=90 bwine 'C:/windows/syswow64/cscript.exe' //nologo 'C:/winhttp_test.js' "$SVWS_PORT" 2>/dev/null | tr -d '\r' | tail -1)
  rm -f "$PREFIX/drive_c/winhttp_test.js"
  echo "    $out"
  [[ $out == *" 200 "* ]]
}

schild_run() {  # exe name
  require_bottle
  [[ -f $SCHILD_DIR/$1 ]] || die "$1 not installed – run: ./svws setup"
  bottles_cli run -b "$BOTTLE_NAME" -e "$SCHILD_DIR/$1"
}
