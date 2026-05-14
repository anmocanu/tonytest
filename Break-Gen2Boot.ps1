<#
  Break-Gen2Boot-OSBucket.ps1
  Purpose: 
    - Reliably simulate "OS Bucket / Boot Failure" for Gen2 VMs.
    - Forces ownership of the UEFI bootloader and renames it.
    - Uses a Scheduled Task to avoid hanging the Azure Deployment.
#>

$ErrorActionPreference = 'Stop'

# 1. Define the 'Nuclear' payload as a script block
$Payload = {
    # Find a free drive letter and mount the EFI partition
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
    
    cmd /c "mountvol $($letter): /S"
    $efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

    if (Test-Path $efiFile) {
        # FORCE ownership to the Administrators group (/a) to bypass TrustedInstaller
        cmd /c "takeown /f $efiFile /a"
        
        # Grant Full Control to Administrators
        cmd /c "icacls $efiFile /grant administrators:F /c /t"
        
        # Rename the bootloader to .bak to break the UEFI boot sequence
        Move-Item -Path $efiFile -Destination "$($efiFile).bak" -Force
        
        # Dismount for safety
        cmd /c "mountvol $($letter): /D"
        
        # Force an immediate reboot
        Restart-Computer -Force -Confirm:$false
    }
}

# 2. Convert payload to a string and save it to a temporary local file
$localScriptPath = "C:\Windows\Temp\FinalBreak.ps1"
$Payload.ToString() | Out-File -FilePath $localScriptPath -Encoding UTF8 -Force

# 3. Create the Scheduled Task to run as SYSTEM with Highest Privileges
# We set the trigger for 30 seconds from 'now' to allow Azure to finish the deployment
$taskName = "LabBox-OSBucket-Trigger"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File $localScriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(30))
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType Service -RunLevel Highest

# 4. Register the task (clearing any old versions first)
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Principal $principal -Force

Write-Host "Success: EFI Mutation task registered."
Write-Host "The VM will rename the bootloader and reboot in 30 seconds."
exit 0
