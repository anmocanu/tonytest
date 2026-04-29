
<#
  BreakGen2Boot-Wrapper.ps1
  Purpose: Ensure RunCommand reports Success, then break Gen2/UEFI boot asynchronously.
#>

$ErrorActionPreference = 'Stop'

# Delay long enough for RunCommand to report success back to ARM
$DelaySeconds = 120

# Prefer safe drive letters for ESP mount
$preferredLetters = @('S','Y','Z','T','U','V','W','X')

$payload = @"
`$ErrorActionPreference = 'Stop'

`$preferredLetters = @('S','Y','Z','T','U','V','W','X')

function Refresh-Drives {
  `$null = Get-PSDrive | Out-Null
  Start-Sleep -Seconds 1
  `$null = Get-PSDrive | Out-Null
}

function Get-FreeLetter {
  `$used = (Get-PSDrive -PSProvider FileSystem).Name
  foreach (`$l in `$preferredLetters) {
    if (`$used -notcontains `$l) { return `$l }
  }
  throw "No free drive letter available for ESP mount."
}

function Mount-ESP([string]`$Letter) {
  `$dl = "`$Letter`:"
  cmd /c "mountvol `$dl /S" 2>&1 | Out-String | Out-Null
  Refresh-Drives
  if (-not (Test-Path "`$dl\"))
  { throw "ESP mount failed on `$dl" }
}

function Dismount-ESP([string]`$Letter) {
  `$dl = "`$Letter`:"
  cmd /c "mountvol `$dl /D" 2>&1 | Out-String | Out-Null
  Refresh-Drives
}

Start-Sleep -Seconds $DelaySeconds

`$letter = Get-FreeLetter
try {
  Mount-ESP -Letter `$letter

  `$efiRoot = "`$letter`:\EFI"
  if (-not (Test-Path `$efiRoot)) { throw "EFI root not found after mount." }

  `$efiLoaders = Get-ChildItem `$efiRoot -Recurse -Filter *.efi -ErrorAction SilentlyContinue
  `$bootLoader = `$efiLoaders | Where-Object {
    `$_.Name -ieq "bootmgfw.efi" -or `$_.Name -ieq "bootx64.efi"
  } | Select-Object -First 1

  if (-not `$bootLoader) {
    throw "No Windows EFI bootloader found (bootmgfw.efi or bootx64.efi)."
  }

  `$bakPath = "`$(`$bootLoader.FullName).bak"

  if (-not (Test-Path `$bakPath)) {
    Rename-Item -Path `$bootLoader.FullName -NewName (`$bootLoader.Name + ".bak") -Force
  }

}
finally {
  try { Dismount-ESP -Letter `$letter } catch {}
}

# Reboot AFTER we have broken EFI bootloader
cmd /c 'shutdown /r /t 15 /c "LabBox: rebooting to reproduce Gen2 UEFI boot failure"' | Out-Null
"@

# Start a detached PowerShell that will execute the payload
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))

Start-Process -FilePath "powershell.exe" `
  -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" `
  -WindowStyle Hidden

Write-Output "Spawned async boot-break process. Will execute in $DelaySeconds seconds."
Write-Output "Returning Success so ARM/LabBox deployment can complete."
exit 0
