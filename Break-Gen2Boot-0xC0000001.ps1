<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Directly targets BCD application paths to force an absolute winload halt phase.
    - Bypasses background task failures by executing immediately.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring absolute BCD validation constraints..."

# 2. FORCE BCD TO AN INVALID OS DEVICE PATH
# By changing the path mapping of the current boot loader entry, winload.efi
# cannot initialize its execution environment, guaranteeing a clean 0xC0000001 status halt.
& bcdedit.exe /set {current} osdevice "ramdisk=[unknown]\DoesNotExist"
& bcdedit.exe /set {current} systemroot "\WindowsDoesNotExist"

# 3. Output confirmation strings for the Azure logs BEFORE the reboot drops the agent
Write-Host "BCD changes applied successfully. Issuing hardware reset execution loop..."

# 4. Trigger the reboot immediately
# Using a 10-second delay ensures the Custom Script Extension finishes sending its success log back to Azure.
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
