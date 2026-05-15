<#
  Break-Gen2Boot-OSBucket.ps1
  Merged Strategy: FAT32 Fix + [POWERSHELL] Background Logic
#>

$ErrorActionPreference = 'Stop'

# 1. THE "MESSING THINGS UP" PAYLOAD
# This is a script block that will run in the background.
$payload = {
    # [BAT] Logic: Wait 60s so the portal turns Green first
    Start-Sleep -Seconds 60
    
    # FAT32 Mutation (The part that actually works on Server 2025)
    mountvol S: /S
    $efiFile = "S:\EFI\Microsoft\Boot\bootmgfw.efi"
    if (Test-Path $efiFile) {
        attrib.exe -r -s -h $efiFile
        Remove-Item -Path $efiFile -Force
    }
    mountvol S: /D
    
    # [POWERSHELL] Logic: Force the break
    Restart-Computer -Force
}

# 2. THE TRIGGER
# Clear OOBE barrier immediately
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# Launch the payload as a detached process
# This allows THIS script to exit NOW and report success to Azure.
Start-Process powershell.exe -ArgumentList "-NoProfile", "-Command", "& {$($payload.ToString())}"

Write-Output "Background process launched. Portal will show Success shortly."
exit 0
