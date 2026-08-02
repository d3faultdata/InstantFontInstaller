# Instant Font Installer

Automatically installs `.ttf`, `.otf`, and `.ttc` fonts from ZIP archives organised by source.
Fonts are tracked by source (Google Fonts, Fontesk, paid, etc.) and archived after installation so your library can be used to reinstall everything on a new or recovered machine.

Cross-platform: a single Python script runs on **Windows, Linux, and macOS**. The whole folder is portable — every path is resolved relative to the script, so you can drop it on a USB stick or clone it anywhere and it just works.

## Folder structure

```
<FontLibraryPath>/                         <- your fonts library root
|-- google/
|   |-- roboto.zip                         <- new, will be installed
|   `-- installed/
|       `-- noto.zip                       <- already installed, kept as backup
|-- fontesk/
|   `-- installed/
|       `-- archivo.zip
`-- paid/
    |-- new-purchase.zip
    `-- installed/
```

- Drop new font ZIPs into the **source subfolder root** (`google/`, `fontesk/`, etc.)
- After installation the ZIP is **moved to `installed/`** — never deleted
- Source subfolders are discovered automatically; add as many as you like

## Where fonts get installed

| OS      | Install location                         | Privileges         |
|---------|------------------------------------------|--------------------|
| Windows | `C:\Windows\Fonts` (system-wide, all users) | Administrator (auto-elevated) |
| Linux   | `~/.local/share/fonts` (then `fc-cache`) | Normal user        |
| macOS   | `~/Library/Fonts`                        | Normal user        |

A font counts as installed when a file of that name already exists in the OS font
folder, so re-running is always safe.

## Reinstall / new machine

Just copy the entire library folder to the new machine and run the tool.
It scans `installed/` too, detects which fonts are missing on the current machine,
and reinstalls them automatically from the archived ZIPs.

## Setup

Requires **Python 3.7+** (pre-installed on most Linux/macOS; on Windows get it from
[python.org](https://www.python.org)).

**Windows:** double-click `install-fonts.cmd` (it requests admin automatically).

**Linux / macOS:**

```sh
./install-fonts
```

## Choosing the library folder

The library path is resolved in this order (first match wins):

1. **`config.json`** — copy `config-template.json` to `config.json` and set
   `FontLibraryPath`. This file is per-machine and git-ignored.
2. **`FONT_LIBRARY_PATH`** environment variable — handy for scripting/automation.
3. **A per-OS default** if neither is set:
   `D:\data-hoarding-media\installers\fonts` on Windows,
   `~/data-hoarding-media/installers/fonts` elsewhere.

If none of these resolves to an existing folder on first run, you are prompted for
the path and it is saved to `config.json`.

## Safety

Font archives are downloaded from all over the web, so every ZIP is vetted before
anything touches your system:

- **Pre-extraction scan** — a ZIP containing any executable/script file
  (`.exe`, `.dll`, `.bat`, `.ps1`, ...) is rejected wholesale.
- **Zip-slip guard** — entries with path traversal, absolute paths, or drive
  letters are refused.
- **Selective extraction** — only `.ttf`/`.otf`/`.ttc` files are ever written to
  disk; all other archive contents are ignored.
- **Magic-bytes validation** — a file's first bytes must match a known font
  signature before it is installed.

## License

MIT — see [LICENSE](LICENSE)
