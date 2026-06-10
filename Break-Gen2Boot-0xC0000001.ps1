<#
Break-Gen2Boot-0xC0000001-BcdCurrent.ps1

Purpose:
    Azure Generation 2 / UEFI Windows VM lab script targeting:
        0xC0000001 / STATUS_UNSUCCESSFUL

Scenario:
    Gen2 VM only.
    Best tested without Trusted Launch / Secure Boot first.

Strategy:
    BCD-only mutation against the currently booted Windows Boot Loader:
        - keep winload.efi intact
        - keep kernel intact
        - do not touch SYSTEM hive
        - do not redirect systemroot
        - remove BCD device
        - remove BCD osdevice

Reason:
    0xC0000001 is primarily a generic STATUS_UNSUCCESSFUL code.
    For Azure Windows boot labs, the closest failure class is BCD / boot-path resolution failure.
    Kernel/image tamper and SYSTEM hive corruption usually map to more specific codes.

Lab warning:
    This intentionally makes the VM non-bootable.
    Use only on disposable lab VMs.
#>

param(
    [string]$IUnderstand = "NO",
    [string]$ScheduleReboot = "YES"
)

$ErrorActionPreference = "Stop"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    Write-Output ("[cmd] {0} {1}" -f $FilePath, ($Arguments -join " "))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    foreach ($arg in $Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()

    $proc.WaitForExit()

    $exitCode = $proc.ExitCode

    if ($stdout) {
        $stdout -split "`r?`n" |
            Where-Object { $_ -ne "" } |
            ForEach-Object { Write-Output $_ }
    }

    if ($stderr) {
        $stderr -split "`r?`n" |
            Where-Object { $_ -ne "" } |
            ForEach-Object { Write-Output $_ }
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed. File=$FilePath ExitCode=$exitCode Args=$($Arguments -join ' ')"
    }

    if (($exitCode -ne 0) -and $AllowFailure) {
        Write-Warning "Command returned non-zero exit code but failure was allowed. ExitCode=$exitCode"
    }

    return $exitCode
}

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Title
    Write-Output "============================================================"
}

function Get-CurrentBcdText {
    $tempPath = "C:\Windows\Temp\bcd-current-snapshot.txt"

    if (Test-Path $tempPath) {
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "bcdedit.exe"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    [void]$psi.ArgumentList.Add("/enum")
    [void]$psi.ArgumentList.Add("{current}")
    [void]$psi.ArgumentList.Add("/v")

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $combined = ""
    if ($stdout) { $combined += $stdout }
    if ($stderr) { $combined += "`r`n" + $stderr }

    Set-Content -Path $tempPath -Value $combined -Encoding ASCII -Force

    return $combined
}

function Test-BcdElementPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BcdText,

        [Parameter(Mandatory = $true)]
        [string]$ElementName
    )

    $pattern = "(?im)^\s*$([regex]::Escape($ElementName))\s+"
    return [regex]::IsMatch($BcdText, $pattern)
}

if ($IUnderstand -ne "YES") {
    Write-Error "Safety check failed. Set -IUnderstand YES to proceed. This script intentionally makes the VM non-bootable."
    exit 2
}

Write-Section "Gen2 BCD Current Loader Break"
Write-Output "Target     : 0xC0000001 / STATUS_UNSUCCESSFUL"
Write-Output "Method     : delete BCD device and osdevice from {current}"
Write-Output "Scope      : currently booted Windows Boot Loader entry"
Write-Output "Lab warning: this intentionally makes the VM non-bootable"

Write-Section "Pre-mutation BCD state"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/enum", "{current}", "/v") | Out-Null

Write-Section "Backing up current BCD store"
$backupPath = "C:\Windows\Temp\BCD-backup-before-0xC0000001-test.bak"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/export", $backupPath) -AllowFailure | Out-Null
Write-Output "BCD export attempted to: $backupPath"

Write-Section "Disabling recovery masking - best effort"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{current}", "recoveryenabled", "No") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{current}", "bootstatuspolicy", "IgnoreAllFailures") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{bootmgr}", "recoveryenabled", "No") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{bootmgr}", "displaybootmenu", "No") -AllowFailure | Out-Null

Write-Section "Normalizing loader so this is not a kernel/image/SYSTEM-hive test"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "kernel") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{current}", "path", "\Windows\System32\winload.efi") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", "{current}", "systemroot", "\Windows") -AllowFailure | Out-Null

Write-Section "Deleting BCD device and osdevice from {current}"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "device") | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "osdevice") | Out-Null

Write-Section "Post-mutation BCD state"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/enum", "{current}", "/v") | Out-Null

Write-Section "Validation"
$bcdText = Get-CurrentBcdText

$devicePresent = Test-BcdElementPresent -BcdText $bcdText -ElementName "device"
$osdevicePresent = Test-BcdElementPresent -BcdText $bcdText -ElementName "osdevice"

Write-Output "device present after mutation   : $devicePresent"
Write-Output "osdevice present after mutation : $osdevicePresent"

if ($devicePresent -or $osdevicePresent) {
    Write-Error "Validation failed. device/osdevice are still present in {current}. The boot-breaking mutation did not apply cleanly."
    exit 10
}

Write-Output ""
Write-Output "Validation passed: device and osdevice are absent from {current}."

Write-Section "Expected result after reboot"
Write-Output "Target boot error : 0xC0000001 / STATUS_UNSUCCESSFUL"
Write-Output "Failure class     : BCD OS loader cannot resolve device/osdevice"
Write-Output "Important note    : If the VM fails with another code, the Gen2 OS/security profile is remapping the visible failure."
Write-Output "Important note    : If the VM still boots, the effective boot entry is not the mutated {current} entry or the platform repaired/ignored the missing values."

if ($ScheduleReboot -eq "YES") {
    Write-Section "Scheduling reboot"
    Invoke-Native -FilePath "shutdown.exe" -Arguments @("/r", "/f", "/t", "60", "/c", "Lab: trigger 0xC0000001 via Gen2 BCD missing device osdevice") | Out-Null
}
else {
    Write-Output ""
    Write-Output "Reboot not scheduled because ScheduleReboot was not YES."
}

Write-Output ""
Write-Output "Script completed."
exit 0