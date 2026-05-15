<#
  Break-Gen2Boot-OSBucket.ps1
  Strategy: Native Scheduled Task (Bypasses Agent Cleanup)
  Matches [BAT] and [POWERSHELL] background logic principles.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. CREATE THE BACKGROUND SCRIPT
# We save the "messing things up" logic to a local file.
$breakScript = @"
Start-Sleep -Seconds 30
& cmd.exe /c "mountvol S: /S"
attrib.exe -r -s -h S:\\EFI\\Microsoft\\Boot\\bootmgfw.efi
Remove-Item -Path S:\\EFI\\Microsoft\\Boot\\bootmgfw.efi -Force
& cmd.exe /c "mountvol S: /D"
Restart-Computer -Force
"@
$scriptPath = "C:\Windows\Temp\FinalBreak.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 3. REGISTER THE TASK (The "Time Bomb")
# This runs as SYSTEM and triggers 1 minute from now.
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureLabBreak" -Action $action -Trigger $trigger -Principal $principal -Force

Write-Output "Background process scheduled via Task Scheduler. Reporting success to Azure..."

# 4. EXIT IMMEDIATELY
# The portal turns green, and the Task Scheduler handles the rest.
exit 0
