<#
  Break-Gen2Boot-OSBucket.ps1
  Purpose: Simulate OS Bucket / Boot Failure by deleting the Boot Manager entry.
  This bypasses file-system permission issues on Windows Server 2025.
#>

$ErrorActionPreference = 'Stop'

Write-Host "Starting Mutation: Corrupting BCD for OS Bucket Failure..."

# 1. Delete the {bootmgr} entry. 
cmd /c "bcdedit /delete {bootmgr} /f"

# 2. Verify the deletion
try {
    $check = bcdedit /enum {bootmgr} 2>&1
    if ($check -match "The boot configuration data store could not be opened") {
        Write-Host "Success: BCD Store is now empty/corrupted."
    }
} catch {
    Write-Host "Verified: Bootmgr entry is gone."
}

# 3. Forced Synchronous Reboot with 60s Buffer
Write-Host "Forcing reboot in 60 seconds to allow Azure status reporting..."
cmd /c "shutdown /r /f /t 60"

# 4. Sleep BEFORE exiting to keep the session open for the Agent
Start-Sleep -Seconds 5
exit 0
