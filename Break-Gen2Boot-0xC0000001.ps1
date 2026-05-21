<#
Break-Gen2-0xC0000001.ps1
Purpose:
- Force Boot Manager failure (not kernel failure)
- Trigger 0xC0000001 reliably in Gen2
#>

$ErrorActionPreference = 'Stop'

$drive = "S:"
$bcdPath = "$drive\EFI\Microsoft\Boot\BCD"

Write-Host "Mounting EFI partition..."
cmd /c "mountvol $drive /S"

if (!(Test-Path $bcdPath)) {
    Write-Error "BCD not found at $bcdPath"
    exit 1
}

Write-Host "Taking ownership..."
takeown /f $bcdPath | Out-Null
icacls $bcdPath /grant administrators:F | Out-Null

Write-Host "Corrupting BCD (not deleting)..."

# IMPORTANT: corrupt content, do NOT remove file
[System.IO.File]::WriteAllText($bcdPath, "BADBCD")

Write-Host "Setting boot policy to expose real failure..."
bcdedit /set {default} bootstatuspolicy IgnoreAllFailures
bcdedit /set {default} recoveryenabled No

Write-Host "Rebooting..."
shutdown /r /f /t 10
