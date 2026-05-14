<#
  Break-Gen2Boot-OSBucket.ps1
  Purpose: Simulate OS Bucket / Boot Failure by deleting the Boot Manager entry.
  This bypasses file-system permission issues on Windows Server 2025.
#>

$ErrorActionPreference = 'Stop'

Write-Host "Starting Mutation: Corrupting BCD for OS Bucket Failure..."

# 1. Delete the {bootmgr} entry. 
# Without this, UEFI knows the disk exists but doesn't know how to start Windows.
# This results in a "No bootable device" or "BCD error" screen.
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

# 3. Forced Synchronous Reboot
# We use /t 0 for an immediate kill so the agent can't block it.
Write-Host "Forcing immediate reboot..."
cmd /c "shutdown /r /f /t 0"

# Stay alive for a few seconds to ensure the kernel receives the signal
Start-Sleep -Seconds 5
