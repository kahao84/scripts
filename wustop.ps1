<#
.SYNOPSIS
    Pause Windows Update for 3650 days (Windows 10 / 11).

.DESCRIPTION
    Windows Settings only allows pausing updates for up to 35 days, but the
    pause state itself is stored as UTC timestamps in the registry key
    HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings.

    This script writes those timestamps directly (start = now, expiry =
    now + 3650 days, i.e. about 10 years) and also sets
    FlightSettingsMaxPauseDays = 3650 so the Settings UI agrees with the
    extended pause window.

    It does NOT disable the Windows Update service, so manual update checks
    and Microsoft Defender definition updates keep working.

.PARAMETER Days
    Number of days to pause updates. Default: 3650.

.PARAMETER Resume
    Remove the pause values again (resume Windows Update).

.NOTES
    Author  : Brian Lee (kahao84)
    Version : 1.0 - 2026-10-21
    Requires: Windows 10 / 11, Windows PowerShell 5.1+,
              Administrator rights (re-launches itself elevated if needed).

.EXAMPLE
    .\wustop.ps1
    Pause Windows Update for 3650 days.

.EXAMPLE
    .\wustop.ps1 -Resume
    Resume Windows Update (remove the pause).
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 36500)]
    [int]$Days = 3650,

    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

# --- Self-elevate to Administrator if needed ---------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Resume) { $argList += '-Resume' } else { $argList += @('-Days', $Days) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
}

$settingsPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$pauseValues  = @(
    'PauseUpdatesStartTime',
    'PauseUpdatesExpiryTime',
    'PauseFeatureUpdatesStartTime',
    'PauseFeatureUpdatesEndTime',
    'PauseQualityUpdatesStartTime',
    'PauseQualityUpdatesEndTime'
)

# --- Resume: remove all pause values ------------------------------------------
if ($Resume) {
    foreach ($name in ($pauseValues + 'FlightSettingsMaxPauseDays')) {
        Remove-ItemProperty -Path $settingsPath -Name $name -ErrorAction SilentlyContinue
    }
    Write-Host 'Windows Update pause removed. Updates will resume on the next scan.' -ForegroundColor Green
    return
}

# --- Make sure the key exists --------------------------------------------------
if (-not (Test-Path $settingsPath)) {
    New-Item -Path $settingsPath -Force | Out-Null
}

# --- Back up the current key (best effort) -------------------------------------
$backupFile = Join-Path $env:TEMP ("WU-UX-Settings-backup-{0}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
& reg.exe export 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' $backupFile /y 2>$null | Out-Null
if (Test-Path $backupFile) {
    Write-Host "Current settings backed up to: $backupFile"
}

# --- Write the pause timestamps (UTC, ISO 8601 - the format Settings uses) -----
$startUtc   = (Get-Date).ToUniversalTime()
$expiryUtc  = $startUtc.AddDays($Days)
$fmt        = 'yyyy-MM-ddTHH:mm:ssZ'
$startStr   = $startUtc.ToString($fmt)
$expiryStr  = $expiryUtc.ToString($fmt)

Set-ItemProperty -Path $settingsPath -Name 'PauseUpdatesStartTime'        -Value $startStr
Set-ItemProperty -Path $settingsPath -Name 'PauseUpdatesExpiryTime'       -Value $expiryStr
Set-ItemProperty -Path $settingsPath -Name 'PauseFeatureUpdatesStartTime' -Value $startStr
Set-ItemProperty -Path $settingsPath -Name 'PauseFeatureUpdatesEndTime'   -Value $expiryStr
Set-ItemProperty -Path $settingsPath -Name 'PauseQualityUpdatesStartTime' -Value $startStr
Set-ItemProperty -Path $settingsPath -Name 'PauseQualityUpdatesEndTime'   -Value $expiryStr
Set-ItemProperty -Path $settingsPath -Name 'FlightSettingsMaxPauseDays'   -Value $Days -Type DWord

# --- Verify ---------------------------------------------------------------------
$check = Get-ItemProperty -Path $settingsPath
Write-Host ''
Write-Host "Windows Update is now paused for $Days days." -ForegroundColor Green
Write-Host "  Paused from : $($check.PauseUpdatesStartTime) (UTC)"
Write-Host "  Paused until: $($check.PauseUpdatesExpiryTime) (UTC)  ->  $($expiryUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm')) local time"
Write-Host ''
Write-Host 'Open Settings > Windows Update to see the new pause date (restart the Settings app if it was already open).'
Write-Host 'To undo later, run:  .\wustop.ps1 -Resume'
