# Shared backup/reset/restore logic used by both anydesk-reset.ps1 (console)
# and anydesk-reset-gui.ps1 (WinForms). Keeping this in one place means both
# front ends stay in lockstep instead of drifting apart.

$script:ProgramDataDir   = "C:\ProgramData\AnyDesk"
$script:RoamingDir       = Join-Path $env:APPDATA "AnyDesk"
$script:UserConfPath     = Join-Path $script:RoamingDir "user.conf"
$script:ServiceConfPath  = Join-Path $script:ProgramDataDir "service.conf"
$script:SystemConfPath   = Join-Path $script:ProgramDataDir "system.conf"

# Keys that represent "your data" (address book) - safe to restore.
# Note: session auth tokens (ad.anynet.auth_tokens) are NOT restorable - they're
# bound to the old device identity by AnyDesk's relay servers, so a fresh ID
# invalidates them server-side no matter what gets written locally.
$script:AddressKeys       = @('ad.roster.items', 'ad.roster.favorites')
# Any key matching this is treated as a saved password/credential hash - safe to restore
# because password checks are self-contained and not tied to the device identity.
$script:PasswordKeyPattern = 'password|pass_hash|protection_hash'

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AnyDeskPaths {
    [PSCustomObject]@{
        ProgramDataDir  = $script:ProgramDataDir
        RoamingDir      = $script:RoamingDir
        UserConfPath    = $script:UserConfPath
        ServiceConfPath = $script:ServiceConfPath
        SystemConfPath  = $script:SystemConfPath
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

function Stop-AnyDeskProcess {
    param([int]$SettleMilliseconds = 1500)
    $proc = Get-Process -Name AnyDesk -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | Stop-Process -Force
        Start-Sleep -Milliseconds $SettleMilliseconds
        return $true
    }
    return $false
}

function Backup-AnyDeskConfig {
    param([Parameter(Mandatory)][string]$BackupRoot)

    $backup = @{
        UserConf    = Get-ConfHashtable -Path $script:UserConfPath
        ServiceConf = Get-ConfHashtable -Path $script:ServiceConfPath
        SystemConf  = Get-ConfHashtable -Path $script:SystemConfPath
    }

    $found = @()
    if ($backup.UserConf['ad.roster.items'] -and $backup.UserConf['ad.roster.items'] -notmatch '^,*$') {
        $found += "address book"
    }
    $pwKeys = @($backup.ServiceConf.Keys) + @($backup.SystemConf.Keys) | Where-Object { $_ -match $script:PasswordKeyPattern }
    if ($pwKeys) { $found += "unattended-access password" }

    $backupDir = Join-Path $BackupRoot (Get-Date -Format 'yyyy-MM-dd_HHmmss')
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $backupDir 'backup.json') -Encoding UTF8

    [PSCustomObject]@{
        BackupDir = $backupDir
        Backup    = $backup
        Found     = $found
    }
}

function Remove-AnyDeskConfig {
    $removed = @()
    if (Test-Path $script:ProgramDataDir) {
        Remove-Item $script:ProgramDataDir -Recurse -Force
        $removed += $script:ProgramDataDir
    }
    if (Test-Path $script:RoamingDir) {
        Remove-Item $script:RoamingDir -Recurse -Force
        $removed += $script:RoamingDir
    }
    return $removed
}

function Start-AnyDeskAndWaitForId {
    param(
        [Parameter(Mandatory)][string]$AnyDeskExe,
        [int]$TimeoutSeconds = 25,
        [scriptblock]$OnTick
    )

    Start-Process $AnyDeskExe

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ready = $false
    $id = $null
    while ((Get-Date) -lt $deadline) {
        if ($OnTick) { & $OnTick }
        Start-Sleep -Milliseconds 250
        if ((Test-Path $script:UserConfPath) -and (Test-Path $script:SystemConfPath)) {
            $sysConf = Get-ConfHashtable -Path $script:SystemConfPath
            if ($sysConf['ad.anynet.id']) { $ready = $true; $id = $sysConf['ad.anynet.id']; break }
        }
    }

    Stop-AnyDeskProcess | Out-Null

    [PSCustomObject]@{ Ready = $ready; Id = $id }
}

function Restore-AnyDeskConfig {
    param([Parameter(Mandatory)][hashtable]$Backup)

    $restored = @()

    if (Test-Path $script:UserConfPath) {
        $values = @{}
        foreach ($key in $script:AddressKeys) {
            if ($Backup.UserConf.ContainsKey($key)) { $values[$key] = $Backup.UserConf[$key] }
        }
        if ($values.Count -gt 0) {
            Set-ConfValues -Path $script:UserConfPath -Values $values
            $restored += "address book"
        }
    }

    # Only restore keys that look like password/credential hashes - never identity fields
    # (ad.anynet.cert / pkey / id / fpr, ad.inst.id, license data) which must stay fresh.
    $pwValues = @{}
    foreach ($src in @($Backup.ServiceConf, $Backup.SystemConf)) {
        foreach ($key in $src.Keys) {
            if ($key -match $script:PasswordKeyPattern) { $pwValues[$key] = $src[$key] }
        }
    }
    if ($pwValues.Count -gt 0) {
        if (Test-Path $script:ServiceConfPath) { Set-ConfValues -Path $script:ServiceConfPath -Values $pwValues }
        if (Test-Path $script:SystemConfPath)  { Set-ConfValues -Path $script:SystemConfPath -Values $pwValues }
        $restored += "unattended-access password"
    }

    return $restored
}

function ConvertTo-BackupHashtable {
    param($Section)
    $ht = @{}
    if ($Section) {
        $Section.psobject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    return $ht
}

function Import-AnyDeskBackup {
    param([Parameter(Mandatory)][string]$Path)
    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    @{
        UserConf    = ConvertTo-BackupHashtable $json.UserConf
        ServiceConf = ConvertTo-BackupHashtable $json.ServiceConf
        SystemConf  = ConvertTo-BackupHashtable $json.SystemConf
    }
}

function Get-AnyDeskBackups {
    param([Parameter(Mandatory)][string]$BackupRoot)
    if (-not (Test-Path $BackupRoot)) { return @() }
    Get-ChildItem -Path $BackupRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'backup.json') } |
        Sort-Object Name -Descending
}

Export-ModuleMember -Function * -Variable @()
