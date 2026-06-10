<#
Break-Gen2Boot-0xC0000001.ps1

Purpose:
    Azure Gen2/UEFI Windows VM lab script targeting:
        0xC0000001 / STATUS_UNSUCCESSFUL

Strategy:
    BCD-only break:
      - keep bootmgr valid
      - keep winload.efi valid
      - keep systemroot valid
      - remove DEVICE and OSDEVICE from the Windows Boot Loader entry

Why:
    Exact 0xC0000001 is associated with BCD / boot-path failure scenarios.
    Do not corrupt SYSTEM hive, ntoskrnl.exe, winload.efi, or fake systemroot for this run.

Lab only:
    This intentionally makes the VM non-bootable.
#>

param(
    [string]$IUnderstand    = "NO",
    [string]$ScheduleReboot = "YES",
    [ValidateSet("BcdMissingDevice")]
    [string]$Mode = "BcdMissingDevice"
)

$ErrorActionPreference = "Stop"

function Invoke-CmdChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [switch]$AllowFailure
    )

    Write-Output "  [cmd] $Command"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/d /c $Command"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()

    $proc.WaitForExit()

    $exitCode = $proc.ExitCode

    $output = @()
    if ($stdout) {
        $output += ($stdout -split "`r?`n")
    }
    if ($stderr) {
        $output += ($stderr -split "`r?`n")
    }

    $output = $output | Where-Object { $_ -ne "" }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed. ExitCode=$exitCode Command=$Command Output=$($output -join "`n")"
    }

    if (($exitCode -ne 0) -and $AllowFailure) {
        Write-Warning "AllowFailure command returned ExitCode=$exitCode Command=$Command"
        if ($output) {
            foreach ($line in $output) {
                Write-Warning "  $line"
            }
        }
    }

    return $output
}

function Get-BcdBlocks {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $blocks = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        if ($line -match "^\s*$") {
            if ($current.Count -gt 0) {
                $blocks.Add(($current -join "`n"))
                $current.Clear()
            }
            continue
        }

        $current.Add($line)
    }

    if ($current.Count -gt 0) {
        $blocks.Add(($current -join "`n"))
    }

    return $blocks
}

function Get-OsLoaderIdentifiers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorePath
    )

    Write-Output ""
    Write-Output "Resolving Windows Boot Loader identifiers from EFI BCD store..."

    $ids = @()

    $enumOutput = Invoke-CmdChecked -Command "bcdedit /store `"$StorePath`" /enum osloader /v" -AllowFailure

    if (-not $enumOutput -or $enumOutput.Count -eq 0) {
        Write-Output "No output from /enum osloader. Trying /enum all fallback..."
        $enumOutput = Invoke-CmdChecked -Command "bcdedit /store `"$StorePath`" /enum all /v" -AllowFailure
    }

    if (-not $enumOutput -or $enumOutput.Count -eq 0) {
        return @()
    }

    $blocks = Get-BcdBlocks -Lines $enumOutput

    foreach ($block in $blocks) {
        if ($block -notmatch "(?im)^Windows Boot Loader\s*$") {
            continue
        }

        $idMatch = [regex]::Match($block, "(?im)^identifier\s+(\{[^\}]+\})\s*$")
        $pathMatch"(?im)^path\s+\\Windows\\system32\\winload\.efi\s*$")

        if ($idMatch.Success -and $pathMatch.Success) {
            $id = $idMatch.Groups[1].Value

            if ($id -notin @("{bootmgr}", "{fwbootmgr}", "{memdiag}")) {
                $ids += $id
            }
        }
    }

    $ids = $ids | Select-Object -Unique

    return $ids
}

function Invoke-BcdMissingDeviceBreak {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScheduleReboot
    )

    Write-Output ""
    Write-Output "=== BcdMissingDevice Mode ==="
    Write-Output "Target: 0xC0000001 / STATUS_UNSUCCESSFUL"
    Write-Output "Method: remove DEVICE and OSDEVICE from the Windows Boot Loader BCD entry."
    Write-Output ""

    $efiDrive = "S:"
    $efiBcd = "$efiDrive\EFI\Microsoft\Boot\BCD"

    Write-Output "Mounting EFI System Partition to $efiDrive ..."
    Invoke-CmdChecked -Command "mountvol $efiDrive /S" | Out-Null

    try {
        if (-not (Test-Path $efiBcd)) {
            throw "EFI BCD store not found at $efiBcd"
        }

        Write-Output "EFI BCD store found: $efiBcd"

        $backupPath = "$efiBcd.bak.BcdMissingDevice"
        Write-Output "Backing up EFI BCD store to: $backupPath"
        Copy-Item -Path $efiBcd -Destination $backupPath -Force

        Write-Output ""
        Write-Output "Pre-mutation BCD snapshot:"
        $preSnapshot = Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /enum osloader /v" -AllowFailure
        if ($preSnapshot) {
            $preSnapshot | ForEach-Object { Write-Output $_ }
        }

        $loaderIds = Get-OsLoaderIdentifiers -StorePath $efiBcd

        if (-not $loaderIds -or $loaderIds.Count -eq 0) {
            throw "Could not find a Windows Boot Loader entry with path \Windows\system32\winload.efi."
        }

        Write-Output ""
        Write-Output "Resolved OS loader ID(s): $($loaderIds -join ', ')"

        foreach ($loaderId in $loaderIds) {
            Write-Output ""
            Write-Output "Applying BCD-only mutation to loader: $loaderId"

            # Keep the boot application valid.
            # This avoids image-format, Secure Boot signature, or missing winload failures.
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set $loaderId path \Windows\System32\winload.efi" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set $loaderId systemroot \Windows" -AllowFailure | Out-Null

            # Clear prior lab kernel override if present.
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /deletevalue $loaderId kernel" -AllowFailure | Out-Null

            # Main mutation for 0xC0000001 BCD class.
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /deletevalue $loaderId device" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /deletevalue $loaderId osdevice" -AllowFailure | Out-Null

            # Avoid automatic repair masking the raw failure screen.
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set $loaderId recoveryenabled No" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set $loaderId bootstatuspolicy IgnoreAllFailures" -AllowFailure | Out-Null
        }

        # Keep boot manager valid. Do not intentionally break bootmgr.
        Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set {bootmgr} recoveryenabled No" -AllowFailure | Out-Null
        Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /set {bootmgr} displaybootmenu No" -AllowFailure | Out-Null

        Write-Output ""
        Write-Output "Post-mutation BCD snapshot:"
        $postSnapshot = Invoke-CmdChecked -Command "bcdedit /store `"$efiBcd`" /enum osloader /v" -AllowFailure
        if ($postSnapshot) {
            $postSnapshot | ForEach-Object { Write-Output $_ }
        }

        Write-Output ""
        Write-Output "Expected post-mutation state:"
        Write-Output "  path       = \Windows\System32\winload.efi"
        Write-Output "  systemroot = \Windows"
        Write-Output "  kernel     = absent"
        Write-Output "  device     = absent from OS loader"
        Write-Output "  osdevice   = absent from OS loader"
    }
    finally {
        Write-Output ""
        Write-Output "Dismounting EFI System Partition..."
        Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
    }

    Write-Output ""
    Write-Output "=== BcdMissingDevice mutation completed ==="
    Write-Output "Target boot error: 0xC0000001 / STATUS_UNSUCCESSFUL"
    Write-Output "If the VM still boots, the BCD object mutated was not the effective boot entry."
    Write-Output "If the VM fails with another code, WS2025 / Trusted Launch is remapping the visible failure code."

    if ($ScheduleReboot -eq "YES") {
        Write-Output ""
        Write-Output "Scheduling forced reboot in 90 seconds..."
        Invoke-CmdChecked -Command 'shutdown /r /f /t 90 /c "Lab: trigger 0xC0000001 via BCD missing device osdevice"'
    }
    else {
        Write-Output ""
        Write-Output "Reboot not scheduled because ScheduleReboot was not YES."
    }
}

# Main

if ($IUnderstand -ne "YES") {
    Write-Error "Safety check failed. Set -IUnderstand YES to proceed. This script intentionally makes the VM non-bootable."
    exit 2
}

if ($Mode -ne "BcdMissingDevice") {
    Write-Error "Unsupported mode: $Mode. This corrected version supports only BcdMissingDevice."
    exit 3
}

Write-Output "Checkpoint: starting corrected BcdMissingDevice script."
Invoke-BcdMissingDeviceBreak -ScheduleReboot $ScheduleReboot
Write-Output "Script completed."
exit 0