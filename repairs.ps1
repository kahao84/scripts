# Auto-Elevate Module
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://kahao.github.io/tools/repair.ps1 | iex`""
    Exit
}

# Select action before starting
Write-Host "Select action for after repair:" -ForegroundColor Yellow
$choice = Read-Host "[R]eboot, [S]hutdown, [N]one"

Write-Host "`nStarting System Repair..." -ForegroundColor Green

# Repair Logic
Write-Host "Running DISM..." -ForegroundColor Cyan
dism /online /cleanup-image /restorehealth
Write-Host "Running SFC (Pass 1)..." -ForegroundColor Cyan
sfc /scannow

Write-Host "Running DISM..." -ForegroundColor Cyan
dism /online /cleanup-image /restorehealth
Write-Host "Running SFC (Pass 2)..." -ForegroundColor Cyan
sfc /scannow

# Regret logic
if ($choice -match 'R|S') {
    Write-Host "`nRepair finished. Action scheduled in 30 seconds." -ForegroundColor Yellow
    Write-Host "Press any key to cancel..." -ForegroundColor White
    
    for ($i = 30; $i -gt 0; $i--) {
        if ([System.Console]::KeyAvailable) {
            $null = [System.Console]::ReadKey($true)
            Write-Host "`nAction aborted by user." -ForegroundColor Red
            return
        }
        Write-Host "Executing in $i seconds... " -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    
    # Execute action
    if ($choice -eq 'R') { Restart-Computer -Force }
    elseif ($choice -eq 'S') { Stop-Computer -Force }
} else {
    Write-Host "`nRepair finished." -ForegroundColor Green
}
