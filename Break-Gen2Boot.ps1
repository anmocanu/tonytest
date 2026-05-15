<#
  Break-Gen2Boot-OSBucket.ps1
  Merged Strategy: FAT32 Fix + [POWERSHELL] Encoded Background Logic
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE barrier immediately to let the Agent breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. THE COMMAND STRING
# We write the logic as a single string to ensure no variable loss.
$cmd = {
    Start-Sleep -Seconds 60
    & cmd.exe /c "mountvol S: /S"
    $efi = "S:\EFI\Microsoft\Boot\bootmgfw.efi"
    if (Test-Path $efi) {
        & attrib.exe -r -s -h $efi
        Remove-Item -Path $efi -Force
    }
    & cmd.exe /c "mountvol S: /D"
    Restart-Computer -Force
}.ToString()

# Encode to Base64 to bypass any string parsing issues in the new process
$bytes = [System.Text.Encoding]::Unicode.GetBytes($cmd)
$encoded = [Convert]::ToBase64String($bytes)

# 3. THE TRIGGER
# Launch as a completely detached process using the EncodedCommand switch
Write-Output "Background process launched. Reporting success to Azure..."
Start-Process powershell.exe -ArgumentList "-NoProfile", "-EncodedCommand", $encoded

exit 0
