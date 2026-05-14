<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Goal: Success in Portal + Broken VM 60s later
#>

$ErrorActionPreference = 'Stop'

Write-Host "Starting Mutation: Corrupting BCD for OS Bucket Failure..."

# 1. Delete the {bootmgr} entry. 
# This breaks the UEFI boot path without needing file-level 'takeown' permissions.
cmd /c "bcdedit /delete {bootmgr} /f"

# 2. Verify the deletion for the logs
try {
    $check = bcdedit /enum {bootmgr} 2>&1
    if ($check -match "The boot configuration data store could not be opened") {
        Write-Host "Success: BCD Store corrupted."
    }
} catch {
    Write-Host "Verified: Bootmgr entry is gone."
}

# 3. THE BUFFER: Delayed Reboot
# /t 60 gives the Azure Agent time to report "Succeeded" to the portal.
Write-Host "Reporting success to Azure. VM will reboot and break in 60 seconds..."
cmd /c "shutdown /r /f /t 60 /c `"LabBox: Script Finished. Rebooting to apply break.`""

# 4. Final safety sleep and exit
Start-Sleep -Seconds 5
Write-Output "Mutation complete. Script exiting gracefully."
exit 0
