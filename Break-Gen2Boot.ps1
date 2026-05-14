<#
  Break-Gen2Boot-OSBucket.ps1
  Purpose: 
    - Simulate "OS Bucket / Boot Failure" (No Bootable Device) for Gen2 VMs.
    - Renames the UEFI bootloader so the firmware cannot find it.
    - Target: https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/os-bucket-boot-failure
#>

$ErrorActionPreference = 'Stop'

# 1. Identify a free drive letter to mount the hidden EFI System Partition (ESP)
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

Write-Host "Mounting EFI partition to $letter:..."
# The /S switch mounts the ESP of the local machine
cmd /c "mountvol $($letter): /S"

$efiPath = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 2. Rename the Bootloader
if (Test-Path $efiPath) {
    Write-Host "Taking ownership and granting permissions for $efiPath"
    # bootmgfw.efi is protected; ownership is required to rename it as SYSTEM
    takeown /f $efiPath
    icacls $efiPath /grant administrators:F
    
    Write-Host "Renaming bootloader to simulate OS Bucket Failure..."
    Rename-Item -Path $efiPath -NewName "bootmgfw.efi.bak" -Force
} else {
    Write-Error "Critical Error: EFI Bootloader not found at $efiPath. This may not be a Gen2 VM."
    exit 1
}

# 3. Clean up the mount point
cmd /c "mountvol $($letter): /D"

# 4. Trigger Reboot via Background Job
# Using a background job ensures the script reports "Success" to the Azure Agent 
# before the OS shuts down.
Start-Job -ScriptBlock { 
    Start-Sleep -Seconds 10
    Stop-Computer -Force 
}

Write-Host "Mutation complete. VM will reboot in 10 seconds to manifest failure."
exit 0
