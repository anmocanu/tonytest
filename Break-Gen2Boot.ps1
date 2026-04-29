<#
  BreakGen2Boot.ps1 (Updated)
  Purpose: Trigger 0x7B INACCESSIBLE_BOOT_DEVICE
  Method: Disable Boot-Critical Storage Drivers
#>

$ErrorActionPreference = 'Stop'
$WorkDir = "C:\LabBox"
$LogFile = "$WorkDir\BreakStatus.txt"

# --- ensure working directory ---
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# --- Logic: Disable Storage Driver ---
# Root Cause Analysis 5: Disabling a driver used as a lower/upper filter or critical service 
# Root Cause Analysis 8: NVMe driver configuration issues cause 0x7B 

$nvmeService = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme"
$scsiService = "HKLM:\SYSTEM\CurrentControlSet\Services\storvsc"

try {
    # Attempt to disable NVMe (standard for modern Gen2 VMs)
    if (Test-Path $nvmeService) {
        Set-ItemProperty -Path $nvmeService -Name "Start" -Value 4
        Add-Content -Path $LogFile -Value "stornvme disabled at $(Get-Date)"
    } 
    # Fallback to SCSI driver if NVMe is not present
    elseif (Test-Path $scsiService) {
        Set-ItemProperty -Path $scsiService -Name "Start" -Value 4
        Add-Content -Path $LogFile -Value "storvsc disabled at $(Get-Date)"
    }
    else {
        throw "No targetable storage driver found."
    }
}
catch {
    Add-Content -Path $LogFile -Value "Failed to disable driver: $($_.Exception.Message)"
    exit 1
}

# --- Reboot to trigger the BSOD ---
shutdown /r /t 10 /f /c "LabBox: Injecting 0x7B INACCESSIBLE_BOOT_DEVICE failure"
