<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Final Synchronous Version
#>

$ErrorActionPreference = 'Stop'

# 1. Mount the EFI Partition
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

Write-Host "Mounting EFI to $letter:..."
cmd /c "mountvol $($letter): /S"

$efiPath = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 2. Force Permissions and Rename
if (Test-Path $efiPath) {
    Write-Host "Wresting control from TrustedInstaller..."
    # /A gives ownership to the Administrators group
    cmd /c "takeown /f $efiPath /a"
    # Grant Full control
    cmd /c "icacls $efiPath /grant administrators:F /c"
    
    Write-Host "Renaming bootloader..."
    # We use move with -Force to ensure it overwrites if needed
    Move-Item -Path $efiPath -Destination "$($efiPath).bak" -Force
} else {
    Write-Error "Bootloader not found at $efiPath"
    exit 1
}

# 3. Verify Mutation locally before rebooting
if (Test-Path "$($efiPath).bak") {
    Write-Host "Mutation Verified. Proceeding to reboot."
} else {
    Write-Error "Mutation failed. File still exists as original."
    exit 1
}

# 4. The "Hammer" - Forced Reboot
# We use shutdown.exe /r /f /t 5. 
# This gives the Azure Agent 5 seconds to send 'Success' back before the OS kills the network.
Write-Host "System will reboot in 5 seconds. Deployment might show 'Failed' but the VM will be broken."
cmd /c "shutdown /r /f /t 5 /c `"LabBox: Simulating OS Bucket Failure`""

# Sleep to ensure the script doesn't exit before the shutdown command registers
Start-Sleep -Seconds 10
