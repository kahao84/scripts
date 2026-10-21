<#
.SYNOPSIS
    Enable SMB 1.0/CIFS Client and Server (Windows 10 / 11) - WITHOUT the
    SMB1 Automatic Removal feature.

.DESCRIPTION
    Since Windows 10 version 1709 / Windows 11, SMBv1 is no longer installed
    by default. The optional feature "SMB 1.0/CIFS File Sharing Support"
    consists of three sub-features:

        SMB1Protocol-Client       - SMB 1.0/CIFS Client
        SMB1Protocol-Server       - SMB 1.0/CIFS Server
        SMB1Protocol-Deprecation  - SMB 1.0/CIFS Automatic Removal
                                    (auto-uninstalls SMB1 after ~15 days
                                     of non-use)

    This script enables the Client and the Server, and explicitly makes sure
    the Automatic Removal feature (SMB1Protocol-Deprecation) is DISABLED, so
    Windows will not silently uninstall SMB1 again later.

    The script NEVER restarts the computer. If a restart is required to
    complete the installation, it says so - restart manually when ready.

.PARAMETER Disable
    Reverse the change: disable the SMB1 Client and Server features again.
    (Automatic Removal is left as-is.)

.NOTES
    Author  : Brian Lee (kahao84)
    Version : 1.0 - 2026-10-21
    Requires: Windows 10 / 11, Windows PowerShell 5.1+,
              Administrator rights (re-launches itself elevated if needed).
    Warning : SMBv1 is a legacy, insecure protocol (deprecated by Microsoft
              since 2014). Enable it only for legacy devices that cannot
              use SMB2/SMB3, and only on trusted networks.

.EXAMPLE
    .\smbv1.ps1
    Enable SMB1 Client + Server, without Automatic Removal.

.EXAMPLE
    .\smbv1.ps1 -Disable
    Disable SMB1 Client + Server again.
#>
[CmdletBinding()]
param(
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'

# --- Self-elevate to Administrator if needed ---------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Disable) { $argList += '-Disable' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
}

$clientFeature      = 'SMB1Protocol-Client'
$serverFeature      = 'SMB1Protocol-Server'
$deprecationFeature = 'SMB1Protocol-Deprecation'   # = "SMB 1.0/CIFS Automatic Removal"

function Get-FeatureState {
    param([string]$Name)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        if ($null -ne $f) { return $f.State }
    } catch { }
    return $null   # feature not present on this Windows build/edition
}

function Show-Smb1Status {
    Write-Host ''
    Write-Host 'Current SMB1 feature states:'
    foreach ($name in @('SMB1Protocol', $clientFeature, $serverFeature, $deprecationFeature)) {
        $state = Get-FeatureState -Name $name
        if ($null -eq $state) { $state = '(not present on this system)' }
        Write-Host ("  {0,-26} : {1}" -f $name, $state)
    }
}

# --- Check the features exist at all ------------------------------------------
if ($null -eq (Get-FeatureState -Name $clientFeature)) {
    Write-Host 'SMB1 optional features were not found on this system.' -ForegroundColor Red
    Write-Host 'On some newer Windows builds/editions the SMB1 payload has been removed completely,'
    Write-Host 'in which case it cannot be enabled by script.'
    return
}

$restartNeeded = $false

if ($Disable) {
    # --- Disable Client + Server ------------------------------------------------
    foreach ($name in @($clientFeature, $serverFeature)) {
        if ((Get-FeatureState -Name $name) -ne 'Disabled') {
            Write-Host "Disabling $name ..."
            $r = Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart
            if ($r.RestartNeeded) { $restartNeeded = $true }
        } else {
            Write-Host "$name is already disabled."
        }
    }
    Write-Host ''
    Write-Host 'SMB1 Client and Server disabled.' -ForegroundColor Green
}
else {
    # --- Enable Client + Server ---------------------------------------------------
    foreach ($name in @($clientFeature, $serverFeature)) {
        $state = Get-FeatureState -Name $name
        if ($state -eq 'Enabled') {
            Write-Host "$name is already enabled."
        } else {
            Write-Host "Enabling $name ..."
            $r = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart
            if ($r.RestartNeeded) { $restartNeeded = $true }
        }
    }

    # --- Make sure Automatic Removal stays OFF -------------------------------------
    # Enabling the SMB1Protocol parent can pull this in on some builds, so set it
    # explicitly: if it is on, turn it off - otherwise SMB1 would uninstall itself
    # again after about 15 days without use.
    $depState = Get-FeatureState -Name $deprecationFeature
    if ($null -eq $depState) {
        Write-Host "$deprecationFeature (Automatic Removal) is not present on this system - nothing to do."
    } elseif ($depState -eq 'Disabled') {
        Write-Host "$deprecationFeature (Automatic Removal) is already disabled - good."
    } else {
        Write-Host "Disabling $deprecationFeature (Automatic Removal) ..."
        $r = Disable-WindowsOptionalFeature -Online -FeatureName $deprecationFeature -NoRestart
        if ($r.RestartNeeded) { $restartNeeded = $true }
    }

    Write-Host ''
    Write-Host 'SMB1 Client and Server enabled (Automatic Removal NOT enabled).' -ForegroundColor Green
}

Show-Smb1Status

# --- Restart note (never automatic) ----------------------------------------------
Write-Host ''
if ($restartNeeded) {
    Write-Host 'A restart is required to complete the change.' -ForegroundColor Yellow
}
Write-Host 'This script does NOT restart the computer - please restart manually when you are ready.'
