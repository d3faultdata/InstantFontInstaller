# Instant Font Installer

This project automates the installation of fonts on Windows using PowerShell. It unzips font files, installs them, and logs the process. 

## Features:
- Installs `.ttf` and `.otf` fonts from a specified folder, including font zip files.
- Automatically unzips fonts if needed.
- Keeps a record of installed fonts to prevent re-installation.
- Logs every installation process.

## Prerequisites:
- **Windows PowerShell** (comes pre-installed on most Windows systems).
- Administrator privileges to install fonts.

## Setup Instructions:
1. **Clone the repository:**
   ```bash
   git clone https://github.com/d3faultdata/InstantFontInstaller.git
   cd InstantFontInstaller
   ```

2. **Configure the font management settings:**
   - Copy `config-template.json` to `config.json`.
   - Open `config.json` and adjust the settings as needed:
     - `fontFolder`: Specify the path where your font zip files will be stored.
     - `logFile`: Set the path where you want to store the installation log.

3. **Run the font installation script:**
   - Open PowerShell as an administrator.
   - Navigate to the project directory:
     ```powershell
     cd C:\path\to\InstantFontInstaller
     ```
   - Execute the installation script:
     ```powershell
     .\InstallFonts.ps1
     ```
   - Check the log file to see the installation results. This file will include details of installed fonts and any errors encountered during the installation process.

## Usage Instructions:
- Place your font zip files in the folder specified in the `fontFolder` setting of your `config.json`.
- Run the installation script whenever you want to install the fonts from the folder.

## Contributing:
If you'd like to contribute to the project, please fork the repository and submit a pull request.

## License
This project is licensed under the MIT License - see the [LICENSE](https://opensource.org/licenses/MIT) file for details.

