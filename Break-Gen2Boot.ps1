<#
  Break-Gen2Boot-OSBucket.ps1
  Strategy: FAT32 Direct Deletion (No ACLs)
#>

$ErrorActionPreference = 'Stop'

# 1. Kill OOBE
Write-Output "Clearing OOBE blocking processes..."
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Mount EFI Partition
$letter = "S"
if (Get-PSDrive $letter -ErrorAction SilentlyContinue) {
    & cmd.exe /c "mountvol $($letter): /D"
}
& cmd.exe /c "mountvol $($letter): /S"

$efiFile = "S:\EFI\Microsoft\Boot\bootmgfw.efi"

# 3. The Mutation (FAT32 Logic)
if (Test-Path $efiFile) {
    Write-Output "Removing attributes and deleting $efiFile..."
    
    # Strip Read-Only, System, and Hidden attributes which protect the file on FAT32
    & attrib.exe -r -s -h $efiFile
    
    # Direct deletion
    Remove-Item -Path $efiFile -Force
    
    # VERIFICATION
    if (Test-Path $efiFile) {
        Write-Error "Critical Failure: File still exists after deletion attempt."
        exit 1
    } else {
        Write-Output "Success: Bootloader file removed."
    }
} else {
    Write-Error "Error: Bootloader not found at $efiFile."
    exit 1
}

# 4. Final Cleanup and Shutdown
& cmd.exe /c "mountvol $($letter): /D"
Write-Output "Reporting success. Triggering reboot in 10 seconds..."

# Shortened timer to ensure it hits before Windows tries to repair itself
& cmd.exe /c "shutdown /r /f /t 10"
Start-Sleep -Seconds 5
exit 0
