<#
  Break-Gen2Boot_v2.ps1
  LabBox intent: deterministically break Gen2/UEFI boot by renaming the Windows Boot Manager EFI file.
  Behavior: completes successfully (exit 0) then reboots.
#>

$ErrorActionPreference = 'Stop'

$preferredLetters = @('S','Y','Z','T','U','V','W','X')

function Refresh-Drives {
  # PowerShell may not see newly mounted ESP immediately; force a rescan. [5](https://learn.microsoft.com/en-us/archive/blogs/sergey_babkins_blog/how-to-mount-a-system-partition)
  $null = Get-PSDrive | Out-Null
  Start-Sleep -Seconds 1
  $null = Get-PSDrive | Out-Null
}

function Get-FreeLetter {
  $used = (Get-PSDrive -PSProvider FileSystem).Name
  foreach ($l in $preferredLetters) { if ($used -notcontains $l) { return $l } }
  throw "No free drive letter found."
}

function Try-MountEspWithMountvol([string]$letter) {
  $dl = "$letter`:"
  $out = cmd /c "mountvol $dl /S" 2>&1 | Out-String
  Write-Output $out.Trim()
  Refresh-Drives
  if (Test-Path "$dl\") { return $true }
  cmd /c "mountvol $dl /D" 2>&1 | Out-String | Write-Output
  Refresh-Drives
  return $false
}

function MountEspFallbackWithPartitionCmdlets([string]$letter) {
  $espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
  $dl = "$letter`:"
  $esp = Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq $espGuid } | Select-Object -First 1
  if (-not $esp) { throw "ESP not found on Disk 0." }
  Add-PartitionAccessPath -DiskNumber 0 -PartitionNumber $esp.PartitionNumber -AccessPath "$dl\"
  Refresh-Drives
  if (-not (Test-Path "$dl\")) { throw "Assigned $dl but not visible." }
}

function DismountEsp([string]$letter, [string]$method) {
  $dl = "$letter`:"
  try {
    if ($method -eq 'mountvol') {
      cmd /c "mountvol $dl /D" 2>&1 | Out-String | Write-Output
    } else {
      $espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
      $esp = Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq $espGuid } | Select-Object -First 1
      if ($esp) { Remove-PartitionAccessPath -DiskNumber 0 -PartitionNumber $esp.PartitionNumber -AccessPath "$dl\" }
    }
    Refresh-Drives
  } catch { Write-Warning $_.Exception.Message }
}

$letter = Get-FreeLetter
$method = $null

try {
  Write-Output "=== BreakGen2BootV2 start ==="
  if (Try-MountEspWithMountvol -letter $letter) { $method = 'mountvol' }
  else { MountEspFallbackWithPartitionCmdlets -letter $letter; $method = 'partition' }

  $dl = "$letter`:"
  $bootMgr = "$dl\EFI\Microsoft\Boot\bootmgfw.efi"
  $bootMgrBak = "$dl\EFI\Microsoft\Boot\bootmgfw.efi.bak"

  if (-not (Test-Path $bootMgr)) { throw "EFI boot manager not found at $bootMgr" }
  if (-not (Test-Path $bootMgrBak)) { Rename-Item -Path $bootMgr -NewName "bootmgfw.efi.bak" -Force }

} finally {
  if ($method) { DismountEsp -letter $letter -method $method }
}

Write-Output "Scheduling reboot in 30 seconds..."
cmd /c 'shutdown /r /t 30 /c "LabBox: rebooting to reproduce Gen2 UEFI boot failure"' | Out-String | Write-Output
Write-Output "=== BreakGen2BootV2 completed (reboot scheduled) ==="
exit 0
