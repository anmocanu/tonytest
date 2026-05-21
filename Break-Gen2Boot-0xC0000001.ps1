<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Limits available boot memory to force an absolute winload allocation halt.
    - Executes directly within the Azure RunCommand context.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Applying hardware memory execution constraints..."

# 2. TRUNCATE SYSTEM MEMORY TO 1MB
# This is a 100% valid structural BCD command that the Windows Server 2025 parser accepts.
# On reboot, winload.efi will fail to initialize the kernel in 1MB of RAM, causing a clean 0xC0000001 halt.
& bcdedit.exe /set {current} truncatememory 0x100000

Write-Host "BCD configuration completed successfully. Enforcing hardware reset..."

# 3. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
