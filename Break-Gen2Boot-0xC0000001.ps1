<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Mounts hidden EFI partition and corrupts the raw BCD hive directly.
    - Bypasses live system file locks and bcdedit parser restrictions.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Mounting hidden EFI System Partition..."

# 2. MOUNT THE HIDDEN EFI VOLUME
# This maps the hidden FAT32 partition directly to drive letter Y:
& mountvol.exe Y: /S
Start-Sleep -Seconds 2

$targetBcd = "Y:\EFI\Microsoft\Boot\BCD"

if (Test-Path $targetBcd) {
    Write-Host "EFI Boot configuration discovered. Stripping system flags..."
    
    # Remove System, Hidden, and Read-Only attributes from the raw BCD storage file
    & cmd.exe /c "attrib -r -s -h $targetBcd"
    
    # 3. OVERWRITE THE RAW BCD FILE WITH GARBAGE BYTES
    # Writing directly to the file stream on the un-locked FAT32 volume bypasses
    # all live kernel protection layers and bcdedit binary validation filters.
    $corruptBytes = [byte[]](,0x00 * 2048)
    [System.IO.File]::WriteAllBytes($targetBcd, $corruptBytes)
    
    Write-Host "Raw BCD storage structure invalidated successfully."
} else {
    Write-Warning "Target EFI structure not discovered on volume path."
}

# 4. CLEAN UP AND REBOOT
& mountvol.exe Y: /D
Write-Host "Initiating hardware reset loop..."

& cmd.exe /c "shutdown /r /f /t 5"

exit 0
