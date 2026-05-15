<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Strategy: Settlement Delay (to clear OOBE) + Synchronous Mutation
#>

$ErrorActionPreference = 'Stop'

# 1. SETTLEMENT DELAY 
# Windows Server 2025 needs time to clear the 'Diagnostic Data' and OOBE screens.
Write-Output "Waiting 180 seconds for OOBE and Guest Agent stabilization..."
Start-Sleep -Seconds 180

# 2. Mount EFI Partition
Write-Output "Mounting EFI Partition..."
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
& cmd.exe /c "mountvol $($letter): /S"

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 3. The Mutation (Gen1 Symmetry)
if (Test-Path $efiFile) {
    Write-Output "Taking ownership and deleting bootloader..."
    & cmd.exe /c "takeown /f $efiFile /a"
    & cmd.exe /c "icacls $efiFile /grant administrators:F /c"
    Remove-Item -Path $efiFile -Force
    Write-Output "Success: Bootloader file removed."
}
else {
    Write-Error "Error: Bootloader file not found at $efiFile."
    exit 1
}

# 4. Cleanup and Shutdown
& cmd.exe /c "mountvol $($letter): /D"

Write-Output "Mutation complete. Reporting SUCCESS to Azure Portal."
Write-Output "The VM will reboot into the 'No bootable device' error in 30 seconds."

# Using a synchronous shutdown with a wait to ensure the Agent reports status first.
& cmd.exe /c "shutdown /r /f /t 30"

# Keep the session open for 15 seconds to let the Agent flush logs
Start-Sleep -Seconds 15

exit 0
