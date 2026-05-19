<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025.
    - Diverts the winload application path to force an absolute boot manager halt phase.
    - Executes directly within the Azure RunCommand context.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Configuring absolute BCD validation constraints..."

# 2. ALTER THE BOOTLOADER PATH PARAMETER
# This is syntactically valid for bcdedit, bypassing the parameter validation check,
# but forces a fatal 0xC0000001 resolution error on the subsequent boot phase.
& bcdedit.exe /set {current} path "\Windows\System32\winload_doesnotexist.efi"

Write-Host "BCD changes applied successfully. Clearing pre-scheduled loops and issuing reset..."

# 3. ABORT ANY EXISTING SHUTDOWN WINDOWS AND FORCE REBOOT
# /a clears error 1190 conflicts; /r /f /t 10 guarantees execution and logs delivery.
& cmd.exe /c "shutdown /a"
Start-Sleep -Seconds 2
& cmd.exe /c "shutdown /r /f /t 10"

exit 0
