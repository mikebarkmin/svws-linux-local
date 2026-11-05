# Troubleshooting

Problems found while getting SchILD-NRW 3 to work under Wine, and how `./svws setup`
handles them.

## SchILD_DBConfig: "REST failed: Fehler beim Senden der Daten: (12157)"

`12157` is `ERROR_WINHTTP_SECURE_CHANNEL_ERROR`. Two different causes produce it.

### Untrusted (self-signed) certificate

Wine reports a failed certificate check as the generic `12157`. With
`WINEDEBUG=+winhttp` you see `cert verify failed: 12045` (unknown CA). SchILD validates
the certificate strictly.

**Fix:** `./svws trust-cert` fetches the server certificate and imports it into the
**user** root store of the prefix (`HKCU\Software\Microsoft\SystemCertificates\Root`).
The machine store (`HKLM\…\Root`) does not work for this, because Wine keeps it in sync
with the Linux CA certificates. Run it again whenever the server certificate changes,
e.g. after deleting `data/svws/keystore`.

### Broken Wine build

With Bottles' default runner `soda-11.0-10`, **every** WinHTTP request failed, even plain
HTTP. `WINEDEBUG=+winhttp` showed `sock_recv recv error 997`: a blocking `recv`
returned `ERROR_IO_PENDING`. The Kron4ek build used here (`WINE_URL` in `.env`) does not
have this problem.

Check from inside Wine with `./svws test`. Expected output:
`https://localhost:8443/status/alive -> 200 SVWS-Server erreichbar`.

## SchILD installer rolls back ("RegSvr32-Aufruf scheiterte mit Exit-Code 0x3")

`data/prefix/drive_c/schild_setup.log` shows the registration of
`IT-NRW\ASDStatistik.dll` failing, followed by "Rolling back changes".
`ASDStatistik.dll` is a Visual Basic 6 COM component and needs `msvbvm60.dll`, which Wine
does not provide. `./svws setup` extracts it from Microsoft's VB6 SP6 runtime package. It
also installs Jet 4.0 SP8, both before running the SchILD installer.

## Font is hard to read (serif / Times)

SchILD's forms use **Segoe UI** for most of the UI, plus **Tahoma**. Without these fonts, or
with `HKCU\Software\Wine\Fonts\Replacements` entries such as `Segoe UI → Times New Roman`
(added by some Bottles dependencies), the UI is rendered in a serif font.

`./svws fonts`:
- copies Microsoft fonts from `FONT_SRC` (default `~/.local/share/fonts/Microsoft`)
  into the prefix and registers them,
- without them, maps Segoe UI to Wine's built-in Tahoma (sans-serif, readable),
- removes Times replacements and enables subpixel smoothing.

Restart SchILD afterwards.

## Empty white window "SchILD-NRW 3"

SchILD is a Delphi program. Its `TApplication` window (class `TApplication`, title
`SchILD-NRW 3`) has size 0×0 on Windows and only provides the taskbar button. Some Wayland
compositors show it as a normal window. On **Hyprland** it appears as a floating
794×768 white window. List the windows with:

```sh
./svws wine winedbg --command 'info wnd'
```

**Fix (Hyprland):** add the window rule from `contrib/hyprland/` to move the window to a
hidden special workspace. Other compositors need an equivalent rule that hides the window
by class `schild30.exe` and title `SchILD-NRW 3`.

## Test data was overwritten

The SVWS-Server imports the test database whenever `IMPORT_TEST_DATA=true` and the
container is **new**. `./svws` sets it only on the very first start (empty
`data/mariadb`) and for `./svws reset-db`.

## SchILD crashes on start with `EOleException: Nicht implementiert` (ADODB)

SchILD shows "Ein Fehler ist aufgetreten" and the EurekaLog file
`data/prefix/drive_c/users/$USER/Documents/SchILD30.el` contains
`Data.Win.ADODB … TParameter.GetDataType`. Wine's built-in ADO (`msado15`) does not
implement `Parameter.Type`. `./svws setup` installs Microsoft's MDAC 2.8 SP1 and sets
`msado15`, `msdasql` and `oledb32` to `native,builtin`.

## Useful paths

| What | Path |
|---|---|
| Wine prefix | `data/prefix` |
| SchILD program | `data/prefix/drive_c/Program Files (x86)/SchILD-NRW3` (`server.json` = expected server version) |
| SchILD working directory | `data/prefix/drive_c/SVWS-Arbeitsverzeichnis` (`Connection-Files/*.con`, `Schild-Reports/`) |
| SchILD output | `data/logs/SchILD30.log` |
| Installer log | `data/prefix/drive_c/schild_setup.log` |
| Server log | `./svws logs`, `data/svws/logs/` |
