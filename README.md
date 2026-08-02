# Instant Font Installer

Automatically installs `.ttf`, `.otf`, and `.ttc` fonts from ZIP archives organised by source.  
Fonts are tracked by source (Google Fonts, Fontesk, paid, etc.) and archived after installation so your library can be used to reinstall everything on a new or recovered machine.

## Folder structure

```
D:\data-hoarding-media\installers\fonts\   ← FontLibraryPath in config.json
├── google\
│   ├── roboto.zip                         ← new, will be installed
│   └── installed\
│       └── noto.zip                       ← already installed, kept as backup
├── fontesk\
│   └── installed\
│       └── archivo.zip
└── paid\
    ├── new-purchase.zip
    └── installed\
```

- Drop new font ZIPs into the **source subfolder root** (`google\`, `fontesk\`, etc.)
- After installation the ZIP is **moved to `/installed`** — not deleted
- Source subfolders are discovered automatically; add as many as you like

## Reinstall / new machine

Just copy the entire library folder to the new machine and run the tool.  
It scans `/installed` too, detects which fonts are missing from Windows, and reinstalls them automatically.

## Setup

1. Copy `config-template.json` → `config.json`
2. Set `FontLibraryPath` to your fonts library root
3. Double-click `RunInstallFonts.bat`

On first run without a `config.json` you will be prompted to enter the path.

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (built-in) or PowerShell 7+
- Administrator privileges (the launcher requests elevation automatically)

## License

MIT — see [LICENSE](LICENSE)
