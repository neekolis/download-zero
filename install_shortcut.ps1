$WshShell = New-Object -comObject WScript.Shell
$ShortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DownloadZero.lnk"

# Target is PowerShell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\DownloadZero.ps1`""
$Shortcut.WorkingDirectory = "$PSScriptRoot"
$Shortcut.IconLocation = "shell32.dll,4" 
$Shortcut.Description = "Automatically sorts files in Downloads"
$Shortcut.Save()

Write-Host "Shortcut created at: $ShortcutPath"
