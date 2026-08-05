<#
.SYNOPSIS
    Batch Installer Pro v2.0
    A modern, high-performance silent installer deployment tool for Windows with voice notifications.

.AUTHOR
    Pranab Chourasiya
#>

# Load Assemblies FIRST before invoking WinForms methods
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName System.Speech -ErrorAction SilentlyContinue } catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# Voice Notification Engine
# ---------------------------------------------------------------------------
function Speak-Voice([string]$text) {
    try {
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.SpeakAsync($text) | Out-Null
    } catch {
        try {
            $sapi = New-Object -ComObject SAPI.SpVoice
            $sapi.Speak($text, 1) | Out-Null
        } catch {}
    }
}

try {

# ---------------------------------------------------------------------------
# 1. Administrator Elevation Check
# ---------------------------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Batch Installer Pro requires Administrator privileges to run installers silently.`n`nWould you like to restart as Administrator now?",
        "Batch Installer Pro | Developed by Pranab Chourasiya",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

# ---------------------------------------------------------------------------
# 2. Relocation Logic to 'Downloads\lab softwares'
# ---------------------------------------------------------------------------
$scriptDir = [System.IO.Directory]::GetCurrentDirectory()
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -notlike "*AppData\Local\Temp*") {
    $selfName = Split-Path -Leaf $MyInvocation.MyCommand.Path
} else {
    $selfName = "BatchInstaller.exe"
}
$markerName = ".batchinstaller_relocated"

if (-not (Test-Path (Join-Path $scriptDir $markerName))) {
    $userDownloads = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
    $destRoot      = Join-Path $userDownloads "lab softwares"

    if (Test-Path $destRoot) {
        $stamp    = Get-Date -Format "yyyyMMdd_HHmmss"
        $destRoot = Join-Path $userDownloads "lab softwares_$stamp"
    }

    try {
        New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptDir "*") -Destination $destRoot -Recurse -Force -ErrorAction Stop
        New-Item -ItemType File -Path (Join-Path $destRoot $markerName) -Force | Out-Null

        $newAppPath = Join-Path $destRoot $selfName
        if ($newAppPath -like "*.exe" -and (Test-Path $newAppPath)) {
            Start-Process -FilePath $newAppPath -Verb RunAs
        } else {
            $fallbackScript = Join-Path $destRoot "BatchInstaller.ps1"
            Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$fallbackScript`""
        }
        exit
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Notice: Could not automatically relocate to Downloads\lab softwares.`nDetails: $($_.Exception.Message)`n`nContinuing execution from current folder.",
            "Batch Installer Pro | Developed by Pranab Chourasiya",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# 3. High-Performance Stream-Based Silent Argument Sniffer
# ---------------------------------------------------------------------------
function Get-InstallerTechAndArgs {
    param([System.IO.FileInfo]$file)

    if ($file.Extension -eq ".msi") {
        return [PSCustomObject]@{
            Technology = "Windows Installer (MSI)"
            Args       = "/qn /norestart"
        }
    }

    $sample = ""
    try {
        $stream = [System.IO.File]::OpenRead($file.FullName)
        $buffer = New-Object byte[] 2000000
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        $stream.Close()
        $stream.Dispose()
        if ($bytesRead -gt 0) {
            $sample = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
        }
    } catch {
        $sample = ""
    }

    if ($sample -match "Inno Setup") {
        return [PSCustomObject]@{ Technology = "Inno Setup"; Args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" }
    } elseif ($sample -match "Nullsoft|NSIS") {
        return [PSCustomObject]@{ Technology = "NSIS (Nullsoft)"; Args = "/S" }
    } elseif ($sample -match "InstallShield") {
        return [PSCustomObject]@{ Technology = "InstallShield"; Args = "/s /v`"/qn`"" }
    } elseif ($sample -match "WiX Toolset|WiXBurn") {
        return [PSCustomObject]@{ Technology = "WiX Burn"; Args = "/quiet /norestart" }
    } elseif ($sample -match "WiseInstall|Wise Installation") {
        return [PSCustomObject]@{ Technology = "Wise Installer"; Args = "/s" }
    } elseif ($sample -match "7-Zip SFX") {
        return [PSCustomObject]@{ Technology = "7-Zip SFX"; Args = "-y" }
    } elseif ($sample -match "BitRock") {
        return [PSCustomObject]@{ Technology = "BitRock Installer"; Args = "/mode unattended" }
    } elseif ($sample -match "Squirrel|Update.exe") {
        return [PSCustomObject]@{ Technology = "Squirrel"; Args = "--silent" }
    } elseif ($sample -match "Chrome|Chromium|Edge") {
        return [PSCustomObject]@{ Technology = "Chromium Silent"; Args = "/silent /install" }
    } else {
        return [PSCustomObject]@{ Technology = "Generic / Custom"; Args = "/S" }
    }
}

function Format-FileSize {
    param([long]$bytes)
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Map-ExitCodeMessage {
    param([int]$code)
    switch ($code) {
        0    { return "SUCCESS" }
        3010 { return "SUCCESS (Reboot Required)" }
        1602 { return "CANCELLED BY USER" }
        1603 { return "FATAL ERROR DURING INSTALLATION" }
        1618 { return "ERROR: ANOTHER INSTALLATION IN PROGRESS" }
        1619 { return "ERROR: COULD NOT OPEN PACKAGE" }
        1638 { return "ERROR: ANOTHER VERSION ALREADY INSTALLED" }
        default { return "FINISHED (Exit Code: $code)" }
    }
}

# ---------------------------------------------------------------------------
# 4. Find Installers in Directory
# ---------------------------------------------------------------------------
$installers = Get-ChildItem -Path $scriptDir -File | Where-Object {
    $_.Extension -in ".exe", ".msi" -and $_.Name -ne $selfName
}

if ($installers.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "No .exe or .msi installers found in directory:`n$scriptDir`n`nPlease place your installer binaries here and relaunch.",
        "Batch Installer Pro | Developed by Pranab Chourasiya",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    exit
}

# ---------------------------------------------------------------------------
# 5. Build Premium Modern Dark GUI
# ---------------------------------------------------------------------------
$themeBg          = [System.Drawing.Color]::FromArgb(30, 30, 30)
$themeCardBg      = [System.Drawing.Color]::FromArgb(45, 45, 48)
$themeGridHeader  = [System.Drawing.Color]::FromArgb(37, 37, 38)
$themeGridAltRow  = [System.Drawing.Color]::FromArgb(38, 38, 40)
$themeAccent      = [System.Drawing.Color]::FromArgb(0, 122, 204)
$themeTextLight   = [System.Drawing.Color]::FromArgb(240, 240, 240)
$themeTextMuted   = [System.Drawing.Color]::FromArgb(170, 170, 170)
$themeLogBg       = [System.Drawing.Color]::FromArgb(15, 15, 15)
$themeLogFg       = [System.Drawing.Color]::FromArgb(0, 230, 150)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Batch Installer Pro v2.0 - Developed by Pranab Chourasiya"
$form.Size = New-Object System.Drawing.Size(920, 680)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 580)
$form.BackColor = $themeBg
$form.ForeColor = $themeTextLight
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

# --- Top Header Panel ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 70
$pnlHeader.BackColor = $themeCardBg
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Batch Installer Pro"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $themeTextLight
$lblTitle.Location = New-Object System.Drawing.Point(16, 10)
$lblTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblTitle)

$lblAuthorBadge = New-Object System.Windows.Forms.Label
$lblAuthorBadge.Text = "Made by Pranab Chourasiya"
$lblAuthorBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblAuthorBadge.ForeColor = [System.Drawing.Color]::FromArgb(0, 200, 255)
$lblAuthorBadge.Location = New-Object System.Drawing.Point(220, 18)
$lblAuthorBadge.AutoSize = $true
$pnlHeader.Controls.Add($lblAuthorBadge)

$lblSubHeader = New-Object System.Windows.Forms.Label
$lblSubHeader.Text = "Working Folder: $scriptDir  |  Total Found: $($installers.Count)"
$lblSubHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSubHeader.ForeColor = $themeTextMuted
$lblSubHeader.Location = New-Object System.Drawing.Point(18, 40)
$lblSubHeader.AutoSize = $true
$pnlHeader.Controls.Add($lblSubHeader)

# --- Main Container Panel ---
$pnlMain = New-Object System.Windows.Forms.Panel
$pnlMain.Dock = "Fill"
$pnlMain.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
$form.Controls.Add($pnlMain)
$pnlMain.BringToFront()

# --- Search & Filter Bar ---
$pnlToolBar = New-Object System.Windows.Forms.Panel
$pnlToolBar.Dock = "Top"
$pnlToolBar.Height = 36
$pnlMain.Controls.Add($pnlToolBar)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Filter:"
$lblSearch.Location = New-Object System.Drawing.Point(0, 8)
$lblSearch.AutoSize = $true
$lblSearch.ForeColor = $themeTextLight
$pnlToolBar.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(45, 5)
$txtSearch.Size = New-Object System.Drawing.Size(180, 25)
$txtSearch.BackColor = $themeCardBg
$txtSearch.ForeColor = $themeTextLight
$txtSearch.BorderStyle = "FixedSingle"
$pnlToolBar.Controls.Add($txtSearch)

$chkVoice = New-Object System.Windows.Forms.CheckBox
$chkVoice.Text = "Voice Alerts"
$chkVoice.Checked = $true
$chkVoice.Location = New-Object System.Drawing.Point(235, 7)
$chkVoice.AutoSize = $true
$chkVoice.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 150)
$chkVoice.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$pnlToolBar.Controls.Add($chkVoice)

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "Select All"
$btnAll.Location = New-Object System.Drawing.Point(340, 4)
$btnAll.Size = New-Object System.Drawing.Size(85, 28)
$btnAll.FlatStyle = "Flat"
$btnAll.FlatAppearance.BorderSize = 0
$btnAll.BackColor = $themeCardBg
$btnAll.ForeColor = $themeTextLight
$btnAll.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlToolBar.Controls.Add($btnAll)

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = "Select None"
$btnNone.Location = New-Object System.Drawing.Point(432, 4)
$btnNone.Size = New-Object System.Drawing.Size(85, 28)
$btnNone.FlatStyle = "Flat"
$btnNone.FlatAppearance.BorderSize = 0
$btnNone.BackColor = $themeCardBg
$btnNone.ForeColor = $themeTextLight
$btnNone.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlToolBar.Controls.Add($btnNone)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install Selected"
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)
$btnInstall.Location = New-Object System.Drawing.Point(700, 2)
$btnInstall.Size = New-Object System.Drawing.Size(185, 32)
$btnInstall.Anchor = "Top,Right"
$btnInstall.FlatStyle = "Flat"
$btnInstall.FlatAppearance.BorderSize = 0
$btnInstall.BackColor = $themeAccent
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlToolBar.Controls.Add($btnInstall)

# --- DataGridView ---
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = "Top"
$grid.Height = 280
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = "Fill"
$grid.SelectionMode = "FullRowSelect"
$grid.EditMode = "EditOnEnter"
$grid.BackgroundColor = $themeBg
$grid.BorderStyle = "None"
$grid.GridColor = [System.Drawing.Color]::FromArgb(60, 60, 65)
$grid.DefaultCellStyle.BackColor = $themeBg
$grid.DefaultCellStyle.ForeColor = $themeTextLight
$grid.DefaultCellStyle.SelectionBackColor = $themeAccent
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$grid.AlternatingRowsDefaultCellStyle.BackColor = $themeGridAltRow
$grid.ColumnHeadersDefaultCellStyle.BackColor = $themeGridHeader
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $themeTextLight
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$grid.EnableHeadersVisualStyles = $false
$grid.RowTemplate.Height = 28

$colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.Name = "Install"
$colCheck.HeaderText = "Install"
$colCheck.FillWeight = 10
$grid.Columns.Add($colCheck) | Out-Null

$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.Name = "Name"
$colName.HeaderText = "Installer Binary"
$colName.ReadOnly = $true
$colName.FillWeight = 32
$grid.Columns.Add($colName) | Out-Null

$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.Name = "Size"
$colSize.HeaderText = "Size"
$colSize.ReadOnly = $true
$colSize.FillWeight = 12
$grid.Columns.Add($colSize) | Out-Null

$colTech = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTech.Name = "Technology"
$colTech.HeaderText = "Engine / Tech"
$colTech.ReadOnly = $true
$colTech.FillWeight = 20
$grid.Columns.Add($colTech) | Out-Null

$colArgs = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colArgs.Name = "Args"
$colArgs.HeaderText = "Silent Installation Arguments (Editable)"
$colArgs.FillWeight = 36
$grid.Columns.Add($colArgs) | Out-Null

# Populate Grid
foreach ($f in $installers) {
    $info = Get-InstallerTechAndArgs -file $f
    $formattedSize = Format-FileSize -bytes $f.Length
    $grid.Rows.Add($true, $f.Name, $formattedSize, $info.Technology, $info.Args) | Out-Null
}

$pnlMain.Controls.Add($grid)

# --- Progress Bar ---
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = "Top"
$progressBar.Height = 10
$progressBar.Style = "Continuous"
$progressBar.Value = 0
$pnlMain.Controls.Add($progressBar)

# --- Terminal Log Box ---
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Execution Log Console:"
$lblLog.Dock = "Top"
$lblLog.Height = 25
$lblLog.TextAlign = "BottomLeft"
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblLog.ForeColor = $themeTextMuted
$pnlMain.Controls.Add($lblLog)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = "Fill"
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $themeLogBg
$logBox.ForeColor = $themeLogFg
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$logBox.BorderStyle = "FixedSingle"
$pnlMain.Controls.Add($logBox)

# --- Footer Panel ---
$pnlFooter = New-Object System.Windows.Forms.Panel
$pnlFooter.Dock = "Bottom"
$pnlFooter.Height = 28
$pnlFooter.BackColor = $themeCardBg
$form.Controls.Add($pnlFooter)

$lblFooterTag = New-Object System.Windows.Forms.Label
$lblFooterTag.Text = "Batch Installer Pro v2.0 | Author: Pranab Chourasiya | Location: lab softwares"
$lblFooterTag.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFooterTag.ForeColor = $themeTextMuted
$lblFooterTag.Dock = "Fill"
$lblFooterTag.TextAlign = "MiddleCenter"
$pnlFooter.Controls.Add($lblFooterTag)

# Arrange Control Z-Orders
$grid.BringToFront()
$progressBar.BringToFront()
$lblLog.BringToFront()
$logBox.BringToFront()

# ---------------------------------------------------------------------------
# 6. Event Handlers & Installation Execution Logic
# ---------------------------------------------------------------------------
$btnAll.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells["Install"].Value = $true }
})

$btnNone.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells["Install"].Value = $false }
})

$txtSearch.Add_TextChanged({
    $filter = $txtSearch.Text.Trim()
    foreach ($row in $grid.Rows) {
        if ([string]::IsNullOrWhiteSpace($filter)) {
            $row.Visible = $true
        } else {
            $nameMatch = $row.Cells["Name"].Value -like "*$filter*"
            $techMatch = $row.Cells["Technology"].Value -like "*$filter*"
            $row.Visible = ($nameMatch -or $techMatch)
        }
    }
})

function Write-Log([string]$msg, [string]$level = "INFO") {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($level) {
        "SUCCESS" { "[+] " }
        "WARN"    { "[!] " }
        "ERROR"   { "[-] " }
        default   { "[*] " }
    }
    $logLine = "[$timestamp] $prefix$msg"
    $logBox.AppendText("$logLine`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    
    Add-Content -Path (Join-Path $scriptDir "InstallLog.txt") -Value $logLine
}

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnAll.Enabled = $false
    $btnNone.Enabled = $false
    
    $selectedItems = @()
    foreach ($row in $grid.Rows) {
        if ($row.Cells["Install"].Value -eq $true) {
            $selectedItems += [PSCustomObject]@{
                Name       = $row.Cells["Name"].Value
                Technology = $row.Cells["Technology"].Value
                Args       = $row.Cells["Args"].Value
            }
        }
    }

    if ($selectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No installers selected for deployment.",
            "Batch Installer Pro | Pranab Chourasiya",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        $btnInstall.Enabled = $true
        $btnAll.Enabled = $true
        $btnNone.Enabled = $true
        return
    }

    Write-Log "Starting batch installation of $($selectedItems.Count) item(s)..." "INFO"
    Write-Log "Author / Developer: Pranab Chourasiya" "INFO"
    Write-Log "Target Directory: $scriptDir" "INFO"
    Write-Log ("-" * 60) "INFO"

    $progressBar.Maximum = $selectedItems.Count
    $progressBar.Value = 0

    $successCount = 0
    $warnCount    = 0
    $failCount    = 0

    foreach ($item in $selectedItems) {
        $fullPath = Join-Path $scriptDir $item.Name
        Write-Log "Deploying: $($item.Name) [$($item.Technology)]" "INFO"
        Write-Log "  Arguments: $($item.Args)" "INFO"
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $startTime = Get-Date
            if ($fullPath -like "*.msi") {
                $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$fullPath`" $($item.Args)" -Wait -PassThru -NoNewWindow
            } else {
                $proc = Start-Process -FilePath $fullPath -ArgumentList $item.Args -Wait -PassThru -NoNewWindow
            }
            $duration = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

            $statusMsg = Map-ExitCodeMessage -code $proc.ExitCode
            if ($proc.ExitCode -eq 0) {
                Write-Log "  -> $statusMsg (Completed in ${duration}s)" "SUCCESS"
                $successCount++
            } elseif ($proc.ExitCode -eq 3010) {
                Write-Log "  -> $statusMsg (Completed in ${duration}s)" "WARN"
                $warnCount++
            } else {
                Write-Log "  -> $statusMsg (Completed in ${duration}s)" "ERROR"
                $failCount++
                if ($chkVoice.Checked) {
                    Speak-Voice "Gadbad ho gayi malik"
                }
            }
        } catch {
            Write-Log "  -> EXCEPTION: $($_.Exception.Message)" "ERROR"
            $failCount++
            if ($chkVoice.Checked) {
                Speak-Voice "Gadbad ho gayi malik"
            }
        }

        $progressBar.Value++
        [System.Windows.Forms.Application]::DoEvents()
    }

    Write-Log ("-" * 60) "INFO"
    Write-Log "Batch Installation Completed!" "SUCCESS"
    Write-Log "Summary: Succeeded: $successCount | Warnings/Reboots: $warnCount | Failed/Review: $failCount" "INFO"

    # Play Voice Notifications
    if ($chkVoice.Checked) {
        if ($failCount -eq 0) {
            Speak-Voice "Shukriya malik"
        } else {
            Speak-Voice "Gadbad ho gayi malik"
        }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Batch Installation Completed!`n`nSucceeded: $successCount`nWarnings/Reboots: $warnCount`nNeed Review: $failCount`n`nDetailed log file created in InstallLog.txt.`n`nBatch Installer Pro | Designed by Pranab Chourasiya",
        "Batch Installer Pro",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

    $btnInstall.Enabled = $true
    $btnAll.Enabled = $true
    $btnNone.Enabled = $true
})

# Display Form
Write-Log "Batch Installer Pro v2.0 Initialized." "SUCCESS"
Write-Log "Developed by Pranab Chourasiya" "INFO"
Write-Log "Found $($installers.Count) installer binary file(s) in current workspace." "INFO"
[void]$form.ShowDialog()

} catch {
    Speak-Voice "Gadbad ho gayi malik"
    Write-Host ""
    Write-Host "================ BATCH INSTALLER PRO ERROR ================" -ForegroundColor Red
    Write-Host "Developer: Pranab Chourasiya" -ForegroundColor Yellow
    Write-Host "Error Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.ScriptStackTrace
    Write-Host "===========================================================" -ForegroundColor Red
    Read-Host "Press Enter to close window"
}
