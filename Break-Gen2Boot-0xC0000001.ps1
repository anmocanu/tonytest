<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Safely breaks the winload execution layer using precision byte mutation.
    - Executes directly within the Azure RunCommand context.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring absolute execution validation constraints..."

$targetLoader = "C:\Windows\System32\winload.efi"

if (Test-Path $targetLoader) {
    # 2. Take ownership and grant full access to administrators to bypass NTFS locks
    & cmd.exe /c "takeown /f $targetLoader /a"
    & cmd.exe /c "icacls $targetLoader /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $targetLoader"
    
    # 3. Read the binary content of the bootloader file into memory
    $bytes = [System.IO.File]::ReadAllBytes($targetLoader)
    
    # Overwrite the very first magic byte ('M' in MZ header) with a zero byte.
    # This leaves the file size, path, and security properties perfectly intact on disk,
    # but destroys its structural execution integrity instantly.
    $bytes[0] = 0x00
    
    # Write the mutated byte array back down to disk
    [System.IO.File]::WriteAllBytes($targetLoader, $bytes)
    
    Write-Host "Execution header mutated successfully."
} else {
    Write-Warning "Target boot loader application path not found."
}

Write-Host "Initiating final hardware reset cycle..."

# 4. FORCE AN IMMEDIATE REBOOT
& cmd.exe /c "shutdown /r /f /t 5"

exit 0
