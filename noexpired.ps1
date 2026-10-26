<#
.SYNOPSIS
    Sets "Password never expires" on every enabled local Windows user account.

.DESCRIPTION
    Disables the password-expiry problem for all local user accounts on a
    Windows 10/11 machine:

    - Enumerates every local account in the SAM database via the ADSI WinNT
      provider (works in Windows PowerShell 5.1 and PowerShell 7, no extra
      modules required).
    - Sets the ADS_UF_DONT_EXPIRE_PASSWD flag (0x10000) on each ENABLED
      account, so its password is no longer subject to the Maximum password
      age policy. The per-account flag overrides the policy for that account.
    - Clears the "User must change password at next logon" state
      (PasswordExpired) on each processed account, so users are not forced
      into a one-time password change at their next logon.
    - Disabled accounts are listed as skipped, not modified.
    - Each account is re-read after the change and reported as OK or FAIL,
      so the summary shows the real result per account.

    Scope: LOCAL accounts only. Domain accounts on a domain-joined machine
    are not touched; for those use Set-ADUser -PasswordNeverExpires $true
    from RSAT Active Directory tools instead.

    This script does NOT change the Maximum password age policy itself.
    New accounts created later will still inherit the policy default. To
    also cover future accounts, run (separately, as its own decision):
        net accounts /maxpwage:unlimited

    Security note: disabling password expiry is a deliberate trade-off.
    It suits service accounts, kiosk/shared PCs, and machines where expiry
    prompts break unattended use. Do not run it blindly on machines that
    must comply with a password-rotation policy.

    Requires administrator rights; the script self-elevates when launched
    from a script file. When run via irm | iex it cannot relaunch itself,
    so run it from an elevated PowerShell window in that case.
    No restart is required; changes take effect immediately.

.NOTES
    Author  : Brian Lee (kahao84)
    Version : 1.0 (2026-10-26)
    Run as  : Administrator
    Usage   : .\noexpired.ps1
              irm https://kahao84.github.io/scripts/noexpired.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

# --- Self-elevate -----------------------------------------------------------
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        $engine = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        Start-Process -FilePath $engine `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
        exit 0
    }
    Write-Warning 'Not running as Administrator and no script file to relaunch (e.g. irm | iex). Please re-run from an elevated PowerShell window.'
    exit 1
}

# --- Constants --------------------------------------------------------------
$ADS_UF_ACCOUNTDISABLE     = 0x0002
$ADS_UF_DONT_EXPIRE_PASSWD = 0x10000

# --- Enumerate local accounts ----------------------------------------------
Write-Host "noexpired.ps1 v1.0 - Set 'Password never expires' on all local user accounts"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host ''

try {
    $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
    $accounts = @($computer.Children | Where-Object { $_.SchemaClassName -eq 'user' })
} catch {
    Write-Host "FAILED to enumerate local accounts: $($_.Exception.Message)"
    exit 1
}

if ($accounts.Count -eq 0) {
    Write-Host 'No local user accounts found. Nothing to do.'
    exit 0
}

# --- Process each account ----------------------------------------------------
$okCount      = 0
$failCount    = 0
$skippedCount = 0
$failedNames  = @()

foreach ($account in $accounts) {
    $name = $account.Name
    try {
        $flags = $account.psbase.InvokeGet('UserFlags')

        if ($flags -band $ADS_UF_ACCOUNTDISABLE) {
            Write-Host "[SKIP] $name - account disabled, not modified"
            $skippedCount++
            continue
        }

        $newFlags = $flags -bor $ADS_UF_DONT_EXPIRE_PASSWD
        $account.psbase.InvokeSet('UserFlags', $newFlags)
        $account.psbase.InvokeSet('PasswordExpired', 0)
        $account.SetInfo()

        # Verify by re-reading the account state.
        $checkFlags = $account.psbase.InvokeGet('UserFlags')
        $checkExpired = $account.psbase.InvokeGet('PasswordExpired')
        $neverExpires = ($checkFlags -band $ADS_UF_DONT_EXPIRE_PASSWD) -ne 0
        $mustChangeCleared = ($checkExpired -eq 0 -or $checkExpired -eq $false)

        if ($neverExpires -and $mustChangeCleared) {
            Write-Host "[OK]   $name - password never expires: Yes, must-change-at-logon cleared: Yes"
            $okCount++
        } else {
            Write-Host "[FAIL] $name - verification mismatch (never expires: $neverExpires, must-change cleared: $mustChangeCleared)"
            $failCount++
            $failedNames += $name
        }
    } catch {
        Write-Host "[FAIL] $name - $($_.Exception.Message)"
        $failCount++
        $failedNames += $name
    }
}

# --- Summary -----------------------------------------------------------------
$processedCount = $okCount + $failCount
Write-Host ''
Write-Host "Summary: $($accounts.Count) local account(s) found, $processedCount enabled processed ($okCount OK, $failCount failed), $skippedCount skipped (disabled)."
if ($failCount -gt 0) {
    Write-Host "Failed account(s): $($failedNames -join ', ')"
    Write-Host 'Done with errors. No restart was performed.'
    exit 1
}
Write-Host 'Done. No restart required - changes take effect immediately.'
exit 0
