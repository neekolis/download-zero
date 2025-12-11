# DownloadZero

**DownloadZero** is a tiny, customizable utility that automatically sorts your Downloads folder on Windows. It sits in your system tray and organizes files into subfolders based on your rules.

## Features
- **Automatic Sorting**: Files are sorted instantly when they arrive in Downloads.
- **Smart Path Detection**: Automatically finds your Downloads folder, even if redirected.
- **System Tray Icon**: Quick access to options and settings.
- **Auto-Update**: Checks for new versions on startup.
- **Extensions**: Customizable rules for any file type.

## Installation
Currently distributed as a PowerShell script.

1. Download `DownloadZero.ps1`.
2. Right-click and run with PowerShell (or use the provided shortcut installer).

## Configuration
Rules are stored in `config.json`. You can manage them via the tray menu "Settings".

## Developing
This utility is written in PowerShell and uses Windows Forms for the UI, meaning it has zero external dependencies!
