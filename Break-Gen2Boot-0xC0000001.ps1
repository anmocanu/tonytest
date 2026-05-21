<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Forces a clean winload structural halt via offline registry file validation faults.
    - Bypasses bcdedit parameter validation blocks entirely.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring absolute boot validation constraints..."

$targetHive = "C:\Windows\System32\config\SYSTEM"

if (Test-Path $targetHive) {
    # 2. Take ownership and grant full access to administrators to bypass locks
    & cmd.exe /c "takeown /f $targetHive /a"
    & cmd.exe /c "icacls $targetHive /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $targetHive"
    
    # 3. Append a block of 1024 garbage bytes directly to the end of the file database.
    # This leaves the file paths and size expectations intact, but structurally invalidates
    # the internal registry mapping data layout.
    $corruptBytes = [byte[]](,0xFF * 1024)
    Add-Content -Path $targetHive -Value $corruptBytes -Encoding Byte
    
    Write-Host "System configuration database mutated successfully."
} else {
    Write-Warning "Target validation hive not discovered on drive path."
}

Write-Host "Initiating hardware reset cycle..."

# 4. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
