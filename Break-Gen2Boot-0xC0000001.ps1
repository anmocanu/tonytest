<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Displaces a critical core boot driver to cleanly halt early kernel loading.
    - Bypasses bcdedit execution sandboxes and persistent file locks entirely.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring early-stage driver validation constraints..."

# Target the core kernel cryptography validation library
$targetDriver = "C:\Windows\System32\drivers\cng.sys"

if (Test-Path $targetDriver) {
    Write-Host "Core validation infrastructure located. Shifting security context..."
    
    # 2. Take ownership and open the file system permissions cleanly
    & cmd.exe /c "takeown /f $targetDriver /a"
    & cmd.exe /c "icacls $targetDriver /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $targetDriver"
    
    # 3. Rename the driver to hide it from winload.efi
    # This leaves the actual binary completely intact for easy recovery later if needed,
    # but completely breaks the early kernel initialization matrix.
    Rename-Item -Path $targetDriver -NewName "cng_hidden.sys" -Force
    
    Write-Host "Driver environment displacement completed successfully."
} else {
    Write-Warning "Target driver infrastructure path not found."
}

Write-Host "Initiating hardware reset loop..."

# 4. TRIGGER IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
