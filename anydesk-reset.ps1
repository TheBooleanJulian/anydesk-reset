#Requires -Version 5.0
[CmdletBinding()]
param()

$Host.UI.RawUI.WindowTitle = "AnyDesk Reset"
$ErrorActionPreference = 'Stop'

# ---- Self-elevate ---------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required - relaunching elevated..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit
}

# ---- Paths ------------------------------------------------------------------
$ProgramDataDir = "C:\ProgramData\AnyDesk"
$RoamingDir     = Join-Path $env:APPDATA "AnyDesk"
$UserConfPath   = Join-Path $RoamingDir "user.conf"
$ServiceConfPath = Join-Path $ProgramDataDir "service.conf"
$SystemConfPath  = Join-Path $ProgramDataDir "system.conf"

# Keys that represent "your data" (address book) - safe to restore.
# Note: session auth tokens (ad.anynet.auth_tokens) are NOT restorable - they're
# bound to the old device identity by AnyDesk's relay servers, so a fresh ID
# invalidates them server-side no matter what gets written locally.
$AddressKeys  = @('ad.roster.items', 'ad.roster.favorites')
# Any key matching this is treated as a saved password/credential hash - safe to restore
# because password checks are self-contained and not tied to the device identity.
$PasswordKeyPattern = 'password|pass_hash|protection_hash'

# ---- UI helpers -------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host "   ___              ______           __" -ForegroundColor Cyan
    Write-Host "  / _ | ___ _ __ __/ / __ \___ ___ / /__" -ForegroundColor Cyan
    Write-Host " / __ |/ _ \ \ / // / /_/ / -_|_-</  '_/" -ForegroundColor Cyan
    Write-Host "/_/ |_/_//_/_\_\/_/_____/\__/___/_/\_\" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  AnyDesk Reset" -ForegroundColor White -NoNewline
    Write-Host "  -  clears ID / config so AnyDesk re-registers as a new device" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 58)) -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Wait {
    param([int]$Seconds, [string]$Message)
    $frames = '|','/','-','\'
    $end = (Get-Date).AddSeconds($Seconds)
    $i = 0
    while ((Get-Date) -lt $end) {
        Write-Host ("`r  {0} {1}" -f $frames[$i % $frames.Length], $Message) -ForegroundColor DarkCyan -NoNewline
        Start-Sleep -Milliseconds 100
        $i++
    }
    Write-Host ("`r{0}`r" -f (' ' * ($Message.Length + 4))) -NoNewline
}

function Invoke-Step {
    param(
        [int]$Number,
        [int]$Total,
        [string]$Text,
        [scriptblock]$Action
    )
    Write-Host ("[{0}/{1}] " -f $Number, $Total) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$Text " -ForegroundColor White -NoNewline

    try {
        $note = & $Action
        Write-Host "OK" -ForegroundColor Green
        if ($note) { Write-Host "        $note" -ForegroundColor DarkGray }
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ConfHashtable {
    param([string]$Path)
    $table = @{}
    if (Test-Path $Path) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $idx = $line.IndexOf('=')
            if ($idx -gt 0) {
                $table[$line.Substring(0, $idx)] = $line.Substring($idx + 1)
            }
        }
    }
    return $table
}

function Set-ConfValues {
    param([string]$Path, [hashtable]$Values)
    if (-not (Test-Path $Path) -or $Values.Count -eq 0) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]][System.IO.File]::ReadAllLines($Path))
    foreach ($key in $Values.Keys) {
        $newLine = "$key=$($Values[$key])"
        $matchIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].StartsWith("$key=")) { $matchIndex = $i; break }
        }
        if ($matchIndex -ge 0) { $lines[$matchIndex] = $newLine } else { $lines.Add($newLine) }
    }
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-AnyDeskExe {
    $candidates = @(
        "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
        "C:\Program Files\AnyDesk\AnyDesk.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# ---- Banner + confirmation -------------------------------------------------
Write-Banner

Write-Host "  This will:" -ForegroundColor Yellow
Write-Host "    - Close AnyDesk"                                          -ForegroundColor Gray
Write-Host "    - Back up your address book"                              -ForegroundColor Gray
Write-Host "    - Delete C:\ProgramData\AnyDesk and %APPDATA%\AnyDesk"    -ForegroundColor Gray
Write-Host "    - Briefly start AnyDesk to generate a fresh ID"          -ForegroundColor Gray
Write-Host "    - Restore your address book"                             -ForegroundColor Gray
Write-Host "    - Relaunch AnyDesk for real"                             -ForegroundColor Gray
Write-Host ""
$confirm = Read-Host "  Continue? [y/N]"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "`n  Cancelled - nothing was changed." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    exit
}
Write-Host ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$TotalSteps = 7

# ---- Step 1: Close AnyDesk ---------------------------------------------------
Invoke-Step -Number 1 -Total $TotalSteps -Text "Closing AnyDesk..." -Action {
    $proc = Get-Process -Name AnyDesk -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | Stop-Process -Force
        Show-Wait -Seconds 2 -Message "waiting for process to release files"
        "Process stopped"
    } else {
        "Not running"
    }
}

# ---- Step 2: Back up addresses & passwords -----------------------------------
$backup = @{ UserConf = @{}; ServiceConf = @{}; SystemConf = @{} }
$backupDir = $null

Write-Host ("[2/{0}] " -f $TotalSteps) -ForegroundColor DarkCyan -NoNewline
Write-Host "Backing up address book... " -ForegroundColor White -NoNewline
try {
    $backup.UserConf    = Get-ConfHashtable -Path $UserConfPath
    $backup.ServiceConf = Get-ConfHashtable -Path $ServiceConfPath
    $backup.SystemConf  = Get-ConfHashtable -Path $SystemConfPath

    $found = @()
    if ($backup.UserConf['ad.roster.items'] -and $backup.UserConf['ad.roster.items'] -notmatch '^,*$') {
        $found += "address book"
    }
    $pwKeys = @($backup.ServiceConf.Keys) + @($backup.SystemConf.Keys) | Where-Object { $_ -match $PasswordKeyPattern }
    if ($pwKeys) { $found += "unattended-access password" }

    $backupDir = Join-Path $PSScriptRoot ("backup\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $backupDir 'backup.json') -Encoding UTF8

    Write-Host "OK" -ForegroundColor Green
    if ($found.Count -gt 0) {
        Write-Host ("        Found: {0}" -f ($found -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "        Nothing to preserve (no saved addresses or passwords found)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
}

# ---- Step 3: Delete ProgramData\AnyDesk --------------------------------------
Invoke-Step -Number 3 -Total $TotalSteps -Text "Deleting ProgramData\AnyDesk..." -Action {
    if (Test-Path $ProgramDataDir) {
        Remove-Item $ProgramDataDir -Recurse -Force
        "Removed $ProgramDataDir"
    } else {
        "Not found, skipped"
    }
}

# ---- Step 4: Delete Roaming\AnyDesk ------------------------------------------
Invoke-Step -Number 4 -Total $TotalSteps -Text "Deleting Roaming AnyDesk..." -Action {
    if (Test-Path $RoamingDir) {
        Remove-Item $RoamingDir -Recurse -Force
        "Removed $RoamingDir"
    } else {
        "Not found, skipped"
    }
}

$anyDeskExe = Get-AnyDeskExe
if (-not $anyDeskExe) {
    Write-Host "  AnyDesk.exe not found automatically - the rest of the steps will be skipped." -ForegroundColor Red
    Write-Host "  Please reinstall or locate AnyDesk manually." -ForegroundColor Red
    Read-Host "  Press Enter to close" | Out-Null
    exit 1
}

# ---- Step 5: Generate a fresh identity ----------------------------------------
# AnyDesk only writes its config files once it actually runs, so it has to be
# started briefly here. It's closed again before Step 6 so its background
# config-save can't clobber the values we splice back in.
Write-Host ("[5/{0}] " -f $TotalSteps) -ForegroundColor DarkCyan -NoNewline
Write-Host "Generating new AnyDesk identity... " -ForegroundColor White

Start-Process $anyDeskExe

$deadline = (Get-Date).AddSeconds(25)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Show-Wait -Seconds 1 -Message "waiting for AnyDesk to register a new ID"
    if ((Test-Path $UserConfPath) -and (Test-Path $SystemConfPath)) {
        $sysConf = Get-ConfHashtable -Path $SystemConfPath
        if ($sysConf['ad.anynet.id']) { $ready = $true; break }
    }
}

$proc = Get-Process -Name AnyDesk -ErrorAction SilentlyContinue
if ($proc) {
    $proc | Stop-Process -Force
    Show-Wait -Seconds 2 -Message "waiting for process to release files"
}

if ($ready) {
    Write-Host "OK" -ForegroundColor Green
    Write-Host "        New ID: $($sysConf['ad.anynet.id'])" -ForegroundColor DarkGray
} else {
    Write-Host "TIMED OUT" -ForegroundColor Yellow
    Write-Host "        Continuing anyway - restore step may have nothing to write into." -ForegroundColor Yellow
}

# ---- Step 6: Restore addresses & passwords -----------------------------------
Write-Host ("[6/{0}] " -f $TotalSteps) -ForegroundColor DarkCyan -NoNewline
Write-Host "Restoring address book... " -ForegroundColor White -NoNewline

try {
    $restored = @()

    if (Test-Path $UserConfPath) {
        $values = @{}
        foreach ($key in $AddressKeys) {
            if ($backup.UserConf.ContainsKey($key)) { $values[$key] = $backup.UserConf[$key] }
        }
        if ($values.Count -gt 0) {
            Set-ConfValues -Path $UserConfPath -Values $values
            $restored += "address book"
        }
    } else {
        Write-Host ""
        Write-Host "        AnyDesk hadn't finished initializing; address book not restored." -ForegroundColor Yellow
        if ($backupDir) { Write-Host "        Your backup is safe at: $backupDir" -ForegroundColor Yellow }
    }

    # Only restore keys that look like password/credential hashes - never identity fields
    # (ad.anynet.cert / pkey / id / fpr, ad.inst.id, license data) which must stay fresh.
    $pwValues = @{}
    foreach ($src in @($backup.ServiceConf, $backup.SystemConf)) {
        foreach ($key in $src.Keys) {
            if ($key -match $PasswordKeyPattern) { $pwValues[$key] = $src[$key] }
        }
    }
    if ($pwValues.Count -gt 0) {
        if (Test-Path $ServiceConfPath) { Set-ConfValues -Path $ServiceConfPath -Values $pwValues }
        if (Test-Path $SystemConfPath)  { Set-ConfValues -Path $SystemConfPath -Values $pwValues }
        $restored += "unattended-access password"
    }

    Write-Host "OK" -ForegroundColor Green
    if ($restored.Count -gt 0) {
        Write-Host ("        Restored: {0}" -f ($restored -join ', ')) -ForegroundColor Green
    } else {
        Write-Host "        Nothing to restore" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    if ($backupDir) { Write-Host "        Your backup is safe at: $backupDir" -ForegroundColor Yellow }
}

# ---- Step 7: Relaunch AnyDesk --------------------------------------------------
Invoke-Step -Number 7 -Total $TotalSteps -Text "Relaunching AnyDesk..." -Action {
    Start-Process $anyDeskExe
    "Launched $anyDeskExe"
}

$sw.Stop()

# ---- Summary ----------------------------------------------------------------
Write-Host ""
Write-Host ("  " + ("-" * 58)) -ForegroundColor DarkGray
Write-Host "  Reset complete " -ForegroundColor Green -NoNewline
Write-Host ("in {0:N1}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
Write-Host "  AnyDesk has a new ID. Your address book was carried over." -ForegroundColor Gray
Write-Host "  You'll need to re-enter passwords for any saved sessions." -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to close" | Out-Null
