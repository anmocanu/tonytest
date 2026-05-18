<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) for training labs.
    - Surgically breaks digital signature validity without corrupting PE image headers.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can execute without blocks
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE BACKGROUND MUTATION PAYLOAD
$breakScript = @'
Start-Sleep -Seconds 30

# Target a critical boot-start driver instead of the main kernel execution binary
$driverPath = "C:\Windows\System32\drivers\acpi.sys"

if (Test-Path $driverPath) {
    # Take ownership and grant Full Control to modify the file
    & cmd.exe /c "takeown /f $driverPath /a"
    & cmd.exe /c "icacls $driverPath /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $driverPath"
    
    # Append corruption bytes directly to the END of the file.
    # This leaves the PE file headers intact (avoiding 0xc000007b) 
    # but completely breaks the cryptographic checksum / digital signature.
    [byte[]]$corruptBytes = 0x99, 0x99, 0x99, 0x99
    $stream = [System.IO.File]::Open($driverPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    $stream.Write($corruptBytes, 0, $corruptBytes.Length)
    $stream.Close()
}

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\KernelMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureKernelBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings for the Azure Run Command logs
Write-Host "Driver integrity modification routine structured successfully."
Write-Host "Background deployment scheduled. VM will halt with 0xC0000001 on next boot phase."
exit 0
