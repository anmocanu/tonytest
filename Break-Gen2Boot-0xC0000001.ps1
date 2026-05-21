<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Uses the universal '{current}' token so it never breaks across different VM deployments.
    - Forces a clean winload processing halt using native EMS routing structures.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Applying universal BCD validation constraints..."

# 2. APPLY DISRUPTIVE EMS REDIRECTION ROUTING TO THE ACTIVE BOOT ENTRY
# By using '{current}', Windows automatically resolves whatever random GUID the VM has.
& bcdedit.exe /set {current} bootems Yes
& bcdedit.exe /set {current} emsport 4
& bcdedit.exe /set {current} emsbaudrate 115200

Write-Host "BCD criteria updated successfully via universal token. Enforcing hardware reset..."

# 3. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
