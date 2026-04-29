<#
  BreakGen2Boot-Wrapper.ps1
  Purpose:
    - Allow RunCommand to succeed immediately
    - Asynchronously break Gen2 / UEFI boot by renaming bootmgfw.efi
    - Reboot VM after EFI mutation
    - Leave forensic markers on disk for debugging

  Safe for LabBox / training subscriptions only
#>

$ErrorActionPreference = 'Stop'

# --- configuration ---
$DelaySeconds = 120
$WorkDir      = "C:\ProgramData\LabBox"
$PayloadPath  = "$WorkDir\BreakEFI.ps1"

# --- ensure working directory ---
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# --- write payload to disk (NO encoding / NO base64) ---
@"
Start-Sleep -Seconds $DelaySeconds

New-Item -Path C:\LabBox -ItemType Directory -Force | Out-Null
Set-Content -Path C:\LabBox\payload_started.txt -Value (Get-Date)

# Select a safe free drive letter for ESP
`$preferredLetters = 'S','Y','Z','T','U','V','W','X'
`$used = (Get-PSDrive -PSProvider FileSystem).Name
`$letter = (`$preferredLetters | Where-Object { `$_ -notin `$used } | Select-Object -First 1)

if (-not `$letter) {
  Set-Content C:\LabBox\no_free_drive_letter.txt (Get-Date)
  exit 1
}

# Mount EFI System Partition
cmd /c "mountvol `$letter`: /S" | Out-Null

`$efiLoader = "`$letter`:\EFI\Microsoft\Boot\bootmgfw.efi"

if (-not (Test-Path `$efiLoader)) {
  Set-Content C:\LabBox\efi_not_found.txt `$efiLoader
  cmd /c "mountvol `$letter`: /D" | Out-Null
  exit 2
}

# Rename ACTIVE Gen2 bootloader
Rename-Item -Path `$efiLoader -NewName "bootmgfw.efi.bak" -Force
Set-Content C:\LabBox\efi_renamed.txt (Get-Date)

# Dismount ESP
cmd /c "mountvol `$letter`: /D" | Out-Null

# Reboot to trigger failure
shutdown /r /t 15 /c "LabBox: Rebooting to reproduce Gen2 UEFI boot failure"
"@ | Set-Content -Path $PayloadPath -Encoding UTF8

# --- launch payload asynchronously ---
Start-Process -FilePath "powershell.exe" `
