<#
  Break-Gen2Boot.ps1
  Purpose: 
    - Simulate 0x7B INACCESSIBLE_BOOT_DEVICE for LabBox training.
    - Disables critical storage and bus drivers to prevent mounting the OS disk.
    - Targets multiple ControlSets to prevent "Last Known Good Configuration" recovery.
#>

$ErrorActionPreference = 'Stop'

# Define the critical drivers for Azure Gen2 (NVMe/SCSI) and the PCIe bus
$Drivers = @("stornvme", "storsvc", "pci", "vmbus")

# We target both CurrentControlSet and ControlSet001 
# This prevents Windows from automatically reverting to a backup configuration during boot
$RegistryPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    "HKLM:\SYSTEM\ControlSet001\Services"
)

foreach ($Path in $RegistryPaths) {
    foreach ($Driver in $Drivers) {
        $FullPath = "$Path\$Driver"
        
        if (Test-Path $FullPath) {
            # Change 'Start' value to 4 (Disabled)
            # 0 = Boot, 3 = Manual, 4 = Disabled
            Set-ItemProperty -Path $FullPath -Name "Start" -Value 4 -Force
        }
    }
}

# Flush the registry to the physical disk to ensure changes survive a hard restart
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

# Force an immediate restart
# Stop-Computer -Force is more effective in a RunCommand context than shutdown.exe
# because it forces the kernel to halt regardless of pending updates or user sessions.
Stop-Computer -Force
