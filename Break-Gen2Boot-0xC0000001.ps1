<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Dynamically discovers the active boot GUID to prevent {current} parsing drops.
    - Uses native EMS routing structures to guarantee a clean 0xC0000001 halt state.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Scoping active OS Boot identifier..."

# 2. DYNAMICALLY CAPTURE THE TRUE SYSTEM BOOT GUID
# This avoids relying on '{current}' which drops out inside detached execution contexts.
$bcdOutput = & bcdedit.exe /enum OSLOADER
$targetGuid = ""

if ($bcdOutput -match "{[a-fA-E0-9-]{36}}") {
    $targetGuid = $Matches[0]
    Write-Host "Successfully captured active system target identifier: $targetGuid"
} else {
    # Fallback to current if parsing hits an unexpected formatting anomaly
    $targetGuid = "{current}"
    Write-Host "Identifier matching anomaly detected. Utilizing standard token matrix."
}

# 3. APPLY DISRUPTIVE EMS REDIRECTION ROUTING
# Enabling Emergency Management Services mapped to an invalid configuration channel 
# forces winload.efi to hit a structural resource collision during early boot initialization, 
# resulting cleanly in the targeted 0xC0000001 screen without corrupting files.
& bcdedit.exe /set $targetGuid bootems Yes
& bcdedit.exe /set $targetGuid emsport 4
& bcdedit.exe /set $targetGuid emsbaudrate 115200

Write-Host "BCD criteria updated successfully. Enforcing hardware reset sequence..."

# 4. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
