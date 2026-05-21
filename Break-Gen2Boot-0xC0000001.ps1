<#
Break-Gen2-0xC0000001.ps1

Purpose:
- Deterministically simulate 0xC0000001 on Gen2 (UEFI) Azure VMs
- Targets EFI BCD corruption (Boot Manager stage)
- Safe for RunCommand execution (fast, no long ACL loops)
#>

$ErrorActionPreference = 'Stop'

Write-Host "Mounting EFI System Partition..."

$efiDrive = "S:"
cmd.exe /c "mountvol $efiDrive /S" | Out-Null

$bcdPath = "$efiDrive\EFI\Microsoft\Boot\BCD"

if (!(Test-Path $bcdPath)) {
    Write-Error "EFI BCD not found at $bcdPath. Abort."
    exit 1
}

Write-Host "Corrupting EFI BCD (preserving file presence)..."

# Take ownership (fast path)
takeown /f $bcdPath | Out-Null
icacls $bcdPath /grant administrators:F | Out-Null

# Corrupt content instead of deleting
# (critical for keeping Boot Manager flow intact)
Set-Content -Path $bcdPath -Value "CORRUPTED_BOOT_CONFIG"

Write-Host "Dismounting EFI partition..."
cmd.exe /c "mountvol $efiDrive /D" | Out-Null

Write-Host "Scheduling reboot..."
cmd.exe /c "shutdown /r /f /t 10"

exit 0

