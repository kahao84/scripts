<#
.SYNOPSIS
    Reset stuck Windows Update components (Windows 10 / 11): stop the
    update services, delete the dead cache files, restart the services.

.DESCRIPTION
    When Windows Update gets stuck (a download frozen at 0%, the same
    update failing over and over, errors such as 0x80070002 or
    0x80242016), the usual cause is a corrupt download cache. This script
    performs the standard cache reset:

        1. Stops the Windows Update services:
             wuauserv  - Windows Update
             bits      - Background Intelligent Transfer Service
             cryptsvc  - Cryptographic Services

        2. Deletes the "dead" cache files (folder CONTENTS only - the
           folders themselves are kept, Windows refills them):
             %SystemRoot%\SoftwareDistribution\Download\*
             %SystemRoot%\System32\catroot2\*
             %ProgramData%\Microsoft\Network\Downloader\qmgr*.dat
           (the last one is the BITS download queue)

        3. Restarts the services. A service whose startup type was set
           to Disabled is first set back to Manual so it can start.

    The update history database (SoftwareDistribution\DataStore) is NOT
    touched, so the installed-update history stays intact.

    Stopping is forceful and quiet: the stop request is sent without
    waiting, and a service that has not stopped within a few seconds is
    force-stopped by killing its own process (on Windows 10 / 11 these
    services run in a dedicated svchost process). Warning output is kept
    to a minimum - locked files are counted and reported as one summary
    line at the end instead of one warning per file.

    The script NEVER restarts the computer. If some files were locked
    and could not be deleted, restart manually and run it once more.

.NOTES
    Author  : Brian Lee (kahao84)
    Version : 1.1 - 2026-10-23 (force-stop services immediately;
              minimized warning output)
    Requires: Windows 10 / 11, Windows PowerShell 5.1+,
              Administrator rights (re-launches itself elevated if needed).

.EXAMPLE
    .\wureset.ps1
    Stop the update services, clear the caches, restart the services.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Self-elevate to Administrator if needed ---------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") -Verb RunAs
    exit
}

$wuServices = @(
    @{ Name = 'wuauserv'; Label = 'Windows Update' }
    @{ Name = 'bits';     Label = 'Background Intelligent Transfer Service' }
    @{ Name = 'cryptsvc'; Label = 'Cryptographic Services' }
)

function Stop-WuService {
    param([string]$Name, [string]$Label)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host "  $Label ($Name) : not present on this system - skipped."
        return
    }
    if ($svc.Status -eq 'Stopped') {
        Write-Host "  $Label ($Name) : already stopped."
        return
    }
    Write-Host "  Stopping $Label ($Name) ..."
    # Send the stop request without waiting: sc.exe returns immediately and
    # does not spam "Waiting for service..." warnings like Stop-Service does.
    & "$env:SystemRoot\System32\sc.exe" stop $Name | Out-Null
    # Short grace period (max ~5 seconds) for a clean stop.
    $svc = Get-Service -Name $Name
    for ($i = 0; $i -lt 5 -and $svc.Status -ne 'Stopped'; $i++) {
        Start-Sleep -Seconds 1
        $svc.Refresh()
    }
    # Still not stopped? Force-kill the service's own process. On Windows
    # 10 / 11 these services run in a dedicated svchost process, so this
    # stops just this service.
    if ($svc.Status -ne 'Stopped') {
        $procId = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue).ProcessId
        if ($procId -and $procId -ne 0) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            for ($i = 0; $i -lt 5 -and $svc.Status -ne 'Stopped'; $i++) {
                Start-Sleep -Seconds 1
                $svc.Refresh()
            }
        }
    }
    if ($svc.Status -ne 'Stopped') {
        Write-Host "    WARNING: $Name could not be stopped (status: $($svc.Status)) - files it holds may stay locked." -ForegroundColor Yellow
    }
}

function Start-WuService {
    param([string]$Name, [string]$Label)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return }
    if ($svc.StartType -eq 'Disabled') {
        Write-Host "  $Label ($Name) startup type is Disabled - setting it back to Manual so it can start."
        Set-Service -Name $Name -StartupType Manual
        $svc = Get-Service -Name $Name
    }
    if ($svc.Status -eq 'Running') {
        Write-Host "  $Label ($Name) : already running."
        return
    }
    Write-Host "  Starting $Label ($Name) ..."
    try {
        Start-Service -Name $Name -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        Write-Host "    Start failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  $Label : folder not found ($Path) - skipped."
        return 0
    }
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        Write-Host "  $Label : already empty."
        return 0
    }
    $removed = 0
    $failed  = 0
    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $removed++
        } catch {
            $failed++   # locked files are counted silently; one summary line at the end
        }
    }
    Write-Host "  $Label : removed $removed item(s) from $Path"
    return $failed
}

# --- Step 1: stop the services -------------------------------------------------
Write-Host '=== Step 1/3: Stopping Windows Update services ==='
foreach ($s in $wuServices) {
    Stop-WuService -Name $s.Name -Label $s.Label
}

# --- Step 2: delete the dead cache files ---------------------------------------
Write-Host ''
Write-Host '=== Step 2/3: Deleting dead cache files ==='
$failedDeletes = 0
$failedDeletes += Clear-FolderContents -Path (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') -Label 'WU download cache'
$failedDeletes += Clear-FolderContents -Path (Join-Path $env:SystemRoot 'System32\catroot2') -Label 'catroot2 (signature catalog cache)'

# BITS queue files (qmgr*.dat)
$downloaderPath = Join-Path $env:ProgramData 'Microsoft\Network\Downloader'
if (Test-Path -LiteralPath $downloaderPath) {
    $qmgrFiles = Get-ChildItem -LiteralPath $downloaderPath -Filter 'qmgr*.dat' -Force -ErrorAction SilentlyContinue
    $qRemoved = 0
    foreach ($file in $qmgrFiles) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $qRemoved++
        } catch {
            $failedDeletes++   # counted silently; summarized at the end
        }
    }
    Write-Host "  BITS queue : removed $qRemoved qmgr file(s) from $downloaderPath"
}

# --- Step 3: restart the services (reverse order) ------------------------------
Write-Host ''
Write-Host '=== Step 3/3: Restarting Windows Update services ==='
foreach ($name in @('cryptsvc', 'bits', 'wuauserv')) {
    $entry = $wuServices | Where-Object { $_.Name -eq $name }
    Start-WuService -Name $entry.Name -Label $entry.Label
}

# --- Summary ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Service status now:'
foreach ($s in $wuServices) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host ("  {0,-10} : (not present)" -f $s.Name)
    } else {
        Write-Host ("  {0,-10} : {1} (StartType: {2})" -f $s.Name, $svc.Status, $svc.StartType)
    }
}

Write-Host ''
if ($failedDeletes -gt 0) {
    Write-Host "$failedDeletes file(s)/folder(s) could not be deleted (still locked)." -ForegroundColor Yellow
    Write-Host 'Restart the computer manually, then run this script once more to finish the cleanup.'
} else {
    Write-Host 'Windows Update cache reset complete.' -ForegroundColor Green
    Write-Host 'Open Settings > Windows Update and check for updates again.'
}
Write-Host 'This script does NOT restart the computer - please restart manually when you are ready.'
