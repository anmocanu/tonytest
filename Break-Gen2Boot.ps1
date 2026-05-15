<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Strategy: Kill OOBE + Direct File Deletion + Synchronous Reboot
#>

$ErrorActionPreference = 'Stop'

# 1. Force-kill the OOBE process to clear the 'Diagnostic Data' screen barrier
Write-Output "Clearing OOBE blocking processes..."
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Mount EFI Partition
$letter = "S"
if (Get-PSDrive $letter -ErrorAction SilentlyContinue) {
    & cmd.exe /c "mountvol $($letter): /D"
}
& cmd.exe /c "mountvol $($letter): /S"

$efiFile = "S:\EFI\Microsoft\Boot\bootmgfw.efi"

# 3. The Mutation
if (Test-Path $efiFile) {
    Write-Output "Applying mutation to $efiFile..."
    & cmd.exe /c "takeown /f $efiFile /a"
    & cmd.exe /c "icacls $efiFile /grant administrators:F /c"
    Remove-Item -Path $efiFile -Force
    Write-Output "Success: Bootloader file removed."
} else {
    Write-Error "Error: Bootloader not found at $efiFile."
    exit 1
}

# 4. Final Cleanup and Shutdown
& cmd.exe /c "mountvol $($letter): /D"
Write-Output "Reporting success. Triggering reboot in 30 seconds..."

# Synchronous reboot call
& cmd.exe /c "shutdown /r /f /t 30"
Start-Sleep -Seconds 15
exit 0
