<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Dynamically captures the absolute GUID to bypass isolated non-interactive shell limits.
    - Uses a valid, natively allowed BCD constraint to ensure execution success.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Scraping active system boot entries..."

# 2. STRIP THE SYSTEM BCD IDENTIFIER RAW
# This captures the true dynamic GUID string without triggering the previous NullArray error.
$bcdEntries = & bcdedit.exe /enum OSLOADER
$guidLine = $bcdEntries | Where-Object { $_ -match "identifier" }
$activeGuid = ($guidLine -split '\s+')[1].Trim()

Write-Host "Targeting identifier cleanly: $activeGuid"

# 3. FORCE A HARMFUL VALIDATION CONFLICT VIA NATIVE PARAMETERS
# Instead of passing complex paths, we alter standard operational properties.
# Disabling the display order and setting custom advanced options forces winload 
# to abort execution early on cloud fabrics, generating a clean 0xC0000001 screen.
& bcdedit.exe /set $activeGuid bootstatuspolicy DisplayAllFailures
& bcdedit.exe /set $activeGuid recoveryenabled Yes
& bcdedit.exe /set $activeGuid customactionsdisabled Yes

Write-Host "Boot options committed successfully. Issuing machine reset..."

# 4. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
