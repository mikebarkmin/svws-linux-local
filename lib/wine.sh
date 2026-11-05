# shellcheck shell=bash
# SchILD-NRW 3 in a plain Wine prefix (data/prefix) with a portable Wine build (cache/wine).

WINE_DIR=$CACHE/wine
export WINEPREFIX=$DATA/prefix
# no Mono (SchILD is a Delphi program), no desktop menu entries / file associations
export WINEDLLOVERRIDES="mscoree=;winemenubuilder.exe="
export WINEDEBUG=${WINEDEBUG:--all}

DRIVE_C=$WINEPREFIX/drive_c
SCHILD_DIR=$DRIVE_C/Program\ Files\ \(x86\)/SchILD-NRW3
WORKDIR=$DRIVE_C/SVWS-Arbeitsverzeichnis

# Run wine and wait until the wineserver has written everything (registry!) to disk
wine() {
  local rc=0
  "$WINE_DIR/bin/wine" "$@" || rc=$?
  "$WINE_DIR/bin/wineserver" -w
  return $rc
}

require_prefix() {
  [[ -x $WINE_DIR/bin/wine && -f $SCHILD_DIR/SchILD30.exe ]] || die "SchILD is not installed – run: ./svws setup"
}

wine_install() {
  local want; want=$(basename "$WINE_URL")
  if [[ -f $WINE_DIR/.source && $(<"$WINE_DIR/.source") == "$want" ]]; then ok "Wine ${want%.tar.xz} present"; return; fi
  step "Installing Wine (${want%.tar.xz})"
  local tar=$CACHE/downloads/$want tmp
  fetch "$WINE_URL" "$tar"
  tmp=$(mktemp -d "$CACHE/.wine.XXXX")
  tar -xf "$tar" -C "$tmp"
  rm -rf "$WINE_DIR"; mv "$tmp"/*/ "$WINE_DIR"; rmdir "$tmp"
  echo "$want" > "$WINE_DIR/.source"
  # Wine Gecko (HTML engine) is picked up from here when the prefix is created
  local gv
  gv=$(python3 -I -c '
import re, sys
m = re.search(r"wine-gecko-([0-9.]+)-x86", open(sys.argv[1], "rb").read().decode("utf-16-le", "ignore"))
print(m.group(1) if m else "")' "$WINE_DIR/lib/wine/x86_64-windows/appwiz.cpl" 2>/dev/null || true)
  if [[ -n $gv ]]; then
    mkdir -p "$WINE_DIR/share/wine/gecko"
    for a in x86 x86_64; do
      fetch "https://dl.winehq.org/wine/wine-gecko/$gv/wine-gecko-$gv-$a.msi" "$CACHE/downloads/wine-gecko-$gv-$a.msi"
      cp "$CACHE/downloads/wine-gecko-$gv-$a.msi" "$WINE_DIR/share/wine/gecko/"
    done
  fi
  ok "Wine installed to cache/wine"
}

prefix_init() {
  if [[ -f $WINEPREFIX/system.reg ]]; then ok "Wine prefix exists"; return; fi
  step "Creating Wine prefix (data/prefix)"
  mkdir -p "$WINEPREFIX"
  wine wineboot -i >/dev/null 2>&1
  [[ -f $WINEPREFIX/system.reg ]] || die "wineboot failed – try: WINEDEBUG= $WINE_DIR/bin/wine wineboot"
  ok "prefix created"
}

# Microsoft Jet 4.0 SP8: Jet/ODBC drivers (like winetricks/Bottles "jet40")
jet40_install() {
  if [[ -f $DRIVE_C/windows/syswow64/msjet40.dll ]]; then ok "Jet 4.0 present"; return; fi
  step "Installing Microsoft Jet 4.0 SP8"
  local exe=$CACHE/downloads/Jet40SP8_9xNT.exe
  fetch "https://web.archive.org/web/20210225171713/http://download.microsoft.com/download/4/3/9/4393c9ac-e69e-458d-9f6d-2fe191c51469/Jet40SP8_9xNT.exe" "$exe"
  check_md5 "$exe" d1028c0f98b4ffe5ede854327b77fbb9
  cp "$exe" "$DRIVE_C/jet40.exe"
  wine 'C:\jet40.exe' /q >/dev/null 2>&1 || true
  rm -f "$DRIVE_C/jet40.exe"
  [[ -f $DRIVE_C/windows/syswow64/msjet40.dll ]] || die "Jet 4.0 installation failed"
  ok "Jet 4.0 installed"
}

# Microsoft Data Access Components 2.8 SP1 (native ADO/OLE DB, like the Bottles
# dependency "mdac28"). Wine's built-in msado15 does not implement Parameter.Type, and
# SchILD crashes on start with EOleException "Nicht implementiert"
# (Data.Win.ADODB.TParameter.GetDataType).
mdac_install() {
  local ado="$DRIVE_C/Program Files (x86)/Common Files/System/ADO/msado15.dll"
  if [[ -f $ado && $(stat -c %s "$ado") -gt 500000 ]]; then ok "MDAC 2.8 present"; return; fi
  step "Installing Microsoft Data Access Components 2.8 SP1"
  local exe=$CACHE/downloads/MDAC_TYP.EXE
  fetch "https://web.archive.org/web/20070127061938/https://download.microsoft.com/download/4/a/a/4aafff19-9d21-4d35-ae81-02c48dcbbbff/MDAC_TYP.EXE" "$exe"
  check_md5 "$exe" 6e914a7391c3b17380ce54fd3a7a133d
  cp "$exe" "$DRIVE_C/mdac.exe"
  wine winecfg /v win98 >/dev/null 2>&1
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES;odbccp32,odbc32,oledb32,mtxdm,msado15,msdasql=n,b" \
    wine 'C:\mdac.exe' /q '/C:setup /qnt' >/dev/null 2>&1 || true
  wine winecfg /v win10 >/dev/null 2>&1
  rm -f "$DRIVE_C/mdac.exe"
  [[ $(stat -c %s "$ado" 2>/dev/null || echo 0) -gt 500000 ]] || die "MDAC installation failed"
  # use the native ADO / OLE DB components from now on
  printf 'REGEDIT4\r\n\r\n[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\r\n"msado15"="native,builtin"\r\n"msdasql"="native,builtin"\r\n"oledb32"="native,builtin"\r\n' > "$DRIVE_C/mdac.reg"
  wine regedit /S 'C:\mdac.reg' >/dev/null 2>&1
  rm -f "$DRIVE_C/mdac.reg"
  ok "MDAC 2.8 installed"
}

# Visual Basic 6 SP6 runtime: SchILD's IT-NRW\ASDStatistik.dll is a VB6 COM component.
# Without msvbvm60.dll the SchILD installer fails at regsvr32 (exit code 3) and rolls back.
# Both packages are IExpress archives: /C /T:<dir> /Q only extracts them.
vb6_install() {
  local dll=$DRIVE_C/windows/syswow64/msvbvm60.dll
  if [[ -f $dll ]]; then ok "VB6 runtime present"; return; fi
  step "Installing Visual Basic 6 SP6 runtime"
  local exe=$CACHE/downloads/VB6.0-KB290887-X86.exe
  fetch "https://web.archive.org/web/20070204154430/https://download.microsoft.com/download/5/a/d/5ad868a0-8ecd-4bb0-a882-fe53eb7ef348/VB6.0-KB290887-X86.exe" "$exe"
  check_md5 "$exe" ef5b83c4cc60e246bf627d85f6d7397b
  cp "$exe" "$DRIVE_C/vb6.exe"
  wine 'C:\vb6.exe' /C '/T:C:\vb6tmp' /Q >/dev/null 2>&1 || true
  wine 'C:\vb6tmp\vbrun60sp6.exe' /C '/T:C:\vb6tmp\x' /Q >/dev/null 2>&1 || true
  cp "$DRIVE_C/vb6tmp/x/msvbvm60.dll" "$dll" 2>/dev/null || die "VB6 runtime extraction failed"
  rm -rf "$DRIVE_C/vb6.exe" "$DRIVE_C/vb6tmp"
  ok "msvbvm60.dll installed"
}

schild_release_tag() {
  if [[ $SCHILD_VERSION == latest ]]; then gh_latest_tag SVWS-NRW/Schild-NRW-3; else echo "v${SCHILD_VERSION#v}"; fi
}

schild_installed_version() {
  [[ -f $SCHILD_DIR/Schild3_Versionen.txt ]] || return 0
  grep -m1 -oE 'Version [0-9]+\.[0-9]+\.[0-9]+' "$SCHILD_DIR/Schild3_Versionen.txt" | cut -d' ' -f2
}

schild_install() {
  local tag ver exe installed
  tag=$(schild_release_tag); ver=${tag#v}
  [[ -n $ver ]] || die "cannot determine the SchILD-NRW 3 release (GitHub unreachable?)"
  installed=$(schild_installed_version)
  if [[ $installed == "$ver" ]]; then ok "SchILD-NRW $ver installed"; return; fi
  step "Installing SchILD-NRW $ver${installed:+ (was $installed)}"
  exe=$CACHE/downloads/Setup_SchILD3_$tag.exe
  fetch "https://github.com/SVWS-NRW/Schild-NRW-3/releases/download/$tag/Setup_SchILD3_$tag.exe" "$exe"
  cp "$exe" "$DRIVE_C/schild-setup.exe"
  wine 'C:\schild-setup.exe' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART '/LOG=C:\schild_setup.log' >/dev/null 2>&1 || true
  rm -f "$DRIVE_C/schild-setup.exe"
  [[ $(schild_installed_version) == "$ver" ]] || die "SchILD installation failed – see data/prefix/drive_c/schild_setup.log"
  ok "SchILD-NRW $ver installed"
}

# Server version SchILD expects (C:\Program Files (x86)\SchILD-NRW3\server.json)
schild_expected_server() {
  [[ -f $SCHILD_DIR/server.json ]] || return 0
  py_json_get "$SCHILD_DIR/server.json" server_version
}

# Fetch the server certificate and trust it in the prefix (Wine reports untrusted
# certificates as WinHTTP error 12157). Goes to the *user* Root store: Wine keeps the
# machine Root store in sync with the Linux CA certificates.
prefix_trust_cert() {
  local reg=$DRIVE_C/svws-cert.reg
  python3 -I - "$SVWS_PORT" "$reg" <<'EOF' || die "cannot fetch the server certificate"
import hashlib, ssl, struct, sys
der = ssl.PEM_cert_to_DER_cert(ssl.get_server_certificate(("localhost", int(sys.argv[1]))))
thumb = hashlib.sha1(der).hexdigest().upper()
blob = struct.pack("<III", 0x20, 1, len(der)) + der            # CERT_CERT_PROP_ID
key = r"HKEY_CURRENT_USER\Software\Microsoft\SystemCertificates\Root\Certificates" + "\\" + thumb
hx = ",".join(f"{b:02x}" for b in blob)
open(sys.argv[2], "w", newline="").write(f'REGEDIT4\r\n\r\n[{key}]\r\n"Blob"=hex:{hx}\r\n')
EOF
  wine regedit /S 'C:\svws-cert.reg' >/dev/null 2>&1
  rm -f "$reg"
  ok "server certificate trusted in Wine"
}

# Fonts: SchILD uses Segoe UI + Tahoma. Use Microsoft fonts from $FONT_SRC if available,
# otherwise map Segoe UI to Wine's built-in Tahoma (never to Times New Roman).
prefix_fonts() {
  local reg=$DRIVE_C/schild-fonts.reg f n count=0
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
      n=$(find "$FONT_SRC" -maxdepth 1 -iname "$f" -print -quit 2>/dev/null || true)
      [[ -n $n ]] || continue
      cp "$n" "$DRIVE_C/windows/Fonts/$f"; count=$((count + 1))
      printf '"%s (TrueType)"="%s"\r\n' "${F[$f]}" "$f"
    done
    printf '\r\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\r\n"Palatino Linotype"=-\r\n"Verdana"=-\r\n'
    if [[ -f $DRIVE_C/windows/Fonts/segoeui.ttf ]]; then
      printf '"Segoe UI"=-\r\n"Segoe UI Semibold"=-\r\n"Segoe UI Light"=-\r\n'
    else
      printf '"Segoe UI"="Tahoma"\r\n"Segoe UI Semibold"="Tahoma"\r\n"Segoe UI Light"="Tahoma"\r\n'
    fi
    printf '\r\n[HKEY_CURRENT_USER\\Control Panel\\Desktop]\r\n"FontSmoothing"="2"\r\n"FontSmoothingType"=dword:00000002\r\n"FontSmoothingGamma"=dword:00000578\r\n"FontSmoothingOrientation"=dword:00000001\r\n'
  } > "$reg"
  wine regedit /S 'C:\schild-fonts.reg' >/dev/null 2>&1
  rm -f "$reg"
  if ((count)); then ok "$count Microsoft fonts installed from $FONT_SRC"
  else warn "no Microsoft fonts in $FONT_SRC – Segoe UI is mapped to Wine's Tahoma (see README)"; fi
}

# WinHTTP request with certificate validation from inside Wine – what SchILD_DBConfig does
prefix_test() {
  cp "$ROOT/lib/winhttp_test.js" "$DRIVE_C/winhttp_test.js"
  local out
  out=$(timeout -s KILL 90 "$WINE_DIR/bin/wine" 'C:/windows/syswow64/cscript.exe' //nologo 'C:/winhttp_test.js' "$SVWS_PORT" 2>/dev/null | tr -d '\r' | tail -1) || true
  rm -f "$DRIVE_C/winhttp_test.js"
  echo "    $out"
  [[ $out == *" 200 "* ]]
}

schild_run() {  # exe
  require_prefix
  mkdir -p "$DATA/logs"
  info "starting $1 (log: data/logs/${1%.exe}.log)"
  cd "$SCHILD_DIR" && setsid "$WINE_DIR/bin/wine" "$SCHILD_DIR/$1" >"$DATA/logs/${1%.exe}.log" 2>&1 < /dev/null &
}

desktop_install() {
  require_prefix
  local apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  mkdir -p "$apps"
  write_desktop() {  # file name comment command
    cat > "$apps/$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=$ROOT/svws $4
Icon=applications-office
Terminal=false
Categories=Office;Education;
StartupWMClass=schild30.exe
EOF
  }
  write_desktop svws-schild.desktop "SchILD-NRW 3 (local)" "SchILD-NRW 3 with the local SVWS-Server" schild
  write_desktop svws-dbconfig.desktop "SchILD DBConfig (local)" "Database connections for SchILD-NRW 3" dbconfig
  ok "menu entries created in $apps"
}
