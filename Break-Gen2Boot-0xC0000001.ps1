<#
Break-Gen2Boot-0xC0000001.ps1

Purpose:
    Gen2/UEFI: reliably produce 0xC0000001 (STATUS_UNSUCCESSFUL) on Windows Server 2025
    by redirecting the BCD 'systemroot' to a fake Windows directory containing a real
    kernel image alongside an internally-corrupt SYSTEM registry hive.

Strategy 6 — Fake SystemRoot + SYSTEM Hive Cell Corruption
-----------------------------------------------------------
winload.efi loads OS files in this order:
    1. Locate OS volume via BCD 'osdevice'                -> success (untouched)
    2. Load ntoskrnl.exe from <systemroot>\system32\      -> success (real binary copied)
    3. Load hal.dll from <systemroot>\system32\           -> success (real binary copied)
    4. Load SYSTEM hive from <systemroot>\system32\config\SYSTEM
       -> FAILS with STATUS_UNSUCCESSFUL (0xC0000001)

    REGF hive format detail:
        Offset 0x000-0x1FB  : Base block. Adler32 checksum covers ONLY these bytes.
        Offset 0x1000       : First hive bin ("hbin" magic).
        Offset 0x1020       : First cell in first bin = root key NK node.
    Zeroing bytes 0x1020-0x109F leaves the file openable ("regf" magic + checksum
    both intact) but destroys the root-key cell, causing CmLoadSystemHive() inside
    winload.efi to return STATUS_UNSUCCESSFUL.

Why previous strategies failed:
    1. BCD path / ramdisk / EMS mutations     -> bcdedit parser rejected unknown tokens;
                                                 Azure RunCommand strips {} GUID tokens.
    2. Live registry key injection             -> VBS + Last Known Good Config revert
                                                 silently undoes changes on forced reboot.
    3. AppInit_DLLs hooking                   -> Ignored for IMAGE_DLLCHARACTERISTICS_
                                                 FORCE_INTEGRITY code-signed binaries.
    4. FileStream / BinaryWriter on hive/BCD  -> NT object manager exclusive oplock;
                                                 FileShare.ReadWrite still denied (0x80070005).
    5. Magic byte flip of winload.efi         -> Boot Manager flags STATUS_INVALID_IMAGE_
                                                 FORMAT (0xC000007B), not 0xC0000001.

Defense bypass employed here:
    - BCD 'systemroot' is NOT validated by Secure Boot or VBS at write time.
    - We create a NEW directory; no protected path is touched.
    - The fake SYSTEM hive is built from 'reg save' (registry API export, no file lock).
    - WinRE is disabled at BOTH the loader and bootmgr BCD levels before reboot.

Designed for Azure RunCommand (non-interactive, SYSTEM context).
#>

param(
    [string]$IUnderstand    = "NO",
    [string]$ScheduleReboot = "YES",
    [ValidateSet("StructuralCorrupt", "SemanticPoison", "SemanticPoisonStrict")]
    [string]$Mode = "SemanticPoisonStrict"
)

$ErrorActionPreference = "Stop"

# ── helpers ────────────────────────────────────────────────────────────────────

function Invoke-CmdChecked {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$AllowFailure
    )
    # PowerShell 7 can promote native stderr to terminating errors when
    # ErrorActionPreference=Stop. Temporarily disable that behavior so we can
    # make decisions strictly by native process exit code.
    $hasNativeErrPref = $null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($hasNativeErrPref) {
        $oldNativeErrPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $out  = & cmd.exe /d /s /c "$Command" 2>&1
        $code = $LASTEXITCODE
    } finally {
        if ($hasNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $oldNativeErrPref
        }
    }

    if (-not $AllowFailure -and $code -ne 0) {
        throw "Command failed (exit $code): $Command`n$out"
    }
    if ($AllowFailure -and $code -ne 0) {
        Write-Warning "AllowFailure command returned exit ${code}: $Command"
    }
    return $out
}

function Get-OsLoaderIdentifier {
    param([Parameter(Mandatory)][string]$StorePath)
    $enum   = Invoke-CmdChecked -Command "bcdedit /store $StorePath /enum all"
    $blocks = ($enum -join "`n") -split "`r?`n`r?`n"
    foreach ($block in $blocks) {
        if ($block -match "Windows Boot Loader" -and
            $block -match "path\s+\\Windows\\system32\\winload\.efi") {
            $idLine = ($block -split "`r?`n" |
                       Where-Object { $_ -match "^identifier\s+" } |
                       Select-Object -First 1)
            if ($idLine -and $idLine -match "identifier\s+(\{[^\}]+\})") {
                return $matches[1]
            }
        }
    }
    return $null
}

# ── Strategy 6: build fake systemroot with a corrupt SYSTEM hive ──────────────

function Build-FakeSystemRoot {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("StructuralCorrupt", "SemanticPoison", "SemanticPoisonStrict")]
        [string]$Mode
    )
    <#
    .SYNOPSIS
        Creates C:\Windows_LAB with a real kernel/HAL and a corrupt SYSTEM hive.
    .NOTES
        winload.efi reads the SYSTEM hive BEFORE enumerating boot drivers, so the
        failure occurs at hive-init time regardless of what drivers are present.
        Minimum required files in the fake tree:
            \system32\ntoskrnl.exe   (real — winload.efi must clear image-load phase)
            \system32\hal.dll        (real — winload.efi must clear image-load phase)
            \system32\config\SYSTEM  (corrupt — triggers STATUS_UNSUCCESSFUL)
    #>
    Write-Output ""
    Write-Output "=== Phase 1: Building fake system root (C:\Windows_LAB) ==="

    $fakeRoot   = "C:\Windows_LAB"
    $fakeSys32  = "$fakeRoot\system32"
    $fakeConfig = "$fakeSys32\config"

    foreach ($dir in @($fakeSys32, $fakeConfig)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Copy the real kernel and HAL so winload.efi clears load steps 2 and 3.
    Write-Output "  Copying ntoskrnl.exe and hal.dll ..."
    Copy-Item "C:\Windows\System32\ntoskrnl.exe" "$fakeSys32\ntoskrnl.exe" -Force
    Copy-Item "C:\Windows\System32\hal.dll"      "$fakeSys32\hal.dll"      -Force

    # Export the live SYSTEM hive via the registry API.
    # 'reg save' reads the in-memory hive image through the NT registry manager,
    # bypassing the kernel-level file lock on the raw .hiv file on disk.
    $exportPath = "C:\Windows\Temp\SYSTEM_LAB_export.hiv"
    if (Test-Path $exportPath) { Remove-Item $exportPath -Force }
    Write-Output "  Exporting SYSTEM hive via 'reg save' ..."
    Invoke-CmdChecked -Command "reg save HKLM\SYSTEM `"$exportPath`" /y"

    if ($Mode -eq "StructuralCorrupt") {
        # Corrupt the exported hive structurally.
        #
        # REGF base block layout (first 512 bytes):
        #   0x000-0x003  "regf" signature
        #   0x004-0x007  Primary sequence number
        #   0x008-0x00B  Secondary sequence number
        #   0x028-0x02B  Root cell offset (relative to start of first hive bin)
        #   0x1C8-0x1CB  Adler32 checksum of bytes 0x000-0x1FB  <-- covers base block only
        #
        # First hive bin (starts at file offset 0x1000 = 4096):
        #   0x1000-0x1003  "hbin" signature
        #   0x1020+        First cell — the root key NK node
        #
        # By zeroing 0x1020-0x109F we destroy the NK header (magic "nk", flags, subkey
        # count, value count, class name offset). The base-block checksum is untouched
        # so CmpInitHiveFromFile() passes integrity checks but hive traversal fails.
        Write-Output "  Mode=StructuralCorrupt: zeroing root-key NK cell (0x1020-0x109F) ..."
        [byte[]]$hiveBytes = [System.IO.File]::ReadAllBytes($exportPath)

        if ($hiveBytes.Length -gt 0x1100) {
            $start = 0x1020
            $end   = 0x109F
            for ($i = $start; $i -le $end; $i++) {
                $hiveBytes[$i] = 0x00
            }
            Write-Output ("  Zeroed {0} bytes (0x{1:X4} - 0x{2:X4})." -f ($end - $start + 1), $start, $end)
        } else {
            # Fallback: strip all hive bins.
            Write-Warning "  Exported hive is unexpectedly small; applying truncation fallback."
            $hiveBytes = $hiveBytes[0..0x1FF]
        }

        [System.IO.File]::WriteAllBytes($exportPath, $hiveBytes)
    } else {
        # Semantic poison path:
        # Keep hive structurally valid but break control-set selection logic.
        # This often avoids explicit 0xC000014C mapping and increases chances of
        # surfacing generic STATUS_UNSUCCESSFUL (0xC0000001).
        $mountKey = "HKLM\LABSYS"
        Invoke-CmdChecked -Command "reg unload $mountKey" -AllowFailure | Out-Null
        Write-Output "  Mode=${Mode}: loading exported hive to $mountKey ..."
        Invoke-CmdChecked -Command "reg load $mountKey `"$exportPath`""
        try {
            Write-Output "  Rebuilding Select key with poisoned control-set selectors ..."
            Invoke-CmdChecked -Command "reg delete $mountKey\Select /f" -AllowFailure | Out-Null
            Invoke-CmdChecked -Command "reg add $mountKey\Select /f" | Out-Null
            Invoke-CmdChecked -Command "reg add $mountKey\Select /v Current /t REG_DWORD /d 4294967295 /f" | Out-Null
            Invoke-CmdChecked -Command "reg add $mountKey\Select /v Default /t REG_DWORD /d 4294967295 /f" | Out-Null
            Invoke-CmdChecked -Command "reg add $mountKey\Select /v LastKnownGood /t REG_DWORD /d 4294967295 /f" | Out-Null
            Invoke-CmdChecked -Command "reg add $mountKey\Select /v Failed /t REG_DWORD /d 4294967295 /f" | Out-Null

            if ($Mode -eq "SemanticPoison") {
                # Legacy semantic poison (more destructive): remove all candidate control sets.
                Invoke-CmdChecked -Command "reg delete $mountKey\ControlSet001 /f" -AllowFailure | Out-Null
                Invoke-CmdChecked -Command "reg delete $mountKey\ControlSet002 /f" -AllowFailure | Out-Null
                Invoke-CmdChecked -Command "reg delete $mountKey\CurrentControlSet /f" -AllowFailure | Out-Null
                Write-Output "  SemanticPoison: removed ControlSet001/002/CurrentControlSet."
            } else {
                # Strict semantic poison: keep hive structure and control sets present.
                # This reduces the likelihood of a direct "registry file missing/corrupt"
                # mapping and can surface a more generic loader failure code.
                Write-Output "  SemanticPoisonStrict: control sets retained; selectors poisoned only."
            }
        } finally {
            Invoke-CmdChecked -Command "reg unload $mountKey" -AllowFailure | Out-Null
        }
    }

    Copy-Item $exportPath "$fakeConfig\SYSTEM" -Force
    Write-Output "  Mutated SYSTEM hive placed at: $fakeConfig\SYSTEM"
    Write-Output "  Fake system root ready: $fakeRoot"
}

# ── main ───────────────────────────────────────────────────────────────────────

if ($IUnderstand -ne "YES") {
    Write-Error "Safety check failed. Set -IUnderstand YES to proceed."
    exit 2
}

# Phase 1: build the fake systemroot BEFORE touching the BCD store so that if the
# directory step fails we have not yet dirtied the bootloader configuration.
Write-Output "Checkpoint: entering Phase 1 (fake system root build)."
Build-FakeSystemRoot -Mode $Mode
Write-Output "Checkpoint: Phase 1 complete. Proceeding to EFI BCD mutation phase."

# Phase 2: modify the EFI BCD store.
$efiDrive = "S:"
$efiBcd   = "$efiDrive\EFI\Microsoft\Boot\BCD"

Write-Output ""
Write-Output "=== Phase 2: EFI BCD mutations ==="

Write-Output "Mounting EFI System Partition to $efiDrive ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /S" | Out-Null

if (!(Test-Path $efiBcd)) {
    Write-Error "EFI BCD not found at $efiBcd. Aborting."
    Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
    exit 3
}

Write-Output "Backing up EFI BCD ..."
try {
    Copy-Item -Path $efiBcd -Destination "$efiBcd.bak" -Force
    Write-Output "  Backup: $efiBcd.bak"
} catch {
    Write-Output "  Backup failed (non-fatal): $($_.Exception.Message)"
}

Write-Output "Resolving active OS loader identifier ..."
$loaderId = Get-OsLoaderIdentifier -StorePath $efiBcd
if (-not $loaderId) {
    Write-Error "Could not find Windows Boot Loader entry in EFI BCD store."
    Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
    exit 4
}
Write-Output "  Loader ID: $loaderId"

# Redirect systemroot to our fake directory.
# winload.efi loads ntoskrnl.exe + hal.dll from \Windows_LAB\system32\ (succeeds),
# then attempts to load the SYSTEM hive from \Windows_LAB\system32\config\SYSTEM
# (fails -> CmLoadSystemHive returns STATUS_UNSUCCESSFUL -> boot screen: 0xC0000001).
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId systemroot \Windows_LAB"
Write-Output "  systemroot           -> \Windows_LAB"

# Verify mutation was written to BCD before continuing.
$loaderSnapshot = Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum $loaderId"
if (($loaderSnapshot -join "`n") -notmatch "(?im)^systemroot\s+\\Windows_LAB\s*$") {
    throw "BCD mutation verification failed: systemroot was not set to \\Windows_LAB"
}
Write-Output "  verification         -> systemroot confirmed in BCD"

# Keep winload.efi path pointing at the real EFI binary so Boot Manager finds it.
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId path \Windows\System32\winload.efi"
Write-Output "  path                 -> \Windows\System32\winload.efi (unchanged)"

# Disable loader-level WinRE so the raw STATUS_UNSUCCESSFUL is rendered on screen
# rather than being silently swallowed by Startup Repair.
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId recoveryenabled No"
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId bootstatuspolicy IgnoreAllFailures"
Write-Output "  recoveryenabled      -> No"
Write-Output "  bootstatuspolicy     -> IgnoreAllFailures"

# Disable bootmgr-level automatic repair.
# WS2025 has a second recovery gate at the Boot Manager layer that can intercept
# loader failures before winload.efi renders the error code to the screen.
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set {bootmgr} recoveryenabled No" -AllowFailure | Out-Null
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set {bootmgr} displaybootmenu No" -AllowFailure | Out-Null
Write-Output "  {bootmgr} recoveryenabled -> No  (suppresses pre-loader Startup Repair)"

Write-Output ""
Write-Output "Post-mutation BCD snapshot:"
$loaderSnapshot | Out-String | Write-Output

Write-Output "Dismounting EFI partition ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /D" | Out-Null

Write-Output "=== All mutations applied ==="
Write-Output "Requested mode        : $Mode"
Write-Output "Expected boot failure : 0xC0000001 (STATUS_UNSUCCESSFUL) target"
Write-Output "Failure point         : CmLoadSystemHive() inside winload.efi"
Write-Output "Corrupt file          : C:\Windows_LAB\system32\config\SYSTEM"
if ($Mode -eq "StructuralCorrupt") {
    Write-Output "Corruption details    : Root-key NK cell (0x1020-0x109F) zeroed;"
    Write-Output "                        base-block checksum intact so file opens cleanly."
} elseif ($Mode -eq "SemanticPoison") {
    Write-Output "Corruption details    : Hive structure valid but Select/ControlSet"
    Write-Output "                        resolution intentionally poisoned."
} else {
    Write-Output "Corruption details    : Hive structure valid, control sets retained,"
    Write-Output "                        Select values poisoned to invalid selectors."
    Write-Output "                        Target code is 0xC0000001 (platform-dependent)."
}

if ($ScheduleReboot -eq "YES") {
    Write-Output ""
    Write-Output "Scheduling forced reboot in 90 seconds ..."
    Invoke-CmdChecked -Command "shutdown /r /f /t 90 /c ""Lab: trigger 0xC0000001 via corrupt SYSTEM hive"""
} else {
    Write-Output "Reboot not scheduled (-ScheduleReboot NO). Restart manually when ready."
}

exit 0
