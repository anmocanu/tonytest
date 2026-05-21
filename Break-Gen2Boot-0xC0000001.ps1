<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Executes instantly to prevent Azure Guest Agent concurrency errors (MultipleExtensionsPerHandler).
#>

$ErrorActionPreference = 'Stop'

# Clear OOBE Barrier instantly so the Guest Agent can process status logs
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring instantaneous validation constraints..."

# Target a critical boot-critical driver that doesn't require takeown modifications
$targetPath = "C:\Windows\System32\drivers\mountmgr.sys"

if (Test-Path $targetPath) {
    # Move the file instantly using native .NET methods (bypasses heavy icacls loops)
    [System.IO.File]::Move($targetPath, "$targetPath.bak")
    Write-Host "Execution matrix adjusted successfully."
}

Write-Host "Issuing rapid reset..."
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
