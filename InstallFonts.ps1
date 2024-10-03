# Define paths for logs and installed fonts record
$logFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "logs"
$installedFontsRecordPath = Join-Path -Path $PSScriptRoot -ChildPath "installedFontsRecord.txt"
$configFilePath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"

# Ensure logs directory exists
if (-not (Test-Path -Path $logFolderPath)) {
    New-Item -ItemType Directory -Path $logFolderPath | Out-Null
}

# Ensure installed fonts record exists
if (-not (Test-Path -Path $installedFontsRecordPath)) {
    New-Item -ItemType File -Path $installedFontsRecordPath -Force | Out-Null
}

# Load configuration or prompt for fonts folder path
if (Test-Path -Path $configFilePath) {
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    $fontsFolderPath = $config.FontsFolderPath
} else {
    $fontsFolderPath = Read-Host "Enter the full path for the fonts folder:"
    # Save the configuration to a JSON file
    $config = @{
        FontsFolderPath = $fontsFolderPath
    }
    $config | ConvertTo-Json | Set-Content -Path $configFilePath
}

# Define log file path
$logFilePath = Join-Path -Path $logFolderPath -ChildPath "installFonts.log"

function Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

function Add-FontToRegistry {
    param (
        [string]$fontPath
    )
    
    $fontName = [System.IO.Path]::GetFileName($fontPath)
    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    if ($fontName -match "\.ttf$") {
        $valueName = $fontName.Replace(".ttf", "")
    } elseif ($fontName -match "\.otf$") {
        $valueName = $fontName.Replace(".otf", "")
    } else {
        return
    }

    $existingFont = Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue
    if (!$existingFont) {
        New-ItemProperty -Path $keyPath -Name $valueName -Value $fontName -PropertyType String -Force | Out-Null
    }
}

function Get-FontFamilyName {
    param (
        [string]$fontFileName
    )

    $fontFamily = $fontFileName -replace '\d+|[_-]', ' ' -replace '\s+', ' ' -replace 'VF|VF', ''
    return $fontFamily.Trim()
}

function Is-FontInstalled {
    param (
        [string]$fontFileName
    )

    $fontName = [System.IO.Path]::GetFileNameWithoutExtension($fontFileName)
    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $existingFont = Get-ItemProperty -Path $keyPath -Name $fontName -ErrorAction SilentlyContinue

    return $existingFont -ne $null
}

function Get-ZipFontFiles {
    param (
        [string]$zipFilePath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipFilePath)
    $fontFiles = @()

    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -match "\.ttf$" -or $entry.FullName -match "\.otf$") {
            $fontFiles += $entry.FullName
        }
    }

    $zip.Dispose()
    return $fontFiles
}

# Record installed fonts
$installedFonts = Get-Content -Path $installedFontsRecordPath -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() }
$newFontFamilies = @()
$recordUpdated = $false

# Function to record already installed fonts from the folder
function Record-InstalledFonts {
    param (
        [string]$fontsFolder
    )

    $fontFiles = Get-ChildItem -Path $fontsFolder -Recurse -Include *.ttf, *.otf

    foreach ($fontFile in $fontFiles) {
        if ($installedFonts -notcontains $fontFile.Name -and (Is-FontInstalled -fontFileName $fontFile.Name)) {
            Add-Content -Path $installedFontsRecordPath -Value $fontFile.Name | Out-Null
            $installedFonts += $fontFile.Name
            $recordUpdated = $true
        }
    }
}

if (Test-Path -Path $fontsFolderPath) {
    Record-InstalledFonts -fontsFolder $fontsFolderPath

    if ($recordUpdated) {
        Log "Updated installed fonts record with existing fonts."
    }

    $zipFiles = Get-ChildItem -Path $fontsFolderPath -Filter *.zip
    $unzipNeeded = $false

    foreach ($zipFile in $zipFiles) {
        $unzipDestination = Join-Path -Path $fontsFolderPath -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($zipFile.Name))
        $fontFilesInZip = Get-ZipFontFiles -zipFilePath $zipFile.FullName
        $allFontsInstalled = $true

        foreach ($fontFile in $fontFilesInZip) {
            $fontFileName = [System.IO.Path]::GetFileName($fontFile)
            if (-not (Is-FontInstalled -fontFileName $fontFileName)) {
                $allFontsInstalled = $false
                $unzipNeeded = $true
                break
            }
        }

        if ($allFontsInstalled) {
            Remove-Item -Path $zipFile.FullName -Force | Out-Null
            continue
        } else {
            if (-not (Test-Path -Path $unzipDestination)) {
                New-Item -ItemType Directory -Path $unzipDestination | Out-Null
            }

            try {
                Expand-Archive -Path $zipFile.FullName -DestinationPath $unzipDestination -Force | Out-Null
                Remove-Item -Path $zipFile.FullName -Force | Out-Null
            } catch {
                continue
            }
        }
    }

    if ($unzipNeeded) {
        $fontFiles = Get-ChildItem -Path $fontsFolderPath -Recurse -Include *.ttf, *.otf

        if ($fontFiles.Count -eq 0) {
            Log "No font files found in $fontsFolderPath or its subfolders."
        }

        foreach ($fontFile in $fontFiles) {
            if ($installedFonts -contains $fontFile.Name) {
                continue
            }

            $fontDestinationPath = "C:\Windows\Fonts\$($fontFile.Name)"

            if (Is-FontInstalled -fontFileName $fontFile.Name) {
                continue
            } else {
                try {
                    Copy-Item -Path $fontFile.FullName -Destination $fontDestinationPath -Force | Out-Null
                } catch {
                    continue
                }

                Add-FontToRegistry -fontPath $fontDestinationPath

                $fontFamily = Get-FontFamilyName -fontFileName $fontFile.Name
                if (-not $newFontFamilies.Contains($fontFamily)) {
                    $newFontFamilies += $fontFamily
                }

                Add-Content -Path $installedFontsRecordPath -Value $fontFile.Name | Out-Null
            }
        }

        if ($newFontFamilies.Count -gt 0) {
            Log "New fonts successfully installed:"
            foreach ($fontFamily in $newFontFamilies) {
                Log "- $fontFamily"
            }
        } else {
            Log "No new fonts were installed."
        }
    } else {
        Log "No new fonts to unzip and install."
    }
} else {
    Log "Fonts folder not found."
}

# Keep the console open until user presses a key
Read-Host "Press Enter to exit..."
