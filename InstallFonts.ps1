#Requires -RunAsAdministrator

$scriptRoot     = $PSScriptRoot
$logFolderPath  = Join-Path $scriptRoot "logs"
$configFilePath = Join-Path $scriptRoot "config.json"

if (-not (Test-Path $logFolderPath)) { New-Item -ItemType Directory -Path $logFolderPath | Out-Null }

# Load or create config
if (Test-Path $configFilePath) {
    $config = Get-Content $configFilePath -Raw | ConvertFrom-Json
    $fontLibraryPath = $config.FontLibraryPath
    if ([string]::IsNullOrWhiteSpace($fontLibraryPath)) {
        $fontLibraryPath = Read-Host "FontLibraryPath in config.json is empty. Enter the full path to your fonts library folder"
        $config.FontLibraryPath = $fontLibraryPath
        $config | ConvertTo-Json | Set-Content $configFilePath
    }
} else {
    $fontLibraryPath = Read-Host "Enter the full path to your fonts library folder (e.g. D:\data-hoarding-media\installers\fonts)"
    @{ FontLibraryPath = $fontLibraryPath } | ConvertTo-Json | Set-Content $configFilePath
    Write-Host "Config saved to config.json"
}

$logFilePath = Join-Path $logFolderPath "installFonts.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $logFilePath -Value $entry
}

# Known font file magic bytes (first 4 bytes of valid font files)
$FONT_SIGNATURES = @(
    [byte[]]@(0x00, 0x01, 0x00, 0x00),  # TrueType
    [byte[]]@(0x74, 0x72, 0x75, 0x65),  # TrueType "true"
    [byte[]]@(0x4F, 0x54, 0x54, 0x4F),  # OpenType CFF "OTTO"
    [byte[]]@(0x74, 0x74, 0x63, 0x66)   # TTC collection "ttcf"
)

# Extensions that should never appear in a font ZIP
$SUSPICIOUS_EXTENSIONS = @(
    '.exe', '.dll', '.bat', '.cmd', '.ps1', '.vbs',
    '.js', '.wsf', '.hta', '.scr', '.msi', '.reg',
    '.pif', '.com', '.lnk', '.inf', '.sys'
)

$FONT_EXTENSIONS = @('.ttf', '.otf', '.ttc')

function Test-FontInstalled {
    param([string]$FontFileName)
    return Test-Path "C:\Windows\Fonts\$FontFileName"
}

function Test-FontSignature {
    param([string]$FilePath)
    try {
        $bytes = New-Object byte[] 4
        $stream = [System.IO.File]::OpenRead($FilePath)
        $read = $stream.Read($bytes, 0, 4)
        $stream.Dispose()
        if ($read -lt 4) { return $false }
        foreach ($sig in $FONT_SIGNATURES) {
            if ($bytes[0] -eq $sig[0] -and $bytes[1] -eq $sig[1] -and
                $bytes[2] -eq $sig[2] -and $bytes[3] -eq $sig[3]) {
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

# Returns a list of warning strings; empty = safe to proceed
function Get-ZipSafetyIssues {
    param([string]$ZipPath)
    $issues = @()
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    foreach ($entry in $zip.Entries) {
        if ($entry.Length -eq 0) { continue }  # skip directory entries

        # Zip slip: path traversal via ../ or ..\
        if ($entry.FullName -match '\.\.[/\\]') {
            $issues += "Path traversal entry: $($entry.FullName)"
        }

        # Executable/script files hidden inside the ZIP
        $ext = [System.IO.Path]::GetExtension($entry.FullName).ToLower()
        if ($SUSPICIOUS_EXTENSIONS -contains $ext) {
            $issues += "Suspicious file in ZIP: $($entry.FullName)"
        }
    }
    $zip.Dispose()
    return $issues
}

# Extracts only font files from a ZIP into $TempDir (never touches other content)
function Export-FontsFromZip {
    param([string]$ZipPath, [string]$TempDir)
    $extracted = @()
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    foreach ($entry in $zip.Entries) {
        $ext = [System.IO.Path]::GetExtension($entry.FullName).ToLower()
        if ($FONT_EXTENSIONS -notcontains $ext) { continue }
        if ($entry.FullName -match '\.\.[/\\]') { continue }

        $destPath = Join-Path $TempDir ([System.IO.Path]::GetFileName($entry.FullName))
        $entryStream = $entry.Open()
        $fileStream  = [System.IO.File]::Create($destPath)
        $entryStream.CopyTo($fileStream)
        $fileStream.Dispose()
        $entryStream.Dispose()
        $extracted += $destPath
    }
    $zip.Dispose()
    return $extracted
}

function Get-ZipFontEntryNames {
    param([string]$ZipPath)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    $names = @($zip.Entries |
        Where-Object { $FONT_EXTENSIONS -contains [System.IO.Path]::GetExtension($_.FullName).ToLower() } |
        ForEach-Object { [System.IO.Path]::GetFileName($_.FullName) })
    $zip.Dispose()
    return $names
}

function Install-Font {
    param([string]$FontPath)
    $fontFileName = [System.IO.Path]::GetFileName($FontPath)
    $destination  = "C:\Windows\Fonts\$fontFileName"

    Copy-Item -Path $FontPath -Destination $destination -Force

    $keyPath  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $ext      = [System.IO.Path]::GetExtension($fontFileName).ToLower()
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fontFileName)
    $suffix   = switch ($ext) {
        ".ttf" { " (TrueType)" }
        ".otf" { " (OpenType)" }
        ".ttc" { " (TrueType)" }
        default { "" }
    }
    $valueName = "$baseName$suffix"
    if (-not (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $keyPath -Name $valueName -Value $fontFileName -PropertyType String -Force | Out-Null
    }
}

function Install-FromZip {
    param([string]$ZipPath, [string]$SourceLabel)

    $zipFileName = [System.IO.Path]::GetFileName($ZipPath)
    $zipName     = [System.IO.Path]::GetFileNameWithoutExtension($ZipPath)
    $tempDir     = Join-Path $env:TEMP "FontInstaller_$zipName"

    # Safety check: scan ZIP contents before extracting anything
    $issues = Get-ZipSafetyIssues -ZipPath $ZipPath
    if ($issues.Count -gt 0) {
        Write-Log "[$SourceLabel] SKIPPED '$zipFileName' - failed safety check:" "WARN"
        foreach ($issue in $issues) {
            Write-Log "[$SourceLabel]   $issue" "WARN"
        }
        return 0
    }

    try {
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        # Extract only font files - other ZIP contents are never written to disk
        $extractedFiles = Export-FontsFromZip -ZipPath $ZipPath -TempDir $tempDir
    } catch {
        Write-Log "[$SourceLabel] Failed to extract '$zipFileName': $_" "ERROR"
        return 0
    }

    if ($extractedFiles.Count -eq 0) {
        Write-Log "[$SourceLabel] No font files found in '$zipFileName'."
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return 0
    }

    $installedNow = 0

    foreach ($filePath in $extractedFiles) {
        $fileName = [System.IO.Path]::GetFileName($filePath)

        if (Test-FontInstalled $fileName) { continue }

        # Magic bytes check: confirm the file is actually a font before installing
        if (-not (Test-FontSignature -FilePath $filePath)) {
            Write-Log "[$SourceLabel] SKIPPED '$fileName' - file signature does not match any known font format." "WARN"
            continue
        }

        try {
            Install-Font -FontPath $filePath
            Write-Log "[$SourceLabel] Installed: $fileName"
            $installedNow++
        } catch {
            Write-Log "[$SourceLabel] Failed to install '$fileName': $_" "ERROR"
        }
    }

    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    return $installedNow
}

# --- Main ---

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $fontLibraryPath)) {
    Write-Log "Font library folder not found: $fontLibraryPath" "ERROR"
    Read-Host "Press Enter to exit"
    exit 1
}

$sourceFolders = Get-ChildItem -Path $fontLibraryPath -Directory |
                 Where-Object { $_.Name -ne "installed" }

if ($sourceFolders.Count -eq 0) {
    Write-Log "No source subfolders found in '$fontLibraryPath'. Create subfolders like 'google' or 'fontesk' and add ZIPs."
    Read-Host "Press Enter to exit"
    exit 0
}

$totalInstalled = 0
$totalSkipped   = 0
$totalFailed    = 0

foreach ($sourceFolder in $sourceFolders) {
    $label        = $sourceFolder.Name
    $installedDir = Join-Path $sourceFolder.FullName "installed"

    if (-not (Test-Path $installedDir)) {
        New-Item -ItemType Directory -Path $installedDir | Out-Null
    }

    $rootZips      = @(Get-ChildItem -Path $sourceFolder.FullName -Filter "*.zip" -File)
    $installedZips = @(Get-ChildItem -Path $installedDir          -Filter "*.zip" -File)

    if ($rootZips.Count -eq 0 -and $installedZips.Count -eq 0) {
        Write-Log "[$label] No ZIPs found, skipping."
        continue
    }

    Write-Log "[$label] Scanning ($($rootZips.Count) new, $($installedZips.Count) archived)..."

    # Check archived ZIPs - reinstall any fonts missing from Windows
    foreach ($zipFile in $installedZips) {
        $fontNames = Get-ZipFontEntryNames -ZipPath $zipFile.FullName
        $missing   = $fontNames | Where-Object { -not (Test-FontInstalled $_) }

        if (-not $missing) {
            $totalSkipped += $fontNames.Count
            continue
        }

        Write-Log "[$label] '$($zipFile.Name)' has $($missing.Count) missing font(s), reinstalling."
        $count = Install-FromZip -ZipPath $zipFile.FullName -SourceLabel $label
        $totalInstalled += $count
        if ($count -lt $missing.Count) { $totalFailed += ($missing.Count - $count) }
    }

    # Process new ZIPs from root - install then archive
    foreach ($zipFile in $rootZips) {
        $fontNames = Get-ZipFontEntryNames -ZipPath $zipFile.FullName
        $missing   = $fontNames | Where-Object { -not (Test-FontInstalled $_) }

        if ($fontNames.Count -eq 0) {
            Write-Log "[$label] '$($zipFile.Name)' contains no font files, skipping."
            continue
        }

        if (-not $missing) {
            Write-Log "[$label] '$($zipFile.Name)' already fully installed, archiving."
            Move-Item -Path $zipFile.FullName -Destination $installedDir -Force
            $totalSkipped += $fontNames.Count
            continue
        }

        $count = Install-FromZip -ZipPath $zipFile.FullName -SourceLabel $label
        $totalInstalled += $count
        if ($count -lt $missing.Count) { $totalFailed += ($missing.Count - $count) }

        Move-Item -Path $zipFile.FullName -Destination $installedDir -Force
        Write-Log "[$label] Archived '$($zipFile.Name)' to /installed"
    }
}

Write-Host ""
Write-Log "Done. Installed: $totalInstalled | Already installed: $totalSkipped | Failed: $totalFailed"
Read-Host "Press Enter to exit"
