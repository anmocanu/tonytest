<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on modern Gen 2 VMs.
    - Moves Code Integrity library to force an absolute winload halt phase.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
$breakScript = @'
Start-Sleep -Seconds 60

$targetFile = "C:\Windows\System32\CI.dll"

if (Test-Path $targetFile) {
    # Grant permissions to administrators over Code Integrity binary
    & cmd.exe /c "takeown /f $targetFile /a"
    & cmd.exe /c "icacls $targetFile /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $targetFile"
    
    # Rename the file instead of deleting it. 
    # This leaves the image intact for potential lab rescue scenarios, 
    # but winload.efi will immediately fail to resolve the dependency.
    Rename-Item -Path $targetFile -NewName "CI.dll.bak" -Force
}

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\CiMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureNativeGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "Code Integrity constraint structured successfully."
Write-Host "Background deployment scheduled. VM will transition to 0xC0000001 shortly."
exit 0
