<#
  Break-Gen2Boot_v2.ps1
  LabBox intent: deterministically break Gen2/UEFI boot by renaming the Windows Boot Manager EFI file.
  Behavior: completes successfully (exit 0) then reboots.
#>

$ErrorActionPreference = 'Stop'

# Prefer these letters; we'll pick the first available.
$preferredLetters = @('S','Y','Z','T','U','V','W','X')

function Refresh-Drives {
    # Known issue: PowerShell may not immediately see the newly mounted system partition.
    # Forcing a rescan by querying PS drives helps. [1](https://learn.microsoft.com/en-us/archive/blogs/sergey_babkins_blog/how-to-mount-a-system-partition)
    $null = Get-PSDrive | Out-Null
    Start-Sleep -Seconds 1
    $null = Get-PSDrive | Out-Null
}

function Get-FreeLetter {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($l in $preferredLetters) {
        if ($used -notcontains $l) { return $l }
    }
    throw "No free drive letter found among: $($preferredLetters -join ',')"
}

function Try-MountEspWithMountvol([string]$letter) {
    $dl = "$letter`:"
    Write-Output "Trying mountvol $dl /S ..."
    $out = cmd /c "mountvol $dl /S" 2>&1 | Out-String
    Write-Output $out.Trim()

    Refresh-Drives

    if (Test-Path "$dl\") {
        Write-Output "Drive $dl is visible to PowerShell."
        return $true
    }

    Write-Warning "Drive $dl still not visible to PowerShell after mountvol. Attempting dismount."
    cmd /c "mountvol $dl /D" 2>&1 | Out-String | Write-Output
    Refresh-Drives
    return $false
}

function MountEspFallbackWithPartitionCmdlets([string]$letter) {
    # EFI System Partition GPT type GUID is c12a7328-f81f-11d2-ba4b-00a0c93ec93b (ESP).
    $espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
    $dl = "$letter`:"
    $accessPath = "$dl\"

    Write-Output "Fallback: locating ESP via Get-Partition and assigning $dl using Add-PartitionAccessPath ..."

    # OS disk is typically Disk 0 in Azure Gen2 Windows images; if not, you'd need more logic.
    $esp = Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq $espGuid } | Select-Object -First 1
    if (-not $esp) {
        throw "EFI System Partition not found on Disk 0 via Get-Partition."
    }

    Add-PartitionAccessPath -DiskNumber 0 -PartitionNumber $esp.PartitionNumber -AccessPath $accessPath
    Refresh-Drives

    if (-not (Test-Path "$dl\")) {
        throw "Assigned $dl but drive still not visible."
    }

    Write-Output "Assigned ESP to $dl successfully via partition cmdlets."
    return $true
}

function DismountEsp([string]$letter, [string]$method) {
    $dl = "$letter`:"
    try {
        if ($method -eq 'mountvol') {
            Write-Output "Dismounting via mountvol $dl /D ..."
            cmd /c "mountvol $dl /D" 2>&1 | Out-String | Write-Output
        } elseif ($method -eq 'partition') {
            Write-Output "Dismounting via Remove-PartitionAccessPath ($dl) ..."
            $espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
            $esp = Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq $espGuid } | Select-Object -First 1
            if ($esp) {
                Remove-PartitionAccessPath -DiskNumber 0 -PartitionNumber $esp.PartitionNumber -AccessPath "$dl\"
            }
        }
        Refresh-Drives
    } catch {
        Write-Warning "Dismount encountered an issue: $($_.Exception.Message)"
    }
}

# --- Main ---
$letter = Get-FreeLetter
$method = $null

try {
    Write-Output "=== Break-Gen2Boot_v2: starting ==="
    Write-Output "Selected drive letter: $letter`:"

    if (Try-MountEspWithMountvol -letter $letter) {
        $method = 'mountvol'
    } else {
        MountEspFallbackWithPartitionCmdlets -letter $letter | Out-Null
        $method = 'partition'
    }

    $dl = "$letter`:"
    $bootMgr = "$dl\EFI\Microsoft\Boot\bootmgfw.efi"
    $bootMgrBak = "$dl\EFI\Microsoft\Boot\bootmgfw.efi.bak"

    Write-Output "Checking for EFI boot manager at: $bootMgr"
    if (-not (Test-Path $bootMgr)) {
        throw "EFI boot manager not found at $bootMgr (unexpected for Windows UEFI)."
    }

    if (Test-Path $bootMgrBak) {
        Write-Output "Backup already exists ($bootMgrBak). Boot may already be broken. Leaving as-is."
    } else {
        Write-Output "Renaming boot manager to break boot on next restart:"
        Write-Output "  $bootMgr -> $bootMgrBak"
        Rename-Item -Path $bootMgr -NewName "bootmgfw.efi.bak" -Force
        Write-Output "Rename completed."
    }

} catch {
    Write-Error ("Break-Gen2Boot_v2 failed: " + $_.Exception.Message)
    throw
} finally {
    if ($method) {
        DismountEsp -letter $letter -method $method
    }
}

Write-Output "Scheduling reboot in 30 seconds to trigger boot failure..."
cmd /c 'shutdown /r /t 30 /c "LabBox: rebooting to reproduce Gen2 UEFI boot failure"' | Out-String | Write-Output

Write-Output "=== Break-Gen2Boot_v2: completed successfully (reboot scheduled) ==="
exit 0
