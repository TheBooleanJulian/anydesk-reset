#Requires -Version 5.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AnyDeskReset.Core.psm1') -Force

# ---- Self-elevate (relaunched hidden so only the GUI window is visible) -----
if (-not (Test-IsAdmin)) {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`""
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$BackupRoot = Join-Path $PSScriptRoot 'backup'

# ---- Theme ------------------------------------------------------------------
$colorBg     = [System.Drawing.Color]::FromArgb(24, 26, 27)
$colorPanel  = [System.Drawing.Color]::FromArgb(32, 34, 36)
$colorText   = [System.Drawing.Color]::FromArgb(225, 225, 225)
$colorMuted  = [System.Drawing.Color]::FromArgb(150, 150, 150)
$colorAccent = [System.Drawing.Color]::FromArgb(0, 212, 200)
$colorOk     = [System.Drawing.Color]::FromArgb(90, 200, 130)
$colorWarn   = [System.Drawing.Color]::FromArgb(230, 190, 80)
$colorErr    = [System.Drawing.Color]::FromArgb(230, 90, 90)
$fontUi      = New-Object System.Drawing.Font('Segoe UI', 9)
$fontMono    = New-Object System.Drawing.Font('Consolas', 9)

# ---- Form ---------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "AnyDesk Reset"
$form.Size = New-Object System.Drawing.Size(560, 460)
$form.MinimumSize = New-Object System.Drawing.Size(480, 380)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $colorBg
$form.Font = $fontUi

$title = New-Object System.Windows.Forms.Label
$title.Text = "AnyDesk Reset"
$title.ForeColor = $colorText
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(16, 14)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Clears the local ID/config so AnyDesk re-registers as a new device."
$subtitle.ForeColor = $colorMuted
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(18, 44)
$form.Controls.Add($subtitle)

# ---- Backup picker row -------------------------------------------------------
$lblBackup = New-Object System.Windows.Forms.Label
$lblBackup.Text = "Restore from:"
$lblBackup.ForeColor = $colorText
$lblBackup.AutoSize = $true
$lblBackup.Location = New-Object System.Drawing.Point(18, 76)
$form.Controls.Add($lblBackup)

$cmbBackups = New-Object System.Windows.Forms.ComboBox
$cmbBackups.DropDownStyle = 'DropDownList'
$cmbBackups.Location = New-Object System.Drawing.Point(100, 72)
$cmbBackups.Width = 320
$cmbBackups.Anchor = 'Top,Left,Right'
$form.Controls.Add($cmbBackups)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(428, 71)
$btnRefresh.Width = 100
$btnRefresh.Anchor = 'Top,Right'
$btnRefresh.FlatStyle = 'Flat'
$form.Controls.Add($btnRefresh)

function Update-BackupList {
    $cmbBackups.Items.Clear()
    $backups = Get-AnyDeskBackups -BackupRoot $BackupRoot
    foreach ($b in $backups) { $cmbBackups.Items.Add($b.Name) | Out-Null }
    if ($cmbBackups.Items.Count -gt 0) { $cmbBackups.SelectedIndex = 0 }
}

# ---- Log box ------------------------------------------------------------------
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(18, 108)
$logBox.Size = New-Object System.Drawing.Size(510, 240)
$logBox.Anchor = 'Top,Bottom,Left,Right'
$logBox.BackColor = $colorPanel
$logBox.ForeColor = $colorText
$logBox.Font = $fontMono
$logBox.ReadOnly = $true
$logBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($logBox)

function Write-Log {
    param([string]$Text, [System.Drawing.Color]$Color = $colorText)
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionLength = 0
    $logBox.SelectionColor = $Color
    $logBox.AppendText("$Text`r`n")
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ---- Buttons ------------------------------------------------------------------
$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Full Reset"
$btnReset.Location = New-Object System.Drawing.Point(18, 362)
$btnReset.Size = New-Object System.Drawing.Size(150, 34)
$btnReset.Anchor = 'Bottom,Left'
$btnReset.FlatStyle = 'Flat'
$btnReset.BackColor = $colorAccent
$btnReset.ForeColor = [System.Drawing.Color]::Black
$form.Controls.Add($btnReset)

$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Backup Only"
$btnBackup.Location = New-Object System.Drawing.Point(178, 362)
$btnBackup.Size = New-Object System.Drawing.Size(150, 34)
$btnBackup.Anchor = 'Bottom,Left'
$btnBackup.FlatStyle = 'Flat'
$form.Controls.Add($btnBackup)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore Selected"
$btnRestore.Location = New-Object System.Drawing.Point(338, 362)
$btnRestore.Size = New-Object System.Drawing.Size(190, 34)
$btnRestore.Anchor = 'Bottom,Right'
$btnRestore.FlatStyle = 'Flat'
$form.Controls.Add($btnRestore)

$allButtons = @($btnReset, $btnBackup, $btnRestore, $btnRefresh, $cmbBackups)
function Set-ButtonsEnabled([bool]$Enabled) {
    foreach ($b in $allButtons) { $b.Enabled = $Enabled }
}

# ---- Actions --------------------------------------------------------------------
$btnBackup.Add_Click({
    Set-ButtonsEnabled $false
    try {
        Write-Log "Backing up address book and unattended-access password..." $colorText
        $result = Backup-AnyDeskConfig -BackupRoot $BackupRoot
        if ($result.Found.Count -gt 0) {
            Write-Log "Found: $($result.Found -join ', ')" $colorOk
        } else {
            Write-Log "Nothing to preserve (no saved addresses or passwords found)" $colorMuted
        }
        Write-Log "Saved to: $($result.BackupDir)" $colorMuted
        Update-BackupList
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)" $colorErr
    } finally {
        Set-ButtonsEnabled $true
    }
})

$btnRestore.Add_Click({
    if ($cmbBackups.SelectedItem -eq $null) {
        Write-Log "No backup selected." $colorWarn
        return
    }
    Set-ButtonsEnabled $false
    try {
        $backupJson = Join-Path (Join-Path $BackupRoot $cmbBackups.SelectedItem) 'backup.json'
        Write-Log "Restoring from $($cmbBackups.SelectedItem)..." $colorText
        Stop-AnyDeskProcess | Out-Null
        $backup = Import-AnyDeskBackup -Path $backupJson
        $restored = Restore-AnyDeskConfig -Backup $backup
        if ($restored.Count -gt 0) {
            Write-Log "Restored: $($restored -join ', ')" $colorOk
        } else {
            Write-Log "Nothing to restore from that backup" $colorMuted
        }
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)" $colorErr
    } finally {
        Set-ButtonsEnabled $true
    }
})

$btnRefresh.Add_Click({ Update-BackupList })

$btnReset.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will close AnyDesk, back up your address book, delete the local AnyDesk config, generate a fresh ID, then restore your address book and relaunch AnyDesk.`n`nContinue?",
        "Confirm Reset",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Set-ButtonsEnabled $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Write-Log "Closing AnyDesk..." $colorText
        if (Stop-AnyDeskProcess) { Write-Log "Process stopped" $colorMuted } else { Write-Log "Not running" $colorMuted }

        Write-Log "Backing up address book..." $colorText
        $backupResult = Backup-AnyDeskConfig -BackupRoot $BackupRoot
        if ($backupResult.Found.Count -gt 0) {
            Write-Log "Found: $($backupResult.Found -join ', ')" $colorOk
        } else {
            Write-Log "Nothing to preserve (no saved addresses or passwords found)" $colorMuted
        }
        Update-BackupList

        Write-Log "Deleting AnyDesk config (ProgramData + Roaming)..." $colorText
        $removed = Remove-AnyDeskConfig
        if ($removed.Count -gt 0) { Write-Log "Removed: $($removed -join ', ')" $colorMuted } else { Write-Log "Nothing to remove" $colorMuted }

        $anyDeskExe = Get-AnyDeskExe
        if (-not $anyDeskExe) {
            Write-Log "AnyDesk.exe not found automatically. Please reinstall or locate it manually." $colorErr
            return
        }

        Write-Log "Generating new identity (this takes a few seconds)..." $colorText
        $idResult = Start-AnyDeskAndWaitForId -AnyDeskExe $anyDeskExe -TimeoutSeconds 25 -OnTick {
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($idResult.Ready) {
            Write-Log "New ID: $($idResult.Id)" $colorOk
        } else {
            Write-Log "Timed out waiting for a new ID - continuing anyway." $colorWarn
        }

        Write-Log "Restoring address book..." $colorText
        $paths = Get-AnyDeskPaths
        if (-not (Test-Path $paths.UserConfPath)) {
            Write-Log "AnyDesk hadn't finished initializing; address book not restored. Backup is safe at $($backupResult.BackupDir)" $colorWarn
        } else {
            $restored = Restore-AnyDeskConfig -Backup $backupResult.Backup
            if ($restored.Count -gt 0) { Write-Log "Restored: $($restored -join ', ')" $colorOk } else { Write-Log "Nothing to restore" $colorMuted }
        }

        Write-Log "Relaunching AnyDesk..." $colorText
        Start-Process $anyDeskExe

        $sw.Stop()
        Write-Log "Reset complete in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s." $colorOk
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)" $colorErr
    } finally {
        Set-ButtonsEnabled $true
    }
})

Update-BackupList
[System.Windows.Forms.Application]::Run($form)
