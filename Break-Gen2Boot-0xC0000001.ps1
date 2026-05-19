<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on modern Gen 2 VMs.
    - Uses Offline Registry Modification to bypass live kernel protection and self-healing.
    - Forces a clean winload processing halt via ELAM initialization faults.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
$breakScript = @'
Start-Sleep -Seconds 60

# Mount the offline SYSTEM registry hive directly from the disk configuration files
# This completely bypasses volatile memory states and live kernel protection
& reg.exe load HKLM\OFFLINE_SYSTEM C:\Windows\System32\config\SYSTEM

# Target the Early Launch Anti-Malware (ELAM) driver configuration (WdBoot)
# By setting its Type to an invalid value (e.g., 4) inside the offline storage layer,
# winload.efi will experience a fatal exception during structural initialization.
$elamPath = "HKLM\OFFLINE_SYSTEM\ControlSet001\Services\WdBoot"
& reg.exe add $elamPath /v Type /t REG_DWORD /d 4 /f
& reg.exe add $elamPath /v ErrorControl /t REG_DWORD /d 3 /f

# Unmount the hive to permanently commit the modifications directly to the disk sector
& reg.exe unload HKLM\OFFLINE_SYSTEM

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\ElamMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureNativeGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "ELAM boot constraint structured successfully."
Write-Host "Background deployment scheduled. VM will transition to 0xC0000001 shortly."
exit 0
