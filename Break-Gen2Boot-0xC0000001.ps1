<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Applies valid configuration overrides to bypass strict bcdedit pre-validation filters.
    - Forces a clean winload processing halt on subsequent boot phase.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring absolute BCD validation constraints..."

# 2. FORCE SYSTEM INTEGRITY CONFLICTS
# These commands use 100% valid parameters that the bcdedit parser will accept,
# but forcing them on a standard Gen 2 image breaks boot validation, triggering 0xC0000001.
& bcdedit.exe /set {current} nointegritychecks Yes
& bcdedit.exe /set {current} testsigning Yes

Write-Host "BCD configuration completed successfully. Initiating hardware reset..."

# 3. FORCE AN IMMEDIATE REBOOT
# We remove 'shutdown /a' to avoid error 1116 and use /f /t 5 to drop the machine instantly.
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
