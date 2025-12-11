Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Configuration ---
$configFile = Join-Path $PSScriptRoot "config.json"
$global:paused = $false
$global:debug = $false # Start disabled for production

# --- Auto-Update ---
$appVersion = "1.1.2"
$updateUrl = "https://raw.githubusercontent.com/neekolis/download-zero/main/version.json"

# --- Icon Embedding ---
# --- Icon Embedding ---
# (Removed in v1.1.2: Using native system icons instead)


# --- Single Instance Check ---
$mutexName = "Global\DownloadZeroAppMutex"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) {
    [System.Windows.Forms.MessageBox]::Show("DownloadZero is already running.", "DownloadZero", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# Get actual Downloads folder path from Registry (handles redirected folders)
try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $downloadsGuid = "{374DE290-123F-4565-9164-39C4925E467B}"
    $downloadsPath = (Get-ItemProperty -Path $regPath).$downloadsGuid
    
    if (-not $downloadsPath) {
        # Fallback to GUID-less lookup or standard name
        $downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    }
}
catch {
    $downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
}

$global:rules = @{}

$logFile = Join-Path $PSScriptRoot "debug.log"

function Write-Log($msg) {
    if ($global:debug) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $msg" | Out-File -FilePath $logFile -Append
    }
}

$global:setupComplete = $false

function Import-Config {
    Write-Log "Loading configuration..."
    if (Test-Path $configFile) {
        try {
            $jsonContent = Get-Content $configFile -Raw
            $json = $jsonContent | ConvertFrom-Json
            
            $global:rules = @{}
            $rulesRaw = $null

            # Handle Schema Migration (Array -> Object)
            if ($json -is [System.Array]) {
                $rulesRaw = $json
                $global:setupComplete = $false
            }
            else {
                $rulesRaw = $json.Rules
                $global:setupComplete = $json.SetupComplete
            }

            foreach ($item in $rulesRaw) {
                # Ensure extension starts with .
                $ext = $item.Extension
                if (-not $ext.StartsWith(".")) { $ext = "." + $ext }
                $global:rules[$ext.ToLower()] = $item.Folder
            }
            Write-Log "Config loaded. Rules count: $($global:rules.Count)"
        }
        catch {
            Write-Log "Error loading config: $_"
            Get-Default-Rules
        }
    }
    else {
        Write-Log "Config file not found. Creating defaults."
        Get-Default-Rules
    }
}

function Get-Default-Rules {
    $global:rules = @{
        ".pdf"  = "Documents"
        ".docx" = "Documents"
        ".doc"  = "Documents"
        ".txt"  = "Documents"
        ".jpg"  = "Images"
        ".png"  = "Images"
        ".jpeg" = "Images"
        ".gif"  = "Images"
        ".zip"  = "Archives"
        ".rar"  = "Archives"
        ".exe"  = "Executables"
        ".msi"  = "Executables"
        ".ics"  = "Calendar Items"
        ".vcs"  = "Calendar Items"
    }
    Export-Config # Create the file
}

function Export-Config {
    $ruleList = @()
    foreach ($key in $global:rules.Keys) {
        $ruleList += @{ Extension = $key; Folder = $global:rules[$key] }
    }
    
    $configData = @{
        SetupComplete = $global:setupComplete
        Rules         = $ruleList
    }

    $configData | ConvertTo-Json -Depth 5 | Set-Content $configFile
}

function Test-Shortcut {
    if ($global:setupComplete) { return }

    $shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DownloadZero.lnk"
    
    if (-not (Test-Path $shortcutPath)) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Would you like to add DownloadZero to your Start Menu?", 
            "First Run Setup", 
            [System.Windows.Forms.MessageBoxButtons]::YesNo, 
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq "Yes") {
            try {
                $WshShell = New-Object -comObject WScript.Shell
                $Shortcut = $WshShell.CreateShortcut($shortcutPath)
                $Shortcut.TargetPath = "powershell.exe"
                $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\DownloadZero.ps1`""
                $Shortcut.WorkingDirectory = "$PSScriptRoot"
                $Shortcut.WorkingDirectory = "$PSScriptRoot"
                $Shortcut.IconLocation = "shell32.dll,4" # Standard Folder Icon
                $Shortcut.Description = "Automatically sorts files in Downloads"
                $Shortcut.Save()
                [System.Windows.Forms.MessageBox]::Show("Shortcut created!", "DownloadZero")
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to create shortcut.`n$_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    }
    
    # Mark setup as complete so we don't ask again (unless config is deleted)
    $global:setupComplete = $true
    Export-Config
}

# --- Settings UI ---

function Get-Update($manual = $false) {
    try {
        $webClient = New-Object System.Net.WebClient
        $jsonStr = $webClient.DownloadString($updateUrl)
        $json = $jsonStr | ConvertFrom-Json
        
        $remoteVersion = [System.Version]$json.version
        $localVersion = [System.Version]$appVersion

        if ($remoteVersion -gt $localVersion) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "A new version of DownloadZero is available ($remoteVersion).`n`nUpdate now?", 
                "Update Available", 
                [System.Windows.Forms.MessageBoxButtons]::YesNo, 
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($result -eq "Yes") {
                Invoke-Update $json.url
            }
        }
        elseif ($manual) {
            [System.Windows.Forms.MessageBox]::Show("You are up to date! (Version $appVersion)", "DownloadZero")
        }
    }
    catch {
        if ($manual) {
            [System.Windows.Forms.MessageBox]::Show("Process failed to check for updates.`n$_", "Update Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
}

function Invoke-Update($scriptUrl) {
    try {
        $tempFile = Join-Path $env:TEMP "DownloadZero_New.ps1"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($scriptUrl, $tempFile)

        # Verify download
        if (Test-Path $tempFile) {
            # Create a self-updater batch file to handle the swap while this process dies
            $batchPath = Join-Path $env:TEMP "update_downloadzero.bat"
            $currentScript = $PSCommandPath
            
            $batchContent = @"
@echo off
timeout /t 2 /nobreak >nul
move /y "$tempFile" "$currentScript"
start "" powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$currentScript"
del "%~f0"
"@
            $batchContent | Out-File $batchPath -Encoding ASCII
            
            Start-Process $batchPath -WindowStyle Hidden
            
            # Exit this instance
            $notifyIcon.Visible = $false
            $watcher.EnableRaisingEvents = $false
            [System.Windows.Forms.Application]::Exit()
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Update failed.`n$_", "Update Error")
    }
}

function Show-Unsorted {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Manage Unsorted Files"
    $form.Size = New-Object System.Drawing.Size(500, 500)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(12, 12)
    $grid.Size = New-Object System.Drawing.Size(460, 400)
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.ColumnHeadersHeightSizeMode = "AutoSize"
    $grid.AllowUserToAddRows = $false # We populate from files
    
    $colExt = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colExt.HeaderText = "Unsorted Extension"
    $colExt.Name = "Extension"
    $colExt.ReadOnly = $true
    $grid.Columns.Add($colExt) | Out-Null

    $colFolder = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $colFolder.HeaderText = "Assign to Folder"
    $colFolder.Name = "Folder"
    # Populate folders from existing rules
    $uniqueFolders = $global:rules.Values | Select-Object -Unique | Sort-Object
    foreach ($f in $uniqueFolders) {
        $colFolder.Items.Add($f) | Out-Null
    }
    $grid.Columns.Add($colFolder) | Out-Null

    # Scan for unsorted
    $files = Get-ChildItem -Path $downloadsPath -File
    $unsortedExts = @{}
    foreach ($file in $files) {
        $ext = $file.Extension.ToLower()
        # Check if ext is not empty AND not in rules
        if (-not [string]::IsNullOrEmpty($ext) -and -not $global:rules.ContainsKey($ext)) {
            $unsortedExts[$ext] = $true # Use hash for unique set
        }
    }

    if ($unsortedExts.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No unsorted files found in Downloads!", "DownloadZero")
        return
    }

    foreach ($ext in $unsortedExts.Keys) {
        $grid.Rows.Add($ext, $null) | Out-Null
    }

    $form.Controls.Add($grid)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save Rules"
    $btnSave.Location = New-Object System.Drawing.Point(316, 420)
    $btnSave.DialogResult = "OK"
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(397, 420)
    $btnCancel.DialogResult = "Cancel"
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()

    if ($result -eq "OK") {
        $changesMade = $false
        foreach ($row in $grid.Rows) {
            $e = $row.Cells["Extension"].Value
            $f = $row.Cells["Folder"].Value
            
            if ([string]::IsNullOrWhiteSpace($f) -eq $false) {
                # User selected a folder
                $global:rules[$e] = $f
                $changesMade = $true
            }
        }
        
        if ($changesMade) {
            Export-Config
            Invoke-DownloadScan
            [System.Windows.Forms.MessageBox]::Show("Rules saved and files sorted!", "DownloadZero")
        }
    }
}

function Show-Settings {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "DownloadZero Settings"
    $form.Size = New-Object System.Drawing.Size(500, 500)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(12, 12)
    $grid.Size = New-Object System.Drawing.Size(460, 400)
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.ColumnHeadersHeightSizeMode = "AutoSize"
    
    $colFolder = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colFolder.HeaderText = "Folder Name"
    $colFolder.Name = "Folder"
    $colFolder.FillWeight = 40
    $grid.Columns.Add($colFolder) | Out-Null

    $colExt = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colExt.HeaderText = "Extensions (comma separated)"
    $colExt.Name = "Extensions"
    $colExt.FillWeight = 60
    $grid.Columns.Add($colExt) | Out-Null

    # Group existing rules by folder
    $grouped = @{}
    foreach ($ext in $global:rules.Keys) {
        $folder = $global:rules[$ext]
        if (-not $grouped.ContainsKey($folder)) {
            $grouped[$folder] = @()
        }
        $grouped[$folder] += $ext
    }

    # Populate Grid
    foreach ($folder in $grouped.Keys) {
        $extList = $grouped[$folder] -join ", "
        $grid.Rows.Add($folder, $extList) | Out-Null
    }

    $form.Controls.Add($grid)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(316, 420)
    $btnSave.DialogResult = "OK"
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(397, 420)
    $btnCancel.DialogResult = "Cancel"
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()

    if ($result -eq "OK") {
        $newRules = @{}
        foreach ($row in $grid.Rows) {
            if (-not $row.IsNewRow) {
                $f = $row.Cells["Folder"].Value
                $eRaw = $row.Cells["Extensions"].Value

                if ([string]::IsNullOrWhiteSpace($f) -eq $false -and [string]::IsNullOrWhiteSpace($eRaw) -eq $false) {
                    # Split by comma
                    $extensions = $eRaw -split ","
                    foreach ($extTrim in $extensions) {
                        $e = $extTrim.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($e)) {
                            if (-not $e.StartsWith(".")) { $e = "." + $e }
                            $newRules[$e.ToLower()] = $f
                        }
                    }
                }
            }
        }
        $global:rules = $newRules
        Export-Config
        Invoke-DownloadScan
    }
}

# --- Logic ---

function Invoke-FileSort($filePath) {
    if ($global:paused) { return }
    if (!(Test-Path -LiteralPath $filePath -PathType Leaf)) { return }

    $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
    if ($global:rules.ContainsKey($ext)) {
        try {
            $folderName = $global:rules[$ext]
            Write-Log "Processing $filePath -> $folderName"
            $targetDir = Join-Path $downloadsPath $folderName
            
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir | Out-Null
            }

            $fileName = [System.IO.Path]::GetFileName($filePath)
            $targetPath = Join-Path $targetDir $fileName

            # Duplicate handling
            $count = 1
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
            while (Test-Path $targetPath) {
                $newName = "$baseName ($count)$ext"
                $targetPath = Join-Path $targetDir $newName
                $count++
            }

            # Wait for file handle release
            Start-Sleep -Milliseconds 10
            
            Move-Item -LiteralPath $filePath -Destination $targetPath -Force -ErrorAction Stop
            Write-Log "Moved to $targetPath"
        }
        catch {
            Write-Log "Error moving file: $_"
        }
    }
}

function Invoke-DownloadScan {
    if ($global:paused) { return }
    Write-Log "Scanning Downloads folder: $downloadsPath"
    try {
        # Use .NET EnumerateFiles for v1.1 performance
        $files = [System.IO.Directory]::EnumerateFiles($downloadsPath)
        Write-Log "Scanning..."
        foreach ($file in $files) {
            Invoke-FileSort $file
        }
    }
    catch {
        Write-Log "Error scanning: $_"
    }
}

# --- Initialization ---

Import-Config
Test-Shortcut
Invoke-DownloadScan

# --- Watcher ---

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $downloadsPath
$watcher.Filter = "*.*"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = {
    $path = $Event.SourceEventArgs.FullPath
    Invoke-FileSort $path
}

Register-ObjectEvent $watcher "Created" -Action $action | Out-Null
Register-ObjectEvent $watcher "Renamed" -Action $action | Out-Null

# --- UI ---

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon

$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application

$notifyIcon.Text = "DownloadZero"
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenu

# Menu: Pause Sorting
$menuItemPause = $contextMenu.MenuItems.Add("Pause Sorting")
$menuItemPause.add_Click({
        $global:paused = -not $global:paused
        $menuItemPause.Checked = $global:paused
        if ($global:paused) {
            $notifyIcon.Text = "DownloadZero (Paused)"
            $notifyIcon.BalloonTipTitle = "DownloadZero Paused"
            $notifyIcon.BalloonTipText = "File sorting temporarily paused."
            $notifyIcon.ShowBalloonTip(3000)
        }
        else {
            $notifyIcon.Text = "DownloadZero"
            $notifyIcon.BalloonTipTitle = "DownloadZero Resumed"
            $notifyIcon.BalloonTipText = "Scanning for files..."
            $notifyIcon.ShowBalloonTip(3000)
            Invoke-DownloadScan # Catch up on anything missed
        }
    })

$contextMenu.MenuItems.Add("-")

# Menu: Run on Startup
$startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\DownloadZero.lnk"

$menuItemStartup = $contextMenu.MenuItems.Add("Run on Startup")
# Check if already in startup
if (Test-Path $startupPath) { $menuItemStartup.Checked = $true }

$menuItemStartup.add_Click({
        if ($menuItemStartup.Checked) {
            # Remove
            Remove-Item $startupPath -ErrorAction SilentlyContinue
            $menuItemStartup.Checked = $false
        }
        else {
            # Add (Copy existing shortcut if possible, or create new)
            $currentShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DownloadZero.lnk"
            if (Test-Path $currentShortcut) {
                Copy-Item $currentShortcut $startupPath -Force
            }
            else {
                # Fallback creation if main shortcut missing
                $WshShell = New-Object -comObject WScript.Shell
                $Shortcut = $WshShell.CreateShortcut($startupPath)
                $Shortcut.TargetPath = "powershell.exe"
                $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\DownloadZero.ps1`""
                $Shortcut.WorkingDirectory = "$PSScriptRoot"
                $Shortcut.IconLocation = "shell32.dll,4"
                $Shortcut.Save()
            }
            $menuItemStartup.Checked = $true
        }
    })

$contextMenu.MenuItems.Add("-")

$menuItemSettings = $contextMenu.MenuItems.Add("Settings...")
$menuItemSettings.add_Click({
        Show-Settings
    })

$menuItemUnsorted = $contextMenu.MenuItems.Add("Manage Unsorted...")
$menuItemUnsorted.add_Click({
        Show-Unsorted
    })

$contextMenu.MenuItems.Add("-")

$menuItemScan = $contextMenu.MenuItems.Add("Scan Now")
$menuItemScan.add_Click({
        Invoke-DownloadScan
        $notifyIcon.BalloonTipTitle = "Scan Complete"
        $notifyIcon.BalloonTipText = "Downloads folder scanned."
        $notifyIcon.ShowBalloonTip(3000)
    })

$contextMenu.MenuItems.Add("-")

$menuItemUpdate = $contextMenu.MenuItems.Add("Check for Updates")
$menuItemUpdate.add_Click({
        Get-Update -manual $true
    })

$contextMenu.MenuItems.Add("-")

$menuItemOpen = $contextMenu.MenuItems.Add("Open Downloads")
$menuItemOpen.add_Click({
        Invoke-Item $downloadsPath
    })

$contextMenu.MenuItems.Add("-")

$menuItemExit = $contextMenu.MenuItems.Add("Exit")
$menuItemExit.add_Click({
        $notifyIcon.Visible = $false
        $watcher.EnableRaisingEvents = $false
        [System.Windows.Forms.Application]::Exit()
    })

$notifyIcon.ContextMenu = $contextMenu

# Keep script running
[System.Windows.Forms.Application]::Run()
