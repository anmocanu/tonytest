<#
  Break-Gen2Boot-OSBucket.ps1
  Goal: Reproduce "No bootable device" black screen on Gen2.
#>

$ErrorActionPreference = 'Stop'

# 1. Mount the EFI Partition
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
cmd /c "mountvol $($letter): /S"

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 2. Kill the Bootloader (This triggers the "No bootable device" screen)
if (Test-Path $efiFile) {
    # We must take ownership from TrustedInstaller
    cmd /c "takeown /f $efiFile /a"
    cmd /c "icacls $efiFile /grant administrators:F /c"
    
    # Deleting it is more "final" than renaming for the firmware
    Remove-Item -Path $efiFile -Force
}

# 3. Clean up
cmd /c "mountvol $($letter): /D"

# 4. Success Buffer for Portal
Write-Host "Mutation complete. Reporting success. Rebooting in 60s..."
cmd /c "shutdown /r /f /t 60"

Start-Sleep -Seconds 5
exit 0
