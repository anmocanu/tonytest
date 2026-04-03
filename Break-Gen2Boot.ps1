<#
  Break-Gen2Boot.ps1
  Purpose: Intentionally break UEFI boot on Windows Gen2 by renaming the Windows Boot Manager EFI file.
  LabBox behavior: Script must complete successfully (exit 0) and THEN reboot.
#>

$ErrorActionPreference = 'Stop'

$efiDrive = "S:"
$efiMountCmd = "mountvol $efiDrive /S"
$efiDismountCmd = "mountvol $efiDrive /D"

$bootMgr = Join-Path $efiDrive "EFI\Microsoft\Boot\bootmgfw.efi"
$bootMgrBak = Join-Path $efiDrive "EFI\Microsoft\Boot\bootmgfw.efi.bak"

try {
    Write-Output "=== Break-Gen2Boot: starting ==="
    Write-Output "Mounting EFI System Partition to $efiDrive ..."
    cmd /c $efiMountCmd | Out-String | Write-Output

    if (-not (Test-Path $bootMgr)) {
        # If bootmgfw.efi is missing, either the path differs or it's already been modified.
        # For LabBox we still want to complete successfully so deployment doesn't fail.
        Write-Warning "EFI boot manager not found at: $bootMgr"
        Write-Warning "No changes made. (VM may already be broken or uses a different boot path.)"
    }
    else {
        if (Test-Path $bootMgrBak) {
            Write-Output "Backup already exists at $bootMgrBak (boot may already be broken)."
        }
        else {
            Write-Output "Renaming boot manager to break boot on next restart:"
            Write-Output "  $bootMgr -> $bootMgrBak"
            Rename-Item -Path $bootMgr -NewName (Split-Path $bootMgrBak -Leaf) -Force
            Write-Output "Rename completed."
        }
    }
}
catch {
    # If we throw here, Run Command will fail the deployment (by design).
    Write-Error ("Break-Gen2Boot failed: " + $_.Exception.Message)
    throw
}
finally {
    try {
        Write-Output "Dismounting EFI System Partition from $efiDrive ..."
        cmd /c $efiDismountCmd | Out-String | Write-Output
    } catch {
        Write-Warning ("EFI dismount encountered an issue: " + $_.Exception.Message)
    }
}

# Schedule reboot AFTER the Run Command returns success.
Write-Output "Scheduling reboot in 30 seconds to trigger the boot failure..."
cmd /c 'shutdown /r /t 30 /c "LabBox: rebooting to reproduce Gen2 UEFI boot failure"' | Out-String | Write-Output

Write-Output "=== Break-Gen2Boot: completed successfully (reboot scheduled) ==="
exit 0
