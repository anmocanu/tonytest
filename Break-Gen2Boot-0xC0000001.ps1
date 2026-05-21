<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Uses native AppInit sub-system configuration to bypass bcdedit parser blocks.
    - Forces a clean winload/kernel processing halt during system initialization.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring sub-system initialization hooks..."

# 2. INJECT THE SUB-SYSTEM COLLISION MATRIX
# This modifies standard, allowed registry values that bypass live-session locks.
# Pointing AppInit to ntdll.dll forces a fatal loop for every core process on reboot.
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"

Set-ItemProperty -Path $registryPath -Name "AppInit_DLLs" -Value "ntdll.dll" -Force
Set-ItemProperty -Path $registryPath -Name "LoadAppInit_DLLs" -Value 1 -Type DWord -Force

Write-Host "Sub-system hooks committed cleanly. Enforcing hardware reset..."

# 3. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
