# Troubleshooting

Problems found while getting SchILD-NRW 3 to work under Wine, and what `./svws setup` does about them.

## SchILD_DBConfig: "REST failed: Fehler beim Senden der Daten: (12157)"

`12157` is `ERROR_WINHTTP_SECURE_CHANNEL_ERROR`. There are two different causes:

### 1. Broken Wine runner (soda-11.0-10)

With the Bottles default runner `soda-11.0-10`, **every** WinHTTP request fails, even plain HTTP.
`WINEDEBUG=+winhttp` shows:

```
warn:winhttp:sock_recv recv error 997
warn:winhttp:netconn_secure_connect Failed to initialize security context: 0x2f7d
```

A blocking `recv` returns `ERROR_IO_PENDING` (997). **Fix:** use the Kron4ek build
`kron4ek-wine-11.20-amd64` (`WINE_RUNNER` in `.env`). `./svws setup` downloads it into
the Bottles runner folder and assigns it to the bottle.

### 2. Untrusted (self-signed) certificate

Wine reports a failed certificate check as the same generic `12157`
(`WINEDEBUG=+winhttp`: `cert verify failed: 12045`, i.e. unknown CA). SchILD validates the
certificate strictly. The certificate the SVWS-Server generates by default also has no
SubjectAltName.

**Fix:** `./svws setup` generates its own certificate (`data/certs/svws.crt`, SAN
`localhost`, `127.0.0.1`, `::1`), writes it as the server keystore and imports it into the
**user** root store of the bottle (`HKCU\Software\Microsoft\SystemCertificates\Root`).
The machine store (`HKLM\…\Root`) is unsuitable: Wine keeps it in sync with the Linux CA
certificates. Re-import with `./svws trust-cert`.

### Registry changes get lost

Each `flatpak run` gets its own `/tmp` and therefore its own `wineserver`, which writes
registry changes to disk only a few seconds after its last process exits. A Wine call
started before that reads the old registry and can write it back. `lib/bottle.sh`
therefore runs `wineserver -w` after every Wine call.

Check from inside the bottle with `./svws test`. Expected output:
`https://localhost:8443/status/alive -> 200 SVWS-Server erreichbar`.

## SchILD installer rolls back ("RegSvr32-Aufruf scheiterte mit Exit-Code 0x3")

`drive_c/schild_setup.log` shows the registration of `IT-NRW\ASDStatistik.dll` failing,
then "Rolling back changes". `ASDStatistik.dll` is a Visual Basic 6 COM component and
needs `msvbvm60.dll`, which Wine does not provide. `./svws setup` installs it from
Microsoft's VB6 SP6 runtime (like the Bottles dependency `vbrun6`), plus Jet 4.0 SP8
(`jet40`) before running the installer.

## Font is hard to read (serif / Times)

SchILD's forms use **Segoe UI** (most of the UI) and **Tahoma**. Some bottle setups add
`HKCU\Software\Wine\Fonts\Replacements` entries `Segoe UI → Times New Roman`, so the whole
UI is rendered in a serif font.

`./svws fonts`:
- copies Microsoft fonts from `FONT_SRC` (default `~/.local/share/fonts/Microsoft`) into
  the bottle and registers them. They are not distributed with this repository; use the
  fonts from a Windows licence you own.
- without them, maps Segoe UI to Wine's built-in Tahoma (sans-serif, readable),
- removes the Times replacements and enables ClearType-like subpixel smoothing.

Restart SchILD afterwards.

## Empty white window "SchILD-NRW 3"

SchILD is a Delphi program. Its `TApplication` window (class `TApplication`, title
`SchILD-NRW 3`) has size 0×0 on Windows and only provides the taskbar button. Some Wayland
compositors show it as a normal window. On **Hyprland** it appears as a floating
794×768 white window. Check with:

```sh
WINEDEBUG=-all flatpak run --command=bash com.usebottles.bottles -c \
  "WINEPREFIX=<bottle> <runner>/bin/winedbg --command 'info wnd'"
```

**Fix (Hyprland):** add the window rule from `contrib/hyprland/` (Lua or hyprlang
config) to move the window to a hidden special workspace. Other compositors need an
equivalent "hide/minimize by class + title" rule.

## Test data was overwritten

The SVWS-Server imports the test database whenever `IMPORT_TEST_DATA=true` and the
container is **new**. `compose.yaml` therefore defaults to `false`. `./svws` sets it to
`true` only on the very first start (empty `data/mariadb`) and for `./svws reset-db`.

## SchILD crashes with `EOleException: Nicht implementiert` (ADODB)

This was seen with the `soda-11.0-10` runner (`Data.Win.ADODB.TParameter.GetDataType`
in `Documents\SchILD30.el`). It did not appear with the Kron4ek runner. If it shows up,
attach the EurekaLog file `drive_c/users/<you>/Documents/SchILD30.el` to an issue.

## Useful paths

| What | Path |
|---|---|
| Bottle | `~/.var/app/com.usebottles.bottles/data/bottles/bottles/SchILD3` |
| SchILD program | `drive_c/Program Files (x86)/SchILD-NRW3` (`server.json` = expected server version) |
| SchILD working directory | `drive_c/SVWS-Arbeitsverzeichnis` (`Connection-Files/*.con`, `Schild-Reports/`) |
| Installer log | `drive_c/schild_setup.log` |
| Server log | `./svws logs`, `data/svws/logs/` |
