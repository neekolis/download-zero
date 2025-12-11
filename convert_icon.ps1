param($source, $dest)

Add-Type -AssemblyName System.Drawing

$img = [System.Drawing.Bitmap]::FromFile($source)
$thumb = $img.GetThumbnailImage(64, 64, $null, [IntPtr]::Zero)
$iconHandle = $thumb.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($iconHandle)

$fs = New-Object System.IO.FileStream $dest, "Create"
$icon.Save($fs)
$fs.Close()

$icon.Dispose()
$thumb.Dispose()
$img.Dispose()
