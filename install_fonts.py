#!/usr/bin/env python3
"""InstantFontInstaller - cross-platform batch font installer.

Installs .ttf/.otf/.ttc fonts from ZIP archives that are organized into
per-source subfolders (google, fontesk, paid, ...). ZIPs are never deleted:
after a successful install each archive is moved into an "installed/" subfolder
within its source, so the whole library stays portable and can reinstall itself
on a fresh or recovered machine.

Runs on Windows (system-wide, needs admin), Linux and macOS (per-user, no admin).
All paths are resolved relative to this script, so the folder can be relocated.

Keep this file ASCII-only.
"""

import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "config.json"
LOG_DIR = SCRIPT_DIR / "logs"
LOG_FILE = LOG_DIR / "install_fonts.log"

IS_WINDOWS = os.name == "nt"
IS_MAC = sys.platform == "darwin"
IS_LINUX = not IS_WINDOWS and not IS_MAC

FONT_EXTENSIONS = (".ttf", ".otf", ".ttc")

# Extensions that should never appear inside a font ZIP.
SUSPICIOUS_EXTENSIONS = {
    ".exe", ".dll", ".bat", ".cmd", ".ps1", ".vbs",
    ".js", ".wsf", ".hta", ".scr", ".msi", ".reg",
    ".pif", ".com", ".lnk", ".inf", ".sys",
}

# First bytes of a valid font file (magic-bytes validation before install).
FONT_SIGNATURES = (
    b"\x00\x01\x00\x00",  # TrueType
    b"true",              # TrueType ("true")
    b"OTTO",              # OpenType with CFF outlines
    b"ttcf",              # TrueType collection
)

# Matches a zip-slip path-traversal segment ("../" or "..\").
TRAVERSAL_RE = re.compile(r"\.\.[/\\]")


# --- Logging ---------------------------------------------------------------

def write_log(message, level="INFO"):
    entry = "{0} [{1}] {2}".format(
        datetime.now().strftime("%Y-%m-%d %H:%M:%S"), level, message
    )
    print(entry)
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as handle:
            handle.write(entry + "\n")
    except OSError:
        pass


# --- Platform helpers ------------------------------------------------------

def font_install_dir():
    """Return the directory where fonts are installed on this OS."""
    if IS_WINDOWS:
        return Path(os.environ.get("SystemRoot", r"C:\Windows")) / "Fonts"
    if IS_MAC:
        return Path.home() / "Library" / "Fonts"
    return Path.home() / ".local" / "share" / "fonts"


def is_windows_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False


def refresh_font_cache():
    """Rebuild the font cache so new fonts are visible (Linux only)."""
    if not IS_LINUX:
        return
    fc_cache = shutil.which("fc-cache")
    if not fc_cache:
        write_log("fc-cache not found; new fonts may need a session restart.", "WARN")
        return
    try:
        subprocess.run(
            [fc_cache, "-f", str(font_install_dir())],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        write_log("Failed to run fc-cache: {0}".format(exc), "WARN")


# --- Config / storage location --------------------------------------------

def read_config():
    try:
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def write_config(config):
    CONFIG_FILE.write_text(json.dumps(config, indent=4), encoding="utf-8")


def default_library_path():
    if IS_WINDOWS:
        return r"D:\data-hoarding-media\installers\fonts"
    return str(Path.home() / "data-hoarding-media" / "installers" / "fonts")


def prompt_for_library_path():
    if not sys.stdin or not sys.stdin.isatty():
        write_log(
            "No font library configured. Set FontLibraryPath in config.json, "
            "or the FONT_LIBRARY_PATH environment variable.",
            "ERROR",
        )
        sys.exit(1)
    example = default_library_path()
    return input(
        "Enter the full path to your fonts library folder "
        "(e.g. {0}): ".format(example)
    ).strip()


def resolve_library_path():
    """Resolve the font library folder by cascade: config -> env -> default.

    Mirrors the yt-dlp setup: a per-machine config file wins, then an
    environment variable, then a per-OS default. Prompts and saves config
    only when nothing usable is found.
    """
    # 1. config.json (user-local, git-ignored)
    if CONFIG_FILE.exists():
        config = read_config()
        value = str(config.get("FontLibraryPath", "")).strip()
        if value:
            return value
        value = prompt_for_library_path()
        config["FontLibraryPath"] = value
        write_config(config)
        write_log("Saved font library path to config.json")
        return value

    # 2. FONT_LIBRARY_PATH environment variable
    env_value = os.environ.get("FONT_LIBRARY_PATH", "").strip()
    if env_value:
        return env_value

    # 3. per-OS default if it already exists, otherwise prompt once
    default = default_library_path()
    if Path(default).is_dir():
        return default

    value = prompt_for_library_path()
    write_config({"FontLibraryPath": value})
    write_log("Saved font library path to config.json")
    return value


# --- Font detection --------------------------------------------------------

def is_font_installed(font_file_name):
    """A font is installed if a file of that name exists in the OS font dir."""
    return (font_install_dir() / font_file_name).exists()


def has_font_signature(path):
    try:
        with open(path, "rb") as handle:
            head = handle.read(4)
    except OSError:
        return False
    if len(head) < 4:
        return False
    return any(head.startswith(sig) for sig in FONT_SIGNATURES)


# --- ZIP handling ----------------------------------------------------------

def _entry_basename(name):
    return os.path.basename(name.replace("\\", "/"))


def zip_safety_issues(zip_path):
    """Return a list of warning strings; an empty list means safe to proceed."""
    issues = []
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename
            # Zip slip: path traversal, absolute path, or a drive letter.
            if (
                TRAVERSAL_RE.search(name)
                or name.startswith(("/", "\\"))
                or (len(name) > 1 and name[1] == ":")
            ):
                issues.append("Path traversal entry: {0}".format(name))
            ext = os.path.splitext(name)[1].lower()
            if ext in SUSPICIOUS_EXTENSIONS:
                issues.append("Suspicious file in ZIP: {0}".format(name))
    return issues


def extract_fonts(zip_path, temp_dir):
    """Extract only font files into temp_dir. Other content is never written."""
    extracted = []
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            name = info.filename
            if os.path.splitext(name)[1].lower() not in FONT_EXTENSIONS:
                continue
            if TRAVERSAL_RE.search(name):
                continue
            base = _entry_basename(name)
            if not base:
                continue
            dest = temp_dir / base
            with archive.open(info) as source, open(dest, "wb") as target:
                shutil.copyfileobj(source, target)
            extracted.append(dest)
    return extracted


def zip_font_names(zip_path):
    names = []
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            if os.path.splitext(info.filename)[1].lower() in FONT_EXTENSIONS:
                base = _entry_basename(info.filename)
                if base:
                    names.append(base)
    return names


# --- Installation ----------------------------------------------------------

def register_font_windows(file_name):
    """Add the registry value that makes a font known to Windows."""
    import winreg

    base = os.path.splitext(file_name)[0]
    ext = os.path.splitext(file_name)[1].lower()
    suffix = {
        ".ttf": " (TrueType)",
        ".otf": " (OpenType)",
        ".ttc": " (TrueType)",
    }.get(ext, "")
    value_name = base + suffix
    key = winreg.OpenKey(
        winreg.HKEY_LOCAL_MACHINE,
        r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
        0,
        winreg.KEY_SET_VALUE | winreg.KEY_QUERY_VALUE,
    )
    try:
        try:
            winreg.QueryValueEx(key, value_name)
            already = True
        except FileNotFoundError:
            already = False
        if not already:
            winreg.SetValueEx(key, value_name, 0, winreg.REG_SZ, file_name)
    finally:
        winreg.CloseKey(key)


def install_font(font_path):
    dest_dir = font_install_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    file_name = os.path.basename(str(font_path))
    shutil.copy2(font_path, dest_dir / file_name)
    if IS_WINDOWS:
        register_font_windows(file_name)


def install_from_zip(zip_path, source_label):
    """Install every not-yet-installed font from one ZIP. Return count installed."""
    zip_file_name = os.path.basename(str(zip_path))
    zip_stem = Path(zip_path).stem

    issues = zip_safety_issues(zip_path)
    if issues:
        write_log(
            "[{0}] SKIPPED '{1}' - failed safety check:".format(source_label, zip_file_name),
            "WARN",
        )
        for issue in issues:
            write_log("[{0}]   {1}".format(source_label, issue), "WARN")
        return 0

    temp_dir = Path(tempfile.mkdtemp(prefix="FontInstaller_{0}_".format(zip_stem)))
    try:
        try:
            extracted = extract_fonts(zip_path, temp_dir)
        except (OSError, zipfile.BadZipFile) as exc:
            write_log(
                "[{0}] Failed to extract '{1}': {2}".format(source_label, zip_file_name, exc),
                "ERROR",
            )
            return 0

        if not extracted:
            write_log("[{0}] No font files found in '{1}'.".format(source_label, zip_file_name))
            return 0

        installed_now = 0
        for font_path in extracted:
            file_name = os.path.basename(str(font_path))
            if is_font_installed(file_name):
                continue
            if not has_font_signature(font_path):
                write_log(
                    "[{0}] SKIPPED '{1}' - file signature does not match any known "
                    "font format.".format(source_label, file_name),
                    "WARN",
                )
                continue
            try:
                install_font(font_path)
                write_log("[{0}] Installed: {1}".format(source_label, file_name))
                installed_now += 1
            except Exception as exc:  # noqa: BLE001 - report and keep going
                write_log(
                    "[{0}] Failed to install '{1}': {2}".format(source_label, file_name, exc),
                    "ERROR",
                )
        return installed_now
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


# --- Main ------------------------------------------------------------------

def main():
    if IS_WINDOWS and not is_windows_admin():
        write_log(
            "Administrator privileges are required to install fonts system-wide "
            "on Windows. Run install-fonts.cmd, which elevates automatically.",
            "ERROR",
        )
        pause_if_interactive()
        sys.exit(1)

    library_path = Path(resolve_library_path())
    if not library_path.is_dir():
        write_log("Font library folder not found: {0}".format(library_path), "ERROR")
        pause_if_interactive()
        sys.exit(1)

    source_folders = [
        child
        for child in sorted(library_path.iterdir(), key=lambda p: p.name.lower())
        if child.is_dir() and child.name != "installed"
    ]
    if not source_folders:
        write_log(
            "No source subfolders found in '{0}'. Create subfolders like 'google' "
            "or 'fontesk' and add ZIPs.".format(library_path)
        )
        pause_if_interactive()
        return

    total_installed = 0
    total_skipped = 0
    total_failed = 0

    for source_folder in source_folders:
        label = source_folder.name
        installed_dir = source_folder / "installed"
        installed_dir.mkdir(parents=True, exist_ok=True)

        root_zips = sorted(source_folder.glob("*.zip"))
        archived_zips = sorted(installed_dir.glob("*.zip"))

        if not root_zips and not archived_zips:
            write_log("[{0}] No ZIPs found, skipping.".format(label))
            continue

        write_log(
            "[{0}] Scanning ({1} new, {2} archived)...".format(
                label, len(root_zips), len(archived_zips)
            )
        )

        # Archived ZIPs: reinstall any fonts missing from this machine.
        for zip_file in archived_zips:
            font_names = zip_font_names(zip_file)
            missing = [name for name in font_names if not is_font_installed(name)]
            if not missing:
                total_skipped += len(font_names)
                continue
            write_log(
                "[{0}] '{1}' has {2} missing font(s), reinstalling.".format(
                    label, zip_file.name, len(missing)
                )
            )
            count = install_from_zip(zip_file, label)
            total_installed += count
            if count < len(missing):
                total_failed += len(missing) - count

        # New ZIPs from the source root: install, then archive.
        for zip_file in root_zips:
            font_names = zip_font_names(zip_file)
            missing = [name for name in font_names if not is_font_installed(name)]

            if not font_names:
                write_log(
                    "[{0}] '{1}' contains no font files, skipping.".format(label, zip_file.name)
                )
                continue

            if not missing:
                write_log(
                    "[{0}] '{1}' already fully installed, archiving.".format(label, zip_file.name)
                )
                shutil.move(str(zip_file), str(installed_dir / zip_file.name))
                total_skipped += len(font_names)
                continue

            count = install_from_zip(zip_file, label)
            total_installed += count
            if count < len(missing):
                total_failed += len(missing) - count

            shutil.move(str(zip_file), str(installed_dir / zip_file.name))
            write_log("[{0}] Archived '{1}' to /installed".format(label, zip_file.name))

    refresh_font_cache()

    print("")
    write_log(
        "Done. Installed: {0} | Already installed: {1} | Failed: {2}".format(
            total_installed, total_skipped, total_failed
        )
    )
    pause_if_interactive()


def pause_if_interactive():
    if IS_WINDOWS and sys.stdin and sys.stdin.isatty():
        try:
            input("Press Enter to exit")
        except EOFError:
            pass


if __name__ == "__main__":
    main()
