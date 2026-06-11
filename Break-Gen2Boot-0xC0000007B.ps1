<#
Break-Gen2Boot-0xC000007B.ps1

Purpose:
    Azure Generation 2 / UEFI Windows VM lab script targeting:
        0xC000007B / STATUS_INVALID_IMAGE_FORMAT

Scenario:
    Gen2 VM only.
    Best tested without Trusted Launch / Secure Boot first (Secure Boot will
    reject the tampered winload.efi before the format error is surfaced).

Strategy:
    Corrupt winload.efi on the active EFI System Partition (or the Windows
    system32 boot copy) so the UEFI boot manager loads the file but the
    Windows Boot Manager rejects it as an invalid PE image:
        - locate EFI winload.efi on the EFI System Partition
        - back up the original
        - overwrite with a zero-byte file (invalid PE header)
        - keep BCD intact so the error is image-format, not path resolution

Reason:
    0xC000007B / STATUS_INVALID_IMAGE_FORMAT fires when the loader binary
    exists and is referenced by BCD, but its PE headers are absent or
    describe the wrong architecture.  Zeroing the file is the fastest
    reliable way to produce this on a running system.

Lab warning:
    This intentionally makes the VM non-bootable.
    Use only on disposable lab VMs.
#>

param(
    [string]$ScheduleReboot  = "YES",
    [string]$AsyncDetonate   = "YES",
    [int]$DelaySeconds       = 90
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Section {
    param([Parameter(Mandatory=$true)][string]$Title)
    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Title
    Write-Output "============================================================"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Output ("[cmd] {0} {1}" -f $FilePath, ($Arguments -join " "))

    $psi                       = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName              = $FilePath
    $psi.UseShellExecute       = $false
    $psi.RedirectStandardOutput= $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow        = $true
    $psi.Arguments             = $Arguments -join " "

    $proc           = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    if ($stdout) { $stdout -split "`r?`n" | Where-Object { $_ -ne "" } | ForEach-Object { Write-Output $_ } }
    if ($stderr) { $stderr -split "`r?`n" | Where-Object { $_ -ne "" } | ForEach-Object { Write-Output $_ } }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed. File=$FilePath ExitCode=$exitCode Args=$($Arguments -join ' ')"
    }
    if (($exitCode -ne 0) -and $AllowFailure) {
        Write-Warning "Command returned non-zero exit code but failure was allowed. ExitCode=$exitCode"
    }

    return $exitCode
}

function Find-WinloadEfi {
    <#
    Returns a list of candidate winload.efi paths to corrupt.
    Priority:
      1. EFI System Partition  \EFI\Microsoft\Boot\winload.efi
      2. Windows system32 boot \Windows\System32\Boot\winload.efi  (fallback)
    #>
    $candidates = @()

    # --- EFI System Partition ---
    try {
        # Use mountvol to find the EFI partition drive letter (if already mounted)
        $volumes = & mountvol | Where-Object { $_ -match '^\s+\\\\\?\\Volume' }
        foreach ($vol in $volumes) {
            $letter = ($vol -replace '\\\\?\\Volume\{[^}]+\}\\','').Trim().TrimEnd('\')
            if ($letter -match '^[A-Z]:$') {
                $p = Join-Path $letter '\EFI\Microsoft\Boot\winload.efi'
                if (Test-Path $p) { $candidates += $p }
            }
        }

        # bcdedit gives us the actual EFI partition path for the boot manager
        $bcdOut = & bcdedit.exe /enum '{fwbootmgr}' /v 2>&1 | Out-String
        if ($bcdOut -match 'device\s+partition=(\w:)') {
            $efiDrive = $Matches[1]
            $p = Join-Path $efiDrive '\EFI\Microsoft\Boot\winload.efi'
            if ((Test-Path $p) -and ($p -notin $candidates)) { $candidates += $p }
        }
    } catch {
        Write-Warning "EFI partition scan failed: $($_.Exception.Message)"
    }

    # --- Windows\System32\Boot fallback ---
    $sys32 = Join-Path $env:SystemRoot 'System32\Boot\winload.efi'
    if ((Test-Path $sys32) -and ($sys32 -notin $candidates)) { $candidates += $sys32 }

    return $candidates
}

# ---------------------------------------------------------------------------
# Deferred / async detonation  (allows RunCommand to report success first)
# ---------------------------------------------------------------------------

if ($AsyncDetonate -eq "YES") {
    Write-Section "Deferring disruptive operation"
    Write-Output "Run mode         : deferred"
    Write-Output "Delay (seconds)  : $DelaySeconds"
    Write-Output "Schedule reboot  : $ScheduleReboot"

    $selfPath = $PSCommandPath
    if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }

    if (-not $selfPath -or -not (Test-Path $selfPath)) {
        Write-Error "Could not resolve script path for deferred execution."
        exit 21
    }

    $deferredLog = "C:\Windows\Temp\Break-Gen2Boot-0xC000007B-deferred.log"

    try {
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $selfPath, 
            "-ScheduleReboot", $ScheduleReboot, "-AsyncDetonate", "NO"
        ) -RedirectStandardOutput $deferredLog -RedirectStandardError ($deferredLog + ".err") | Out-Null
    } catch {
        Write-Error "Failed to launch deferred worker process: $($_.Exception.Message)"
        exit 22
    }

    Write-Output "Deferred worker launched successfully."
    Write-Output "Worker log path  : $deferredLog"
    Write-Output "Exiting now so RunCommand can complete before reboot/break."
    exit 0
}

# ---------------------------------------------------------------------------
# Main break logic
# ---------------------------------------------------------------------------

Write-Section "Gen2 Boot Break — 0xC000007B / STATUS_INVALID_IMAGE_FORMAT"
Write-Output "Target     : 0xC000007B / STATUS_INVALID_IMAGE_FORMAT"
Write-Output "Method     : overwrite winload.efi with a zero-byte (invalid PE) file"
Write-Output "Scope      : EFI System Partition + System32\Boot fallback"
Write-Output "Lab warning: this intentionally makes the VM non-bootable"

# If called with AsyncDetonate=NO, apply the delay that was set in deferred launcher
if ($AsyncDetonate -eq "NO" -and $DelaySeconds -gt 0) {
    Write-Section "Applying scheduled delay"
    Write-Output "Sleeping for $DelaySeconds seconds before mutation..."
    Start-Sleep -Seconds $DelaySeconds
}

Write-Section "Locating winload.efi"
$targets = Find-WinloadEfi

if (-not $targets -or $targets.Count -eq 0) {
    Write-Error "Could not locate winload.efi on any known path. Aborting."
    exit 11
}

Write-Output "Found $($targets.Count) target(s):"
$targets | ForEach-Object { Write-Output "  $_" }

Write-Section "Backing up and corrupting winload.efi"
$backupDir = "C:\Windows\Temp\winload-backup-0xC000007B"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$corrupted = @()
foreach ($target in $targets) {
    $fileName   = [System.IO.Path]::GetFileName($target)
    $backupPath = Join-Path $backupDir ($fileName + "_" + (Get-Date -Format 'yyyyMMddHHmmss') + ".bak")
    try {
        Copy-Item -Path $target -Destination $backupPath -Force
        Write-Output "Backed up : $target  ->  $backupPath"
    } catch {
        Write-Warning "Backup failed for '$target': $($_.Exception.Message). Skipping this target."
        continue
    }

    try {
        # Overwrite with a zero-byte file — invalid PE, causes STATUS_INVALID_IMAGE_FORMAT
        [System.IO.File]::WriteAllBytes($target, [byte[]]@())
        Write-Output "Corrupted : $target (zeroed)"
        $corrupted += $target
    } catch {
        Write-Warning "Could not corrupt '$target': $($_.Exception.Message)"
    }
}

if ($corrupted.Count -eq 0) {
    Write-Error "No winload.efi files were successfully corrupted. Aborting."
    exit 12
}

Write-Section "Validation"
foreach ($target in $corrupted) {
    $size = (Get-Item $target -Force).Length
    Write-Output "$target  ->  size after corruption: $size bytes"
    if ($size -eq 0) {
        Write-Output "  [PASS] File is zero-byte (invalid PE header confirmed)."
    } else {
        Write-Warning "  [WARN] File is not zero-byte. Result may vary."
    }
}

Write-Section "Expected result after reboot"
Write-Output "Target boot error : 0xC000007B / STATUS_INVALID_IMAGE_FORMAT"
Write-Output "Failure class     : Windows Boot Manager loaded winload.efi but its PE header is invalid"
Write-Output "Important note    : Secure Boot must be DISABLED — Secure Boot will reject the modified"
Write-Output "                    file with a different error before the format check runs."
Write-Output "Recovery          : Restore from backup at $backupDir"

if ($ScheduleReboot -eq "YES") {
    Write-Section "Scheduling reboot"
    try {
        shutdown.exe /r /f /t 10
        Write-Output "Reboot scheduled for 10 seconds."
    } catch {
        Write-Warning "shutdown.exe failed. Falling back to Restart-Computer."
        try {
            Restart-Computer -Force
        } catch {
            Write-Warning "Restart-Computer also failed: $($_.Exception.Message)"
        }
    }
} else {
    Write-Output ""
    Write-Output "Reboot not scheduled because ScheduleReboot was not YES."
}

Write-Output ""
Write-Output "Script completed."
exit 0
