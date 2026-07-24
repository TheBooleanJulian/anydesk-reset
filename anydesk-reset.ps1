#Requires -Version 5.0
[CmdletBinding()]
param()

$Host.UI.RawUI.WindowTitle = "AnyDesk Reset"
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AnyDeskReset.Core.psm1') -Force

# ---- Self-elevate ---------------------------------------------------------
if (-not (Test-IsAdmin)) {
    Write-Host "Administrator rights required - relaunching elevated..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit
}

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
    if (Stop-AnyDeskProcess -SettleMilliseconds 0) {
        Show-Wait -Seconds 2 -Message "waiting for process to release files"
        "Process stopped"
    } else {
        "Not running"
    }
}

# ---- Step 2: Back up addresses & passwords -----------------------------------
$backupResult = $null

Write-Host ("[2/{0}] " -f $TotalSteps) -ForegroundColor DarkCyan -NoNewline
Write-Host "Backing up address book... " -ForegroundColor White -NoNewline
try {
    $backupResult = Backup-AnyDeskConfig -BackupRoot (Join-Path $PSScriptRoot 'backup')

    Write-Host "OK" -ForegroundColor Green
    if ($backupResult.Found.Count -gt 0) {
        Write-Host ("        Found: {0}" -f ($backupResult.Found -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "        Nothing to preserve (no saved addresses or passwords found)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
}
$backup = $backupResult.Backup
$backupDir = $backupResult.BackupDir
$paths = Get-AnyDeskPaths

# ---- Step 3+4: Delete ProgramData\AnyDesk and Roaming\AnyDesk ----------------
Invoke-Step -Number 3 -Total $TotalSteps -Text "Deleting ProgramData\AnyDesk..." -Action {
    if (Test-Path $paths.ProgramDataDir) {
        Remove-Item $paths.ProgramDataDir -Recurse -Force
        "Removed $($paths.ProgramDataDir)"
    } else {
        "Not found, skipped"
    }
}

Invoke-Step -Number 4 -Total $TotalSteps -Text "Deleting Roaming AnyDesk..." -Action {
    if (Test-Path $paths.RoamingDir) {
        Remove-Item $paths.RoamingDir -Recurse -Force
        "Removed $($paths.RoamingDir)"
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

$idResult = Start-AnyDeskAndWaitForId -AnyDeskExe $anyDeskExe -TimeoutSeconds 25 -OnTick {
    Show-Wait -Seconds 1 -Message "waiting for AnyDesk to register a new ID"
}

if ($idResult.Ready) {
    Write-Host "OK" -ForegroundColor Green
    Write-Host "        New ID: $($idResult.Id)" -ForegroundColor DarkGray
} else {
    Write-Host "TIMED OUT" -ForegroundColor Yellow
    Write-Host "        Continuing anyway - restore step may have nothing to write into." -ForegroundColor Yellow
}

# ---- Step 6: Restore addresses & passwords -----------------------------------
Write-Host ("[6/{0}] " -f $TotalSteps) -ForegroundColor DarkCyan -NoNewline
Write-Host "Restoring address book... " -ForegroundColor White -NoNewline

try {
    if (-not (Test-Path $paths.UserConfPath)) {
        Write-Host ""
        Write-Host "        AnyDesk hadn't finished initializing; address book not restored." -ForegroundColor Yellow
        if ($backupDir) { Write-Host "        Your backup is safe at: $backupDir" -ForegroundColor Yellow }
    } else {
        $restored = Restore-AnyDeskConfig -Backup $backup
        Write-Host "OK" -ForegroundColor Green
        if ($restored.Count -gt 0) {
            Write-Host ("        Restored: {0}" -f ($restored -join ', ')) -ForegroundColor Green
        } else {
            Write-Host "        Nothing to restore" -ForegroundColor DarkGray
        }
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
