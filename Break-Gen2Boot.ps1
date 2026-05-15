<#
  Break-Gen2Boot-OSBucket.ps1
  Method: Registry RunOnce + Immediate Threaded Shutdown
  Goal: Success in Portal + Gen2 "No bootable device" error
#>

$ErrorActionPreference = 'Stop'

# 1. Mount and Delete the Bootloader (The Mutation)
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
mountvol "$($letter):" /S

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

if (Test-Path $efiFile) {
    takeown /f $efiFile /a
    icacls $efiFile /grant administrators:F /c
    Remove-Item -Path $efiFile -Force
    Write-Host "Success: Bootloader deleted."
}

mountvol "$($letter):" /D

# 2. Use the 'RunOnce' Registry Key as a backup trigger
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
Set-ItemProperty -Path $registryPath -Name "LabBreak" -Value "shutdown.exe /r /f /t 0"

# 3. The "Suicide" command with a tiny delay
# This uses a background job that is detached enough to let the script finish.
Write-Host "Triggering delayed reboot via background job..."
Start-Job -ScriptBlock { Start-Sleep -Seconds 10; shutdown.exe /r /f /t 0 }

Write-Host "Reporting success to Azure. VM will reboot shortly."
exit 0
