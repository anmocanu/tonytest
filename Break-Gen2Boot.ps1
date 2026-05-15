<#
  Break-Gen2Boot-OSBucket.ps1
  Method: [POWERSHELL] Decoupled via Start-Process
  Goal: Success in Portal (Run Command) + Gen2 "No bootable device" error
#>

$ErrorActionPreference = 'Stop'

# 1. Define the Background Payload
# This is the part that actually breaks the VM.
$payload = {
    # Wait 60 seconds to allow the Run Command agent to report success and exit
    Start-Sleep -Seconds 60
    
    # Mount the EFI Partition
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
    mountvol "$($letter):" /S
    
    $efiFile = "$($letter):\EFI\Microsoft\Bootootmgfw.efi"
    
    # Take ownership and delete the bootloader
    if (Test-Path $efiFile) {
        takeown /f $efiFile /a
        icacls $efiFile /grant administrators:F /c
        Remove-Item -Path $efiFile -Force
        
        # Immediate Reboot
        Restart-Computer -Force
    }
}

# 2. Launch the payload as a SEPARATE process
# This returns control to the Run Command agent IMMEDIATELY.
Start-Process powershell.exe -ArgumentList "-NoProfile", "-Command", "& {$($payload.ToString())}"

Write-Output "Background process initiated. Reporting success to Run Command handler..."
exit 0
