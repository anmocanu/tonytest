<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Goal: Reproduce "No bootable device" black screen (Gen1 symmetry)
  Status: Synchronous Success in Azure Portal
#>

$ErrorActionPreference = 'Stop'

Write-Host "Starting Mutation: Reproducing Gen1 'No bootable device' error on Gen2..."

# 1. Find a free drive letter and mount the EFI System Partition (ESP)
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

Write-Host "Mounting EFI partition to $($letter):..."
cmd /c "mountvol $($letter): /S"

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 2. Delete the primary bootloader file
if (Test-Path $efiFile) {
    Write-Host "Wresting control of bootloader from TrustedInstaller..."
    # Give ownership to the Administrators group (/a)
    cmd /c "takeown /f $efiFile /a"
    # Grant full permissions to Administrators
    cmd /c "icacls $efiFile /grant administrators:F /c"
    
    Write-Host "Deleting bootloader to trigger 'No bootable device' error..."
    Remove-Item -Path $efiFile -Force
} else {
    Write-Error "Bootloader file not found at $efiFile. Is this a Gen2 VM?"
    exit 1
}

# 3. Clean up the mount point
cmd /c "mountvol $($letter): /D"

# 4. Create a "Self-Destruct" Scheduled Task
# This allows the script to exit NOW (Succeeding in Portal)
# and triggers the reboot in exactly 60 seconds.
$triggerTime = (Get-Date).AddSeconds(60).ToString('HH:mm')

Write-Host "Creating delayed reboot task for $triggerTime..."
cmd /c "schtasks /create /tn `"LabBreak`" /tr `"shutdown.exe /r /f /t 0`" /sc once /st $triggerTime /ru SYSTEM /rl HIGHEST /f"

Write-Output "Mutation complete. The Azure Portal will now show 'Succeeded'."
Write-Output "The VM will reboot into the 'No bootable device' error in 60 seconds."

# 5. Exit immediately with Success code
exit 0
