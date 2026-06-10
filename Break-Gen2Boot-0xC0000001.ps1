<#
Break-Gen2Boot-0xC0000001.ps1

Purpose:
    Gen2/UEFI Azure Windows VM lab script to target boot error:
        0xC0000001 / STATUS_UNSUCCESSFUL

Strategy:
    Use a BCD-only break by removing DEVICE and OSDEVICE from the Windows Boot Loader
    entry in the EFI BCD store.

Why this strategy:
    For exact 0xC0000001, avoid SYSTEM hive corruption, kernel tamper, winload.efi tamper,
    or fake systemroot redirection. Those usually map to more specific boot failure codes
    such as 0xC000007B, 0xC000014C, or 0xC0000225.

Designed for:
    - Azure Generation 2 Windows VM
    - UEFI boot
    - Azure Run Command
    - Disposable lab VM only
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
        [Parameter(Mandatory)][string]$Command,
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

    $code = $proc.ExitCode

    $out = @()
    if ($stdout) { $out += ($stdout -split "`r?`n") }
    if ($stderr) { $out += ($stderr -split "`r?`n") }
    $out = $out | Where-Object { $_ -ne "" }

    if (-not $AllowFailure -and $code -ne 0) {
        throw "Command failed (exit $code): $Command`n$($out -join "`n")"
    }

    if ($AllowFailure -and $code -ne 0) {
        Write-Warning "AllowFailure command returned exit ${code}: $Command"
        if ($out) {
            $out | ForEach-Object { Write-Warning "  $_" }
        }
    }

    return $out
}

function Get-OsLoaderIdentifiers {
    param(
        [Parameter(Mandatory)][string]$StorePath
    )

    Write-Output ""
    Write-Output "Collecting OS loader entries from EFI BCD store..."

    $ids = @()

    $enumOsLoader = Invoke-CmdChecked -Command "bcdedit /store $StorePath /enum osloader /v" -AllowFailure

    if ($enumOsLoader) {
        $text = $enumOsLoader -join "`n"
        $blocks = $text -split "(?im)(?=^Windows Boot Loader\s*$)"

        foreach ($block in $blocks) {
            if ($block -notmatch "(?im)^Windows Boot Loader\s*$") {
                continue
            }

            $idMatch = [regex]::Match($block, "(?im)^identifier\s+(\{[^\}]+\})")
            $pathMatch = [regex]::Match($block, "(?im)^path\s+\\Windows\\system32\\winload\.efi\s*$")

            if ($idMatch.Success -and $pathMatch.Success) {
                $id = $idMatch.Groups[1].Value

                if ($id -notin @("{bootmgr}", "{fwbootmgr}", "{memdiag}")) {
                    $ids += $id
                }
            }
        }
    }

    if ($ids.Count -eq 0) {
        Write-Output "No entries found through /enum osloader. Trying /enum all fallback..."

        $enumAll = Invoke-CmdChecked -Command "bcdedit /store $StorePath /enum all /v" -AllowFailure

        if ($enumAll) {
            $text = $enumAll -join "`n"
            $blocks = $text -split "(?im)(?=^Windows Boot Loader\s*$)"

            foreach ($block in $blocks) {
                if ($block -notmatch "(?im)^Windows Boot Loader\s*$") {
                    continue
                }

                $idMatch = [regex]::Match($block, "(?im)^identifier\s+(\{[^\}]+\})")
                $pathMatch = [regex]::Match($block, "(?im)^path\s+\\Windows\\system32\\winload\.efi\s*$")

                if ($idMatch.Success -and $pathMatch.Success) {
                    $id = $idMatch.Groups[1].Value

                    if ($id -notin @("{bootmgr}", "{fwbootmgr}", "{memdiag}")) {
                        $ids += $id
                    }
                }
            }
        }
    }

    $ids = $ids | Select-Object -Unique

    return $ids
}

function Invoke-BcdMissingDeviceBreak {
    param(
        [Parameter(Mandatory)][string]$ScheduleReboot
    )

    Write-Output ""
    Write-Output "=== BcdMissingDevice Mode: targeting exact 0xC0000001 failure class ==="
    Write-Output "This mode keeps winload.efi and systemroot valid, then removes DEVICE and OSDEVICE from the OS loader."
    Write-Output ""

    $efiDrive = "S:"
    $efiBcd   = "$efiDrive\EFI\Microsoft\Boot\BCD"

    Write-Output "Mounting EFI System Partition to $efiDrive ..."
    Invoke-CmdChecked -Command "mountvol $efiDrive /S" | Out-Null

    try {
        if (!(Test-Path $efiBcd)) {
            throw "EFI BCD store was not found at $efiBcd"
        }

        Write-Output "EFI BCD store found: $efiBcd"

        $backupPath = "$efiBcd.bak.BcdMissingDevice"
        Write-Output "Backing up EFI BCD store to: $backupPath"
        Copy-Item -Path $efiBcd -Destination $backupPath -Force

        Write-Output ""
        Write-Output "Pre-mutation BCD snapshot:"
        Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum osloader /v" -AllowFailure | Out-String | Write-Output

        $loaderIds = Get-OsLoaderIdentifiers -StorePath $efiBcd

        if (-not $loaderIds -or $loaderIds.Count -eq 0) {
            throw "Could not find Windows Boot Loader entries with path \Windows\system32\winload.efi in EFI BCD store."
        }

        Write-Output ""
        Write-Output "Resolved OS loader ID(s): $($loaderIds -join ', ')"

        foreach ($loaderId in $loaderIds) {
            Write-Output ""
            Write-Output "Applying BCD-only mutation to loader: $loaderId"

            # Keep the boot application valid.
            # This avoids Secure Boot / image format / missing winload paths from taking over the failure code.
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId path \Windows\System32\winload.efi" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId systemroot \Windows" -AllowFailure | Out-Null

            # Clear any previous lab kernel override.
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /deletevalue $loaderId kernel" -AllowFailure | Out-Null

            # Main target mutation:
            # Remove DEVICE and OSDEVICE from the OS loader entry.
            # This targets the documented BCD/missing boot path class for 0xC0000001.
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /deletevalue $loaderId device" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /deletevalue $loaderId osdevice" -AllowFailure | Out-Null

            # Avoid automatic repair masking the raw result.
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId recoveryenabled No" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId bootstatuspolicy IgnoreAllFailures" -AllowFailure | Out-Null
        }

        # Keep boot manager itself valid.
        # We do not want to break bootmgr. We only want the loader's OS partition resolution to fail.
        Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set {bootmgr} device partition=$efiDrive" -AllowFailure | Out-Null
        Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set {bootmgr} recoveryenabled No" -AllowFailure | Out-Null
        Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set {bootmgr} displaybootmenu No" -AllowFailure | Out-Null

        Write-Output ""
        Write-Output "Post-mutation BCD snapshot:"
        Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum osloader /v" -AllowFailure | Out-String | Write-Output

        Write-Output ""
        Write-Output "Expected post-mutation state:"
        Write-Output "  path       : \Windows\System32\winload.efi"
        Write-Output "  systemroot : \Windows"
        Write-Output "  kernel     : absent"
        Write-Output "  device     : absent from OS loader"
        Write-Output "  osdevice   : absent from OS loader"

    } finally {
        Write-Output ""
        Write-Output "Dismounting EFI System Partition..."
        Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
    }

    Write-Output ""
    Write-Output "=== BcdMissingDevice mutations applied ==="
    Write-Output "Target boot error : 0xC0000001 / STATUS_UNSUCCESSFUL"
    Write-Output "Failure class     : BCD OS loader cannot resolve DEVICE/OSDEVICE"
    Write-Output "Note              : If Windows Server 2025 + Trusted Launch still remaps this to another code,"
    Write-Output "                    then the remaining blocker is the platform/build/security mapping, not the script."

    if ($ScheduleReboot -eq "YES") {
        Write-Output ""
        Write-Output "Scheduling forced reboot in 90 seconds..."
        Invoke-CmdChecked -Command "shutdown /r /f /t 90 /c ""Lab: trigger 0xC0000001 via BCD missing device/osdevice"""
    } elseoot not scheduled because -ScheduleReboot NO was provided."
        Write-Output "Restart manually when ready."
    }
}

# Main

if ($IUnderstand -ne "YES") {
    Write-Error "Safety check failed. Set -IUnderstand YES to proceed. This script intentionally makes the VM non-bootable."
    exit 2
}

if ($Mode -ne "BcdMissingDevice") {
    Write-Error "Unsupported mode: $Mode. This final version supports only BcdMissingDevice for exact 0xC0000001 targeting."
    exit 3
}

Write-Output "Checkpoint: entering BcdMissingDevice mode."
Invoke-BcdMissingDeviceBreak -ScheduleReboot $ScheduleReboot

Write-Output ""
Write-Output "Script completed."
exit 0