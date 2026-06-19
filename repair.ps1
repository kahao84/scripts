$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting Admin Privileges..." -ForegroundColor Yellow  
    $scriptUrl = "https://kahao.github.io/tools/repair.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm $scriptUrl | iex`""
    Exit
}

Write-Host "Starting System Repair [Administrator Mode]..." -ForegroundColor Green

Write-Host "Running DISM RestoreHealth..." -ForegroundColor Cyan
dism /online /cleanup-image /restorehealth

Write-Host "Running SFC /scannow (Pass 1/2)..." -ForegroundColor Cyan
sfc /scannow

Write-Host "Running DISM RestoreHealth..." -ForegroundColor Cyan
dism /online /cleanup-image /restorehealth

Write-Host "Running SFC /scannow (Pass 2/2)..." -ForegroundColor Cyan
sfc /scannow

Write-Host "Repair completed! A system reboot is recommended." -ForegroundColor Green

Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
