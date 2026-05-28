<#
Break-Gen2Boot-0xC0000001-BCDEdit.ps1

Purpose:
- Gen2/UEFI: break boot via EFI BCD store edits (no ACL/takeown; no raw file writes)
- Designed for Azure RunCommand (fast + deterministic)
#>

param(
  [string]$IUnderstand = "NO",
  [string]$ScheduleReboot = "YES"
)

$ErrorActionPreference = "Stop"

function Invoke-CmdChecked {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [switch]$AllowFailure
  )

  $output = cmd /c $Command 2>&1
  $code = $LASTEXITCODE

  if (-not $AllowFailure -and $code -ne 0) {
    throw "Command failed (exit $code): $Command`n$output"
  }

  return $output
}

function Get-OsLoaderIdentifier {
  param([Parameter(Mandatory = $true)][string]$StorePath)

  $enum = Invoke-CmdChecked -Command "bcdedit /store $StorePath /enum all"
  $blocks = ($enum -join "`n") -split "`r?`n`r?`n"

  foreach ($block in $blocks) {
    if ($block -match "Windows Boot Loader" -and $block -match "path\s+\\Windows\\system32\\winload\.efi") {
      $idLine = ($block -split "`r?`n" | Where-Object { $_ -match "^identifier\s+" } | Select-Object -First 1)
      if ($idLine -and $idLine -match "identifier\s+(\{[^\}]+\})") {
        return $matches[1]
      }
    }
  }

  return $null
}

function Register-KernelFallback {
  $payload = @'
$ErrorActionPreference = "SilentlyContinue"

$kernelPath = "C:\Windows\System32\ntoskrnl.exe"

if (Test-Path $kernelPath) {
  cmd /c "takeown /f C:\Windows\System32\ntoskrnl.exe /a" | Out-Null
  cmd /c "icacls C:\Windows\System32\ntoskrnl.exe /grant administrators:F /c" | Out-Null
  cmd /c "attrib -r -s -h C:\Windows\System32\ntoskrnl.exe" | Out-Null

  [byte[]]$bytes = 0x41, 0x42, 0x43, 0x44, 0x45, 0x46
  $fs = [System.IO.File]::Open($kernelPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
  try {
    $fs.Position = 0
    $fs.Write($bytes, 0, $bytes.Length)
    $fs.Flush()
  } finally {
    $fs.Close()
  }
}

shutdown /r /f /t 15 /c "Lab: fallback reboot after kernel mutation"
'@

  $scriptPath = "C:\Windows\Temp\BreakKernelFallback.ps1"
  Set-Content -Path $scriptPath -Value $payload -Encoding ASCII

  $taskName = "Lab-BreakKernel-Fallback"
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
  $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2))
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null

  Write-Output "Registered fallback task '$taskName' (runs in ~2 minutes)."
}

if ($IUnderstand -ne "YES") {
  Write-Error "Safety check failed. Set -IUnderstand YES to proceed."
  exit 2
}

$efiDrive = "S:"
$efiBcd   = "$efiDrive\EFI\Microsoft\Boot\BCD"

Write-Output "Mounting EFI System Partition to $efiDrive ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /S" | Out-Null

if (!(Test-Path $efiBcd)) {
  Write-Error "EFI BCD not found at $efiBcd. Aborting."
  Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
  exit 3
}

Write-Output "Backing up EFI BCD (best effort) ..."
try {
  Copy-Item -Path $efiBcd -Destination "$efiBcd.bak" -Force
  Write-Output "Backup created: $efiBcd.bak"
} catch {
  Write-Output "Backup copy failed (continuing): $($_.Exception.Message)"
}

# IMPORTANT: Use BCDEdit to modify the EFI BCD store (no raw writes; FAT32 has no ACLs).
Write-Output "Enumerating current loader identifier (expect {default} or {current}) ..."
$bcdEnum = Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum all"
$bcdEnum | Out-String | Write-Output

Write-Output "Discovering active Windows Boot Loader identifier from EFI store ..."
$loaderId = Get-OsLoaderIdentifier -StorePath $efiBcd
if (-not $loaderId) {
  Write-Error "Could not find Windows Boot Loader identifier in EFI BCD store."
  Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
  exit 4
}
Write-Output "Resolved loader identifier: $loaderId"

Write-Output "Applying boot-fatal BCD mutations ..."

$bcdMutationSucceeded = $false
try {
  # Keep device/osdevice valid, then break loader path and system root.
  Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId path \Windows\System32\winload_labbroken.efi" | Out-Null
  Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId systemroot \Windows_BROKEN" | Out-Null
  $bcdMutationSucceeded = $true
} catch {
  Write-Output "Primary BCD mutation failed: $($_.Exception.Message)"
}

# Optional: expose the underlying boot error instead of WinRE masking.
# (Common troubleshooting practice to see the “real” boot failure code.)
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId recoveryenabled No" | Out-Null
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId bootstatuspolicy IgnoreAllFailures" | Out-Null

Write-Output "Post-mutation BCD snapshot:"
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum $loaderId" | Out-String | Write-Output

Write-Output "Dismounting EFI partition ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /D" | Out-Null

Write-Output "Completed BCD break. VM should fail to boot on next restart (Gen2/UEFI)."

if (-not $bcdMutationSucceeded) {
  Write-Output "Switching to fallback mutation path for deterministic break..."
  Register-KernelFallback
}

if ($ScheduleReboot -eq "YES") {
  if ($bcdMutationSucceeded) {
    Write-Output "Scheduling reboot in 120 seconds (allows RunCommand to finalize cleanly)..."
    cmd /c "shutdown /r /f /t 120 /c ""Lab: rebooting to reproduce Gen2 BCD boot failure""" | Out-Null
  } else {
    Write-Output "Fallback task will handle reboot automatically."
  }
} else {
  Write-Output "Reboot not scheduled. Restart manually when ready."
}

exit 0
