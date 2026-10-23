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
           plus two services that often hold the cache files open:
             TrustedInstaller - Windows Modules Installer
             UsoSvc           - Update Orchestrator Service

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

    If a file or folder STILL cannot be deleted (locked by a protected
    service or a stubborn handle), the script escalates: it takes
    ownership of the item and grants Administrators full control, then
    retries the delete. If it still survives, it is queued for deletion
    at the next reboot (PendingFileRenameOperations - registered via
    MoveFileEx, with a direct registry write as fallback): Windows
    deletes it early in the boot process, before the update services
    start, so it cannot be locked again. If even the registration
    fails, the real Win32 error code is printed once so the cause can
    be diagnosed instead of guessed. The summary at the end tells you
    when a reboot is needed to finish the cleanup.

    The script NEVER restarts the computer. If files were queued for
    deletion at the next reboot, restart manually once - no need to run
    the script again afterwards.

.NOTES
    Author  : Brian Lee (kahao84)
    Version : 1.3 - 2026-10-24 (deletion escalates: take ownership and
              retry, then queue for deletion at next reboot via API or
              direct registry write; first failure prints the Win32
              error code)
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

# Not part of Windows Update itself, but they often hold the cache files
# open - stopped for the cleanup, started again afterwards.
$holderServices = @(
    @{ Name = 'TrustedInstaller'; Label = 'Windows Modules Installer' }
    @{ Name = 'UsoSvc';           Label = 'Update Orchestrator Service' }
)

# --- Delete-on-reboot support (PendingFileRenameOperations) -------------------
if (-not ([System.Management.Automation.PSTypeName]'Win32.MoveFile').Type) {
    Add-Type -Namespace Win32 -Name MoveFile -MemberDefinition @'
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
}

$queueErrorShown = $false

function Add-PendingDeletePair {
    # Fallback registration: append the (source, "") pair directly to the
    # PendingFileRenameOperations registry value, in NT path form.
    param([string]$Path)
    try {
        $smKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $existing = (Get-ItemProperty -Path $smKey -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
        $pairs = @()
        if ($existing) { $pairs += $existing }
        $pairs += ("\??\" + $Path)
        $pairs += ''
        Set-ItemProperty -Path $smKey -Name 'PendingFileRenameOperations' -Value $pairs -Type MultiString -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Register-DeleteOnReboot {
    param([string]$Path)
    $queued = 0
    if (Test-Path -LiteralPath $Path -PathType Container) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
            $queued += Register-DeleteOnReboot -Path $child.FullName
        }
    }
    # MOVEFILE_DELAY_UNTIL_REBOOT = 4; a null new name means "delete".
    if ([Win32.MoveFile]::MoveFileEx($Path, $null, 4)) {
        $queued++
    } else {
        $win32err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if (Add-PendingDeletePair -Path $Path) {
            $queued++
        } elseif (-not $script:queueErrorShown) {
            $script:queueErrorShown = $true
            Write-Host "    Note: queuing '$Path' for deletion at reboot failed (MoveFileEx Win32 error $win32err)." -ForegroundColor Yellow
        }
    }
    return $queued
}

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
    $result = [PSCustomObject]@{ Removed = 0; Queued = 0; Failed = 0 }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  $Label : folder not found ($Path) - skipped."
        return $result
    }
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        Write-Host "  $Label : already empty."
        return $result
    }
    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $result.Removed++
        } catch {
            # Escalate: take ownership + grant Administrators full control,
            # then retry the delete once.
            $deleted = $false
            try {
                & "$env:SystemRoot\System32\takeown.exe" /F $item.FullName /R /D Y | Out-Null
                & "$env:SystemRoot\System32\icacls.exe" $item.FullName /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $result.Removed++
                $deleted = $true
            } catch { }
            if (-not $deleted) {
                # Last resort: queue it for deletion at the next reboot,
                # when Windows removes it before the services can start.
                $q = Register-DeleteOnReboot -Path $item.FullName
                if ($q -gt 0) { $result.Queued++ } else { $result.Failed++ }
            }
        }
    }
    $line = "  $Label : removed $($result.Removed) item(s) from $Path"
    if ($result.Queued -gt 0) { $line += " ; $($result.Queued) item(s) queued for deletion at next reboot" }
    if ($result.Failed -gt 0) { $line += " ; $($result.Failed) item(s) FAILED" }
    Write-Host $line
    return $result
}

# --- Step 1: stop the services -------------------------------------------------
Write-Host '=== Step 1/3: Stopping Windows Update services ==='
foreach ($s in ($wuServices + $holderServices)) {
    Stop-WuService -Name $s.Name -Label $s.Label
}

# --- Step 2: delete the dead cache files ---------------------------------------
Write-Host ''
Write-Host '=== Step 2/3: Deleting dead cache files ==='
$removedTotal = 0
$queuedTotal  = 0
$failedTotal  = 0
$r = Clear-FolderContents -Path (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') -Label 'WU download cache'
$removedTotal += $r.Removed; $queuedTotal += $r.Queued; $failedTotal += $r.Failed
$r = Clear-FolderContents -Path (Join-Path $env:SystemRoot 'System32\catroot2') -Label 'catroot2 (signature catalog cache)'
$removedTotal += $r.Removed; $queuedTotal += $r.Queued; $failedTotal += $r.Failed

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
            $q = Register-DeleteOnReboot -Path $file.FullName
            if ($q -gt 0) { $queuedTotal++ } else { $failedTotal++ }
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
foreach ($s in $holderServices) {
    Start-WuService -Name $s.Name -Label $s.Label
}

# --- Summary ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Service status now:'
foreach ($s in ($wuServices + $holderServices)) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host ("  {0,-10} : (not present)" -f $s.Name)
    } else {
        Write-Host ("  {0,-10} : {1} (StartType: {2})" -f $s.Name, $svc.Status, $svc.StartType)
    }
}

Write-Host ''
if ($queuedTotal -gt 0) {
    Write-Host "$queuedTotal item(s) were still locked and are now queued for deletion at the next reboot." -ForegroundColor Yellow
    Write-Host 'Restart the computer once: Windows deletes them early in the boot process, before the'
    Write-Host 'update services start, so they cannot be locked again. After the restart, just open'
    Write-Host 'Settings > Windows Update and check for updates - the caches rebuild themselves clean.'
}
if ($failedTotal -gt 0) {
    Write-Host "$failedTotal item(s) could not be deleted or queued - check the service status above." -ForegroundColor Red
}
if ($queuedTotal -eq 0 -and $failedTotal -eq 0) {
    Write-Host 'Windows Update cache reset complete.' -ForegroundColor Green
    Write-Host 'Open Settings > Windows Update and check for updates again.'
}
Write-Host 'This script does NOT restart the computer - please restart manually when you are ready.'
