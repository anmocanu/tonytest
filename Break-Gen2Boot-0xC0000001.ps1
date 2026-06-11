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
    [string]$ScheduleReboot = "YES",
    [string]$AsyncDetonate = "YES",
    [int]$DelaySeconds = 90
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
    $psi.Arguments = $Arguments -join " "

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
    $psi.Arguments = "/enum {current} /v"

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

function Get-OsLoaderIdentifiers {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "bcdedit.exe"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = "/enum osloader /v"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $combined = ""
    if ($stdout) { $combined += $stdout }
    if ($stderr) { $combined += "`r`n" + $stderr }

    $ids = @()
    $matches = [regex]::Matches($combined, "(?im)^identifier\s+(\{[^\}]+\})\s*$")
    foreach ($m in $matches) {
        $id = $m.Groups[1].Value
        if ($id -notin @("{bootmgr}", "{fwbootmgr}")) {
            $ids += $id
        }
    }

    return ($ids | Select-Object -Unique)
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

if ($AsyncDetonate -eq "YES") {
    Write-Section "Deferring disruptive operation"
    Write-Output "Run mode         : deferred"
    Write-Output "Delay (seconds)  : $DelaySeconds"
    Write-Output "Schedule reboot  : $ScheduleReboot"

    $selfPath = $PSCommandPath
    if (-not $selfPath) {
        $selfPath = $MyInvocation.MyCommand.Path
    }

    if (-not $selfPath -or -not (Test-Path $selfPath)) {
        Write-Error "Could not resolve script path for deferred execution."
        exit 21
    }

    $deferredLog = "C:\Windows\Temp\Break-Gen2Boot-deferred.log"
    $escapedPath = $selfPath.Replace("'", "''")
    $command = "Start-Sleep -Seconds $DelaySeconds; & '$escapedPath' -ScheduleReboot $ScheduleReboot -AsyncDetonate NO -DelaySeconds 0 *>> '$deferredLog'"

    try {
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-Command", $command
        ) | Out-Null
    }
    catch {
        Write-Error "Failed to launch deferred worker process: $($_.Exception.Message)"
        exit 22
    }

    Write-Output "Deferred worker launched successfully."
    Write-Output "Worker log path: $deferredLog"
    Write-Output "Exiting now so RunCommand can complete before reboot/break."
    exit 0
}

Write-Section "Gen2 BCD Current Loader Break"
Write-Output "Target     : 0xC0000001 / STATUS_UNSUCCESSFUL"
Write-Output "Method     : delete BCD device and osdevice from all osloader entries"
Write-Output "Scope      : all discovered boot loader identifiers (+ aliases)"
Write-Output "Lab warning: this intentionally makes the VM non-bootable"

Write-Section "Pre-mutation BCD state"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/enum", "osloader", "/v") | Out-Null

$loaderIds = Get-OsLoaderIdentifiers
if (-not $loaderIds -or $loaderIds.Count -eq 0) {
    Write-Error "Could not resolve osloader identifiers from BCD store."
    exit 11
}

Write-Output "Discovered osloader IDs: $($loaderIds -join ', ')"

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
foreach ($loaderId in $loaderIds) {
    Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", $loaderId, "kernel") -AllowFailure | Out-Null
    Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", $loaderId, "path", "\Windows\System32\winload.efi") -AllowFailure | Out-Null
    Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/set", $loaderId, "systemroot", "\Windows") -AllowFailure | Out-Null
}
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "kernel") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{default}", "kernel") -AllowFailure | Out-Null

Write-Section "Deleting BCD device and osdevice from osloader entries"
foreach ($loaderId in $loaderIds) {
    Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", $loaderId, "device") -AllowFailure | Out-Null
    Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", $loaderId, "osdevice") -AllowFailure | Out-Null
}
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "device") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{current}", "osdevice") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{default}", "device") -AllowFailure | Out-Null
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/deletevalue", "{default}", "osdevice") -AllowFailure | Out-Null

Write-Section "Post-mutation BCD state"
Invoke-Native -FilePath "bcdedit.exe" -Arguments @("/enum", "osloader", "/v") | Out-Null

Write-Section "Validation"
$bcdText = Get-CurrentBcdText

$devicePresent = Test-BcdElementPresent -BcdText $bcdText -ElementName "device"
$osdevicePresent = Test-BcdElementPresent -BcdText $bcdText -ElementName "osdevice"

Write-Output "device present after mutation   : $devicePresent"
Write-Output "osdevice present after mutation : $osdevicePresent"

$defaultTextPath = "C:\Windows\Temp\bcd-default-snapshot.txt"
$defaultText = ""
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "bcdedit.exe"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = "/enum {default} /v"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($stdout) { $defaultText += $stdout }
    if ($stderr) { $defaultText += "`r`n" + $stderr }

    Set-Content -Path $defaultTextPath -Value $defaultText -Encoding ASCII -Force
} catch {
    Write-Warning "Failed to capture {default} snapshot for validation: $($_.Exception.Message)"
}

$defaultDevicePresent = $false
$defaultOsdevicePresent = $false
if ($defaultText) {
    $defaultDevicePresent = Test-BcdElementPresent -BcdText $defaultText -ElementName "device"
    $defaultOsdevicePresent = Test-BcdElementPresent -BcdText $defaultText -ElementName "osdevice"
}

Write-Output "{default} device present         : $defaultDevicePresent"
Write-Output "{default} osdevice present       : $defaultOsdevicePresent"

if ($devicePresent -or $osdevicePresent -or $defaultDevicePresent -or $defaultOsdevicePresent) {
    Write-Error "Validation failed. device/osdevice are still present in active/default loader views. The boot-breaking mutation did not apply cleanly."
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
    $shutdownExitCode = Invoke-Native -FilePath "shutdown.exe" -Arguments @("/r", "/f", "/t", "10") -AllowFailure
    if ($shutdownExitCode -ne 0) {
        Write-Warning "shutdown.exe failed in RunCommand context (ExitCode=$shutdownExitCode). Falling back to Restart-Computer."
        try {
            Restart-Computer -Force
        }
        catch {
            Write-Warning "Restart-Computer fallback also failed: $($_.Exception.Message)"
        }
    }
}
else {
    Write-Output ""
    Write-Output "Reboot not scheduled because ScheduleReboot was not YES."
}

Write-Output ""
Write-Output "Script completed."
exit 0