<#
  Break-Gen2Boot-OSBucket.ps1
  Purpose: 
    - Simulate "OS Bucket / Boot Failure" (No Bootable Device) for Gen2 VMs.
    - Renames the UEFI bootloader so the firmware cannot find it.
    - Follows: https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/os-bucket-boot-failure
#>

$ErrorActionPreference = 'Stop'

# --- Payload: Mount EFI and Rename Bootloader ---
$Payload = {
    # 1. Find a free drive letter to mount the EFI partition
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

    # 2. Mount the EFI System Partition (ESP)
    cmd /c "mountvol $($letter): /S"

    $efiPath = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

    if (Test-Path $efiPath) {
        # 3. Take ownership to bypass TrustedInstaller protections
        takeown /f $efiPath
        icacls $efiPath /grant administrators:F

        # 4. Rename the bootloader to break the boot sequence
        Rename-Item -Path $efiPath -NewName "bootmgfw.efi.bak" -Force
    }

    # 5. Force an immediate reboot to manifest the failure
    Stop-Computer -Force
}

# --- Schedule the payload to run in 60 seconds ---
# This allows the RunCommand to report SUCCESS to Azure first.
$ScriptBlock = "[scriptblock]::Create('$($Payload.ToString() -replace "'","''")').Invoke()"
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -Command $ScriptBlock"
$Trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))

Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "LabBox-OSBucket-Break" -User "System" -RunLevel Highest

Write-Host "Bootloader targeted. Scheduled reboot in 60s. Reporting success to Azure..."
exit 0
