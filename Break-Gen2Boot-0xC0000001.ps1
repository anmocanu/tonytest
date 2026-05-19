<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Injects a strict security initialization constraint to bypass self-healing filters.
    - Executes directly within the Azure RunCommand context.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring system initialization constraints..."

# 2. FORCE LSA SYSTEM AUDIT STATE FAILURE
# This creates a native security policy restriction. During winload/kernel handoff, 
# the system reads this flag and terminates initialization immediately, yielding 0xC0000001.
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-ItemProperty -Path $registryPath -Name "crashonauditfail" -Value 2 -Type DWord -Force

Write-Host "Configuration completed successfully. Issuing immediate hardware reset..."

# 3. FORCE IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
