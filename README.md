# Batch Installer Pro v1.0 🚀

> **A modern, high-performance, self-contained silent software deployment tool for Windows with automated engine detection and custom voice alerts.**

Developed with ❤️ by **Pranab Chourasiya**

---

## 🌟 Key Features

* **⚡ Standalone Executable (`BatchInstaller.exe`)**: Runs natively without requiring external PowerShell console windows or manual execution policy changes.
* **🎙️ Voice Alerts**: Built-in Text-To-Speech notifications:
  * **Success**: *"Shukriya malik"* (Plays upon 100% successful batch installation).
  * **Error / Warning**: *"Gadbad ho gayi malik"* (Plays whenever an installer fails or encounters an exception).
  * Toggleable via the **`[x] Voice Alerts`** checkbox in the top navigation bar.
* **🎨 Modern Dark Mode GUI**: Built using Windows Forms with custom dark theme styling (`#1E1E1E`), clean typography, real-time filtering, formatted binary file sizes (MB/GB), and visual progress tracking.
* **🔍 Automated Engine Detection & Argument Sniffing**: Uses high-performance stream reading to inspect binary headers without loading multi-gigabyte files into RAM.
* **🛡️ Smart Folder Relocation**: On first run, safely copies setup binaries to `Downloads\lab softwares` to prevent accidental loss or locked files.
* **📊 Windows Exit Code Mapping**: Translates standard Windows Installer return codes (e.g., `0 = SUCCESS`, `3010 = REBOOT REQUIRED`, `1602 = CANCELLED`, `1603 = FATAL ERROR`, `1618 = IN PROGRESS`).
* **📝 Real-time Terminal Console & Logging**: Live timestamped logs displayed in an in-app terminal window and saved to `InstallLog.txt`.

---

## 🛠️ Supported Installer Engines & Default Silent Flags

| Installer Engine | Detection Method | Default Silent Arguments |
| :--- | :--- | :--- |
| **Windows Installer (MSI)** | `.msi` Extension | `/qn /norestart` |
| **Inno Setup** | Binary String Sniffing | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| **NSIS (Nullsoft)** | Binary String Sniffing | `/S` |
| **InstallShield** | Binary String Sniffing | `/s /v"/qn"` |
| **WiX Burn** | Binary String Sniffing | `/quiet /norestart` |
| **7-Zip SFX** | Binary String Sniffing | `-y` |
| **BitRock Installer** | Binary String Sniffing | `/mode unattended` |
| **Squirrel** | Binary String Sniffing | `--silent` |
| **Chromium / Chrome / Edge** | Binary String Sniffing | `/silent /install` |
| **Wise Installer** | Binary String Sniffing | `/s` |
| **Generic / Custom** | Fallback | `/S` |

---

## 🚀 Quick Start & Usage

1. **Place Installers**: Put `BatchInstaller.exe` (or `BatchInstaller.ps1`) in the same folder as your `.exe` and `.msi` setup binaries.
2. **Launch Application**: Double-click `BatchInstaller.exe`.
   *(It automatically requests Administrator privileges via Windows UAC)*.
3. **Select & Customize**:
   * Use the **Filter** box to quickly search for specific installers.
   * Check or uncheck installers to include/exclude them.
   * Modify the **Silent Installation Arguments** in the grid if custom switches are required.
4. **Start Deployment**: Click **🚀 Install Selected** and watch progress live in the log console.

---

## 🏗️ Repository Architecture

```
├── BatchInstaller.exe          # Standalone compiled Windows GUI application
├── BatchInstaller.ps1          # Core PowerShell WinForms GUI source script
├── Run-BatchInstaller.bat      # Quick launcher script with execution policy bypass
├── Compile-BatchInstallerExe.ps1# C# .NET compiler script to rebuild BatchInstaller.exe
├── README.md                   # Project documentation
├── LICENSE                     # MIT License
└── .gitignore                  # Git ignore rules
```

---

## 🔧 Building from Source

To compile `BatchInstaller.ps1` into a fresh `BatchInstaller.exe` binary:

```powershell
powershell -ExecutionPolicy Bypass -File .\Compile-BatchInstallerExe.ps1
```

*(Uses the built-in Windows .NET C# compiler `csc.exe` — no third-party build tools required!)*

---

## 📄 License & Restrictions

This project is licensed under a **Custom Non-Commercial & No-Resale License** - see the [LICENSE](LICENSE) file for full details.

### 🚫 Restrictions Summary:
- **No Commercial Use / Revenue Generation**: You may not use this software for commercial monetization or paid services without written consent.
- **No Resale or Sublicensing**: Selling, leasing, or bundling this software for money is strictly prohibited.
- **No Unauthorized Derivative Resale**: Any modified versions must retain author credits (**Made by Pranab Chourasiya**) and remain 100% free and non-commercial.

Developed by **Pranab Chourasiya**
