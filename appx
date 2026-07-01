# Auto-Elevate Module
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://kahao.github.io/tools/apps-repair.ps1 | iex`""
    Exit
}

Write-Host "--- Windows AppX Repairing ---" -ForegroundColor Yellow
Write-Host "Re-registering all built-in Windows apps. This may take a moment..." -ForegroundColor Cyan

# core
Get-AppXPackage | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
}

Write-Host "`nApp re-registration completed!" -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
