# restoreicon.ps1 - Rebuild Windows icon cache to restore default app icons
# Usage: irm https://kahao84.github.io/scripts/restoreicon.ps1 | iex
# Safe to run as current user (no admin required); Explorer will briefly restart.

Write-Host "Stopping Explorer..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$local = $env:LOCALAPPDATA
$paths = @(
    "$local\IconCache.db",
    "$local\Microsoft\Windows\Explorer\iconcache*",
    "$local\Microsoft\Windows\Explorer\thumbcache*"
)
foreach ($p in $paths) {
    Remove-Item $p -Force -ErrorAction SilentlyContinue
}

Start-Process explorer.exe
Write-Host "Done. If some icons still look wrong, reboot once." -ForegroundColor Green
