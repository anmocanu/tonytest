<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) for training labs.
    - Surgically breaks the ntoskrnl.exe integrity to trigger signature validation failure.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can execute without blocks
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE IN-MEMORY DESTRUCTION PAYLOAD
$breakScript = @'
Start-Sleep -Seconds 30

$kernelPath = "C:\Windows\System32\ntoskrnl.exe"

if (Test-Path $kernelPath) {
    # Take ownership and grant Full Control to modify the kernel binary on disk
    & cmd.exe /c "takeown /f $kernelPath /a"
    & cmd.exe /c "icacls $kernelPath /grant administrators:F /c"
    & cmd.exe /c "attrib -r -s -h $kernelPath"
    
    # Intentionally corrupt the binary structure by overwriting the first few bytes
    # This renders the signature invalid and corrupts the PE header execution path
    [byte[]]$corruptBytes = 0x41, 0x42, 0x43, 0x44, 0x45, 0x46
    $stream = [System.IO.File]::OpenWrite($kernelPath)
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
Write-Host "Kernel target routine structured successfully."
Write-Host "Background deployment scheduled. VM will halt with 0xC0000001 on the subsequent boot phase."
exit 0
