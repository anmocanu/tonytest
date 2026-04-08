<#
  BreakGen2Boot.ps1
  Purpose: Intentionally break Windows Gen2 / UEFI boot in Azure LabBox scenarios
  Method: Locate and rename the active EFI bootloader (bootmgfw.efi or bootx64.efi)
  Result: VM reboots and fails at UEFI boot stage
#>

$ErrorActionPreference = 'Stop'

# Prefer safe drive letters for ESP mount
$preferredLetters = @('S','Y','Z','T','U','V','W','X')

function Refresh-Drives {
    # PowerShell may not see newly mounted ESP immediately
    $null = Get-PSDrive | Out-Null
    Start-Sleep -Seconds 1
    $null = Get-PSDrive | Out-Null
}

function Get-FreeLetter {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($l in $preferredLetters) {
        if ($used -notcontains $l) { return $l }
    }
    throw "No free drive letter available for ESP mount."
}

function Mount-ESP {
    param([string]$Letter)

    $dl = "$Letter`:"
    Write-Output "Mounting EFI System Partition to $dl"

    $out = cmd /c "mountvol $dl /S" 2>&1 | Out-String
    Write-Output $out.Trim()
    Refresh-Drives

    if (-not (Test-Path "$dl\")) {
        throw "ESP mount failed on $dl"
    }
}

function Dismount-ESP {
    param([string]$Letter)

    $dl = "$Letter`:"
    Write-Output "Dismounting EFI System Partition from $dl"
    cmd /c "mountvol $dl /D" 2>&1 | Out-String | Write-Output
    Refresh-Drives
}

# ---------------- MAIN ----------------

$letter = Get-FreeLetter

try {
    Write-Output "=== BreakGen2BootV2 start ==="

    Mount-ESP -Letter $letter

    $efiRoot = "$letter`:\EFI"
    Write-Output "Enumerating EFI contents under $efiRoot"

    if (-not (Test-Path $efiRoot)) {
        throw "EFI root not found after mount."
    }

    # Locate active Windows EFI loader
    $efiLoaders = Get-ChildItem $efiRoot -Recurse -Filter *.efi -ErrorAction SilentlyContinue

    $bootLoader = $efiLoaders | Where-Object {
        $_.Name -ieq "bootmgfw.efi" -or $_.Name -ieq "bootx64.efi"
    } | Select-Object -First 1

    if (-not $bootLoader) {
        throw "No Windows EFI bootloader found (bootmgfw.efi or bootx64.efi)."
    }

    Write-Output "Active EFI bootloader found:"
    Write-Output "  $($bootLoader.FullName)"

    $bakPath = "$($bootLoader.FullName).bak"

    if (Test-Path $bakPath) {
        Write-Output "Backup already exists. Boot may already be broken."
    }
    else {
        Write-Output "Renaming EFI bootloader to break boot:"
        Write-Output "  $($bootLoader.FullName) -> $bakPath"
        Rename-Item -Path $bootLoader.FullName -NewName ($bootLoader.Name + ".bak") -Force
        Write-Output "EFI bootloader rename completed."
    }
}
catch {
    Write-Error $_.Exception.Message
    throw
}
finally {
    Dismount-ESP -Letter $letter
}

# Schedule reboot AFTER script success
Write-Output "Scheduling reboot in 30 seconds..."
cmd /c 'shutdown /r /t 30 /c "LabBox: rebooting to reproduce Gen2 UEFI boot failure"' | Out-String | Write-Output

Write-Output "=== BreakGen2BootV2 completed successfully (reboot scheduled) ==="
exit 0
