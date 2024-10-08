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
1. **Navigate to your desired location using a terminal:**
   - Use the `cd` command to change directories. For example:
     - If you want to navigate to a folder named "Projects" on your C drive, use:
       ```bash
       cd C:\path\to\Projects
       ```
   - Replace `C:\path\to\Projects` with the actual path where you want to clone the repository.

2. **Clone the repository:**
   Use the following command to clone the repository:
   ```bash
   git clone https://github.com/d3faultdata/InstantFontInstaller.git

3. **Configure the font management settings:**
   - The first time you run the installation script, you will be guided through the configuration process.
   - During this process, specify the path where your font zip files will be stored.

4. **Run the font installation script:**
   - Simply double-click the RunInstallFonts.bat file to execute the installation process.

## Usage Instructions:
- Place your font zip files in the folder specified in the `fontFolder` setting of your `config.json`.
- Run the installation script by double-clicking the RunInstallFonts.bat file whenever you want to install the fonts from the folder.

## Contributing:
If you'd like to contribute to the project, please fork the repository and submit a pull request.

## License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/d3faultdata/InstantFontInstaller/blob/main/LICENSE) file for details.