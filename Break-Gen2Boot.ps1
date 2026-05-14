<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Method: Detached Process (No Scheduled Tasks)
#>

$ErrorActionPreference = 'Stop'

# 1. Mount and Rename (The "Break")
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

Write-Host "Mounting EFI to $letter:..."
cmd /c "mountvol $($letter): /S"

$efiPath = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

if (Test-Path $efiPath) {
    # Take control from TrustedInstaller
    cmd /c "takeown /f $efiPath /a"
    cmd /c "icacls $efiPath /grant administrators:F"
    
    # Rename the file
    Move-Item -Path $efiPath -Destination "$($efiPath).bak" -Force
    Write-Host "Bootloader renamed to .bak"
} else {
    Write-Error "EFI path not found."
    exit 1
}

# 2. The Reboot (The "Detached Hammer")
# We launch a separate powershell process that sleeps for 10s then reboots.
# Because it's a separate process, it survives the end of the RunCommand session.
$rebootScript = "Start-Sleep -Seconds 10; Restart-Computer -Force"
Start-Process powershell.exe -ArgumentList "-NoProfile -Command `"$rebootScript`""

Write-Host "Reboot initiated in detached process. Reporting success to Azure..."
exit 0
