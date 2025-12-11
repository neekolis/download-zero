$ErrorActionPreference = "Stop"

$downloads = "$env:USERPROFILE\Downloads"
$docFolder = "$downloads\Documents"
$testFile = "$downloads\verif_test.pdf"
$targetFile = "$docFolder\verif_test.pdf"

# Cleanup
Write-Host "Cleaning up..."
if (Test-Path $testFile) { Remove-Item $testFile -Force }
if (Test-Path $targetFile) { Remove-Item $targetFile -Force }
if (!(Test-Path $downloads)) { New-Item -ItemType Directory -Path $downloads }
if (!(Test-Path $docFolder)) { New-Item -ItemType Directory -Path $docFolder }

# Start Application
Write-Host "Starting Sortify..."
$appProcess = Start-Process -FilePath ".\Sortify.exe" -PassThru
Start-Sleep -Seconds 3

# Create Test File
Write-Host "Creating test file: $testFile"
"dummy content" | Set-Content $testFile

# Wait for Sort
Write-Host "Waiting for sorting..."
Start-Sleep -Seconds 5

# Verify
if (Test-Path $targetFile) {
    Write-Host "SUCCESS: File moved to $targetFile"
}
else {
    Write-Host "FAILURE: File not found at $targetFile"
    if (Test-Path $testFile) { Write-Host "File still exists at source." }
}

# Stop Application
Write-Host "Stopping Sortify..."
Stop-Process -Id $appProcess.Id -Force
