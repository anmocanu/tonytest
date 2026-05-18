<#
  Break-Gen2Boot.ps1
  Purpose: 
    - Reliably simulate 0x7B INACCESSIBLE_BOOT_DEVICE for LabBox training.
    - Disables storage stack across ALL ControlSets.
    - Wipes the CriticalDeviceDatabase for NVMe to prevent driver re-enumeration.
    - Uses a Scheduled Task for a clean Azure deployment "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Identify all ControlSets to prevent Windows from falling back to a "Last Known Good"
$Sets = Get-ChildItem -Path HKLM:\SYSTEM -Name | Where-Object { $_ -match "ControlSet|CurrentControlSet" }
$Drivers = @("stornvme", "storsvc", "pci", "vmbus", "atapi", "storvsc")

foreach ($Set in $Sets) {
    foreach ($Driver in $Drivers) {
        $path = "HKLM:\SYSTEM\$Set\Services\$Driver"
        if (Test-Path $path) {
            # Disable driver (4) and set an invalid Group to block PnP loading
            Set-ItemProperty -Path $path -Name "Start" -Value 4 -Force
            Set-ItemProperty -Path $path -Name "Group" -Value "Disabled" -Force
        }
    }
}

# 2. Wipe the CriticalDeviceDatabase entries for the storage controllers
# This is the 'secret sauce' to ensure the kernel panics during the next boot
$cdb = "HKLM:\SYSTEM\CurrentControlSet\Control\CriticalDeviceDatabase"
if (Test-Path $cdb) {
    Get-ChildItem $cdb | Where-Object { $_.Name -match "PCI#VEN_144D" -or $_.Name -match "primary_stornvme" } | Remove-Item -Recurse -Force
}

# 3. Schedule the "Self-Destruct" Reboot
# The 1-minute delay allows the Run Command to report SUCCESS to Azure first
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "Stop-Computer -Force"'
$Trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))

# Register the task to run as the SYSTEM account with highest privileges
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "LabBox-Break" -User "System" -RunLevel Highest

# 4. Final output for the Azure Run Command logs
Write-Host "Registry and CriticalDeviceDatabase mutated successfully."
Write-Host "Reboot scheduled in 60 seconds. VM will crash with 0x7B on next boot."
exit 0
