<#
  Break-Gen2Boot.ps1
  Purpose: 
    - Simulate 0x7B INACCESSIBLE_BOOT_DEVICE for LabBox training.
    - Disables critical storage and bus drivers.
    - Uses a Scheduled Task to allow the Azure deployment to finish before rebooting.
#>

$ErrorActionPreference = 'Stop'

# 1. Define the critical drivers for Azure Gen2 (NVMe/SCSI) and the PCIe bus 
[cite_start]$Drivers = @("stornvme", "storsvc", "pci", "vmbus") [cite: 1]

# 2. Target both CurrentControlSet and ControlSet001 to prevent automatic recovery 
$RegistryPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    "HKLM:\SYSTEM\ControlSet001\Services"
[cite_start]) [cite: 1]

foreach ($Path in $RegistryPaths) {
    foreach ($Driver in $Drivers) {
        $FullPath = "$Path\$Driver"
        
        if (Test-Path $FullPath) {
            # Change 'Start' value to 4 (Disabled) 
            [cite_start]Set-ItemProperty -Path $FullPath -Name "Start" -Value 4 -Force [cite: 1]
        }
    }
}

# 3. Schedule the "Self-Destruct" Reboot 
# This allows the script to report SUCCESS to the Azure Run Command agent first.
[cite_start]$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "Stop-Computer -Force"' [cite: 4]
[cite_start]$Trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) [cite: 4]

# Register the task to run as the SYSTEM account 
[cite_start]Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "LabBox-Break" -User "System" -RunLevel Highest [cite: 4]

# 4. Final log and exit 
[cite_start]Write-Host "Registry broken. Scheduled reboot in 1 minute. Reporting success to Azure..." [cite: 4]
[cite_start]exit 0 [cite: 4]
