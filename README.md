# SVWS Linux Local

A local **SVWS-NRW test environment on Linux**, set up by one command:

- **SVWS-Server** + MariaDB in Podman, with the official test school
  ("Albert Zweistein Gymnasium")
- **SVWS-Tools** web apps (Konferenz, Import, Prognos, GradeHub, Laufbahnplanung)
- **SchILD-NRW 3** in Wine, already trusting the server
- **All report collections** for SchILD-NRW 3 (base reports and report cards for
  GS, Sek I, Sek II, BK, WBK), straight from GitHub

> ⚠️ For testing, development and training only. Do not use with real school data.
> This project is not affiliated with the SVWS-NRW project or the
> Ministerium für Schule und Bildung NRW.

## Requirements

Only three programs are needed. Everything else, including Wine, is downloaded into this folder:

| Program | Arch | Debian / Ubuntu | Fedora |
|---|---|---|---|
| podman | `pacman -S podman` | `apt install podman` | preinstalled |
| curl, python3 | usually preinstalled | `apt install curl python3` | preinstalled |

- x86_64 Linux desktop (X11 or Wayland)
- The Wine build is self-contained and needs no 32-bit system libraries. It uses common
  desktop libraries (GnuTLS, FreeType, fontconfig), which every desktop distribution ships.
- Optional: Microsoft TrueType fonts (Segoe UI, Tahoma, …) from a Windows licence you
  own, in `~/.local/share/fonts/Microsoft` (see [fonts](#fonts)).

## Quick start

```sh
git clone https://github.com/mikebarkmin/svws-linux-local.git
cd svws-linux-local
./svws setup        # ~5 min, downloads ~400 MB
./svws dbconfig     # once: create the database connection (values from the setup output)
./svws schild       # start SchILD-NRW 3
./svws desktop      # optional: menu entries
```

`./svws setup` can be re-run at any time. It:

1. creates `.env` with random passwords,
2. downloads a portable Wine build ([Kron4ek](https://github.com/Kron4ek/Wine-Builds)
   11.20 wow64) to `cache/wine` and creates the Wine prefix `data/prefix`,
3. installs Microsoft Jet 4.0 SP8, MDAC 2.8 SP1 (ADO) and the VB6 runtime, which SchILD
   needs,
4. installs the latest [SchILD-NRW 3 release](https://github.com/SVWS-NRW/Schild-NRW-3/releases)
   silently,
5. starts the **SVWS-Server version SchILD expects** (read from SchILD's `server.json`)
   and imports the test data on the first start,
6. installs the [SVWS-Tools](https://github.com/SVWS-NRW/SVWS-Tools) web apps,
7. links all report collections into `C:\SVWS-Arbeitsverzeichnis\Schild-Reports`,
8. makes Wine trust the server certificate and sets up readable fonts,
9. tests the HTTPS connection from inside Wine, as SchILD does it.

### Connect SchILD (once)

SchILD stores the connection with an encrypted password, so it is created in
`SchILD_DBConfig` (`./svws dbconfig`). `./svws status` shows the values:

| Section | Field | Value |
|---|---|---|
| Datenbank | Server / Port | `localhost` / `3306` |
| | Datenbank | `svwsdb` |
| | Benutzer / Kennwort | `svwsuser` / `svwspass` |
| SVWS-Server | Adresse | `localhost:8443` |

Log in to SchILD and the SVWS-Client as **`Admin` with an empty password** (test data).

## Commands

| Command | |
|---|---|
| `./svws setup` | Install or repair everything |
| `./svws update` | Update SchILD, server version, SVWS-Tools and reports |
| `./svws schild` | Start the server (if needed) and SchILD-NRW 3 |
| `./svws dbconfig` | Start SchILD_DBConfig |
| `./svws desktop` | Add menu entries for SchILD and DBConfig |
| `./svws up` / `down` | Start / stop the server |
| `./svws status` | Versions, URLs, access data |
| `./svws logs` | Follow the server log |
| `./svws reports` | Update the report collections only |
| `./svws tools` | Install/update the SVWS-Tools only |
| `./svws fonts` | Re-apply the font setup |
| `./svws trust-cert` | Re-import the server certificate into Wine |
| `./svws test` | HTTPS test from inside Wine |
| `./svws reset-db` | Replace the database with fresh test data |
| `./svws wine …` | Run a command in the Wine prefix, e.g. `./svws wine winecfg` |

## Web

| | URL |
|---|---|
| SVWS-Client | https://localhost:8443 |
| SVWS-Tools start page | https://localhost:8443/app/start/ |
| Konferenz / Import / Prognos / GradeHub / Laufbahnplanung | `https://localhost:8443/app/{konferenz,import,prognos,gradehub,laufbahn}/` |

The server uses a self-signed certificate. The browser warns once.

The tiles on the start page are set in `data/apps/start/sichtbarkeit.js`
(initially copied from [`config/sichtbarkeit.js`](config/sichtbarkeit.js)).

## Reports

[`config/reports.conf`](config/reports.conf) lists the collections. Each repository is
downloaded to `cache/reports/<repo>`, and the files of its official release (listed in its
`.zipallow`) are **linked** into `C:\SVWS-Arbeitsverzeichnis\Schild-Reports\<folder>`:

| Folder | Repository |
|---|---|
| `Basisreports` | [Schild-NRW-3-Reports](https://github.com/SVWS-NRW/Schild-NRW-3-Reports) |
| `Zeugnisse Sek-I` | [Schild-NRW-3-Zeugnisse-Sek-I](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-Sek-I) |
| `Zeugnisse Sek-II` | [Schild-NRW-3-Zeugnisse-Sek-II](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-Sek-II) |
| `Zeugnisse GS` | [Schild-NRW-3-Zeugnisse-GS](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-GS) |
| `Zeugnisse BK` | [Schild-NRW-3-Zeugnisse-BK](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-BK) |
| `Zeugnisse WBK` | [Schild-NRW-3-Zeugnisse-WBK](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-WBK) |
| `Legacy/…` | [Schild-NRW-Reports](https://github.com/SVWS-NRW/Schild-NRW-Reports), [Schild-NRW-Zeugnisse-Sek1](https://github.com/SVWS-NRW/Schild-NRW-Zeugnisse-Sek1), [Schild-NRW-Zeugnisse-Sek2](https://github.com/SVWS-NRW/Schild-NRW-Zeugnisse-Sek2) (older collections) |

`./svws reports` downloads a collection again only when its repository has new commits.
An update replaces everything in the linked folders, so keep your own reports in a
separate folder.

## Fonts

SchILD uses **Segoe UI** and **Tahoma**. If `FONT_SRC` (default
`~/.local/share/fonts/Microsoft`) contains the Microsoft TrueType files, they are copied
into the prefix. Otherwise Segoe UI is mapped to Wine's built-in Tahoma. Microsoft fonts
are not part of this repository; take them from a Windows licence you own.

## Desktop notes

- **Hyprland:** SchILD shows an extra empty window. Add the rule from
  [`contrib/hyprland/`](contrib/hyprland) to your config.
- More problems and their causes: [docs/troubleshooting.md](docs/troubleshooting.md).

## Layout

```
svws                 command-line entry point
lib/                 wine, server and report logic
.env.example         settings; copied to .env (gitignored) by setup
config/              report list, tile visibility
contrib/             desktop-specific snippets
docs/                troubleshooting
data/  (gitignored)  Wine prefix, database, server config + keystore + logs, web apps
cache/ (gitignored)  downloads, Wine build, report collections
```

## Uninstall

```sh
./svws down
podman pod rm -f svws-local
podman unshare rm -rf data          # database files belong to the container user
rm -rf cache .env ~/.local/share/applications/svws-*.desktop
```

## License

The scripts and configuration in this repository are licensed under the
[MIT License](LICENSE).

The software they download is not included and keeps its own licences:
SVWS-Server and SVWS-Tools (BSD-3-Clause), SchILD-NRW 3 and the report collections
(see the respective [SVWS-NRW repositories](https://github.com/SVWS-NRW)), Wine (LGPL),
MariaDB (GPL), Microsoft Jet 4.0, MDAC 2.8 and VB6 runtime (Microsoft EULA, downloaded from
Microsoft via the Internet Archive, as winetricks does).
