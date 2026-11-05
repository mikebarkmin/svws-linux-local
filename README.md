# SVWS Linux Local

A local **SVWS-NRW test environment on Linux**, set up by one command:

- **SVWS-Server** + MariaDB in Podman, with the official test school
  ("Albert Zweistein Gymnasium")
- **SVWS-Tools** web apps (Konferenz, Import, Prognos, GradeHub, Laufbahnplanung)
- **SchILD-NRW 3** in a [Bottles](https://usebottles.com/) bottle (Wine), already
  connected to the server
- **All report collections** for SchILD-NRW 3 (base reports and report cards for
  GS, Sek I, Sek II, BK, WBK), synced from GitHub

> ⚠️ For testing, development and training only. Do not use with real school data.
> This project is not affiliated with the SVWS-NRW project or the
> Ministerium für Schule und Bildung NRW.

## Requirements

- Linux with `podman`, `podman-compose`, `flatpak`, `curl`, `git`, `openssl`, `rsync`,
  `unzip`, `cabextract`, `python3`
- Bottles from Flathub: `flatpak install flathub com.usebottles.bottles`
- Optional: Microsoft TrueType fonts (Segoe UI, Tahoma, …) from a Windows licence
  you own, in `~/.local/share/fonts/Microsoft` (see [fonts](#fonts))

## Quick start

```sh
git clone https://github.com/mikebarkmin/svws-linux-local.git
cd svws-linux-local
./svws setup        # 10–15 min on first run
./svws dbconfig     # once: create the database connection (values from the setup output)
./svws schild       # start SchILD-NRW 3
```

`./svws setup` is idempotent and can be re-run at any time. It:

1. creates `.env` with random passwords,
2. downloads the Wine runner **Kron4ek 11.20** into Bottles (the default `soda` runner
   breaks SchILD's HTTPS connection, see [troubleshooting](docs/troubleshooting.md)),
3. creates the bottle `SchILD3`, installs Microsoft Jet 4.0 SP8 and the VB6 runtime
   (needed by the SchILD installer) and installs the latest
   [SchILD-NRW 3 release](https://github.com/SVWS-NRW/Schild-NRW-3/releases) silently,
4. starts the **SVWS-Server version SchILD expects** (read from SchILD's `server.json`),
   with a generated TLS certificate, and imports the test data on the first start,
5. installs the [SVWS-Tools](https://github.com/SVWS-NRW/SVWS-Tools) web apps,
6. syncs all report collections into `C:\SVWS-Arbeitsverzeichnis\Schild-Reports`,
7. trusts the certificate inside the bottle and sets up readable fonts,
8. tests the HTTPS connection from inside the bottle, as SchILD does it.

### Connect SchILD (once)

The password in SchILD's connection file is encrypted, so the connection is created in
`SchILD_DBConfig` (`./svws dbconfig`). `./svws status` shows the values:

| Section | Field | Value |
|---|---|---|
| Datenbank | Server / Port | `localhost` / `3306` |
| | Datenbank | `svwsdb` |
| | Benutzer / Kennwort | `svwsuser` / *(from `.env`)* |
| SVWS-Server | Adresse | `localhost:8443` |

Log in to SchILD and the SVWS-Client as **`Admin` with an empty password** (test data).

## Commands

| Command | |
|---|---|
| `./svws setup` | Install or repair everything |
| `./svws update` | Update SchILD, server version, SVWS-Tools and reports |
| `./svws schild` | Start the server (if needed) and SchILD-NRW 3 |
| `./svws dbconfig` | Start SchILD_DBConfig |
| `./svws up` / `down` | Start / stop the server containers |
| `./svws status` | Versions, URLs, access data |
| `./svws logs` | Follow the server log |
| `./svws reports` | Sync the report collections only |
| `./svws tools` | Install/update the SVWS-Tools only |
| `./svws fonts` | Re-apply the font setup in the bottle |
| `./svws trust-cert` | Re-import the server certificate into the bottle |
| `./svws test` | HTTPS test from inside the bottle |
| `./svws reset-db` | Replace the database with fresh test data |

## Web

| | URL |
|---|---|
| SVWS-Client | https://localhost:8443 |
| SVWS-Tools start page | https://localhost:8443/app/start/ |
| Konferenz / Import / Prognos / GradeHub / Laufbahnplanung | `https://localhost:8443/app/{konferenz,import,prognos,gradehub,laufbahn}/` |

The browser warns about the self-signed certificate once. You can import
`data/certs/svws.crt` into your browser to avoid the warning.

The tiles on the start page are configured in `data/apps/start/sichtbarkeit.js`
(initially copied from [`config/sichtbarkeit.js`](config/sichtbarkeit.js)).

## Reports

[`config/reports.conf`](config/reports.conf) lists the collections. Each repository is
cloned to `cache/repos/`, and the files of its official release (listed in its
`.zipallow`) are copied to `C:\SVWS-Arbeitsverzeichnis\Schild-Reports\<folder>`:

| Folder | Repository |
|---|---|
| `Basisreports` | [Schild-NRW-3-Reports](https://github.com/SVWS-NRW/Schild-NRW-3-Reports) |
| `Zeugnisse Sek-I` | [Schild-NRW-3-Zeugnisse-Sek-I](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-Sek-I) |
| `Zeugnisse Sek-II` | [Schild-NRW-3-Zeugnisse-Sek-II](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-Sek-II) |
| `Zeugnisse GS` | [Schild-NRW-3-Zeugnisse-GS](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-GS) |
| `Zeugnisse BK` | [Schild-NRW-3-Zeugnisse-BK](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-BK) |
| `Zeugnisse WBK` | [Schild-NRW-3-Zeugnisse-WBK](https://github.com/SVWS-NRW/Schild-NRW-3-Zeugnisse-WBK) |
| `Legacy/…` | [Schild-NRW-Reports](https://github.com/SVWS-NRW/Schild-NRW-Reports), [Schild-NRW-Zeugnisse-Sek1](https://github.com/SVWS-NRW/Schild-NRW-Zeugnisse-Sek1), [Schild-NRW-Zeugnisse-Sek2](https://github.com/SVWS-NRW/Schild-NRW-Zeugnisse-Sek2) (older collections) |

Files are copied, not linked, because the Bottles flatpak cannot access this repository.
`./svws reports` updates them. Don't edit files in the synced folders; changes are
overwritten. Put your own reports in a separate folder.

## Fonts

SchILD uses **Segoe UI** and **Tahoma**. If `FONT_SRC` (default
`~/.local/share/fonts/Microsoft`) contains the Microsoft TrueType files, they are
copied into the bottle. Otherwise Segoe UI is mapped to Wine's built-in Tahoma. Microsoft
fonts are not part of this repository and must come from a licence you own.

## Desktop notes

- **Hyprland:** SchILD shows an extra empty window. Add the rule from
  [`contrib/hyprland/`](contrib/hyprland) to your config.
- Other desktops: see [docs/troubleshooting.md](docs/troubleshooting.md#empty-white-window-schild-nrw-3).

## Layout

```
svws                 command-line entry point
lib/                 server, bottle, report logic
compose.yaml         SVWS-Server + MariaDB (podman-compose)
.env.example         settings; copied to .env (gitignored) by setup
config/              report list, tile visibility
contrib/             desktop-specific snippets
docs/                troubleshooting
data/  (gitignored)  database, server config + keystore + logs, web apps, certificate
cache/ (gitignored)  downloads and cloned report repositories
```

## Uninstall

```sh
./svws down
podman unshare rm -rf data          # database etc. belong to the container user
rm -rf cache .env
flatpak run --command=bottles-cli com.usebottles.bottles list bottles   # then delete "SchILD3" in Bottles
```

## License

The scripts and configuration in this repository are licensed under the
[MIT License](LICENSE).

The software they download is not included and keeps its own licences:
SVWS-Server and SVWS-Tools (BSD-3-Clause), SchILD-NRW 3 and the report collections
(see the respective [SVWS-NRW repositories](https://github.com/SVWS-NRW)), the Wine
runner (LGPL), MariaDB (GPL), Microsoft Jet 4.0 and VB6 runtime (Microsoft EULA, downloaded
from Microsoft via the Internet Archive, as Bottles and winetricks do).
