Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

if ($MyInvocation.MyCommand.Path) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $Root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$DownloadScript = Join-Path $Root "Download-YouTubeMp3.ps1"
$SetupScript = Join-Path $Root "setup.ps1"
$DefaultOutput = "C:\_Media\MP3"
$script:CurrentProcess = $null
$script:CurrentUrlFile = $null
$script:CurrentProcessLog = $null
$script:CurrentRunnerFile = $null
$script:CurrentLogPosition = 0
$script:AppLogFile = Join-Path $Root "app-error.log"

[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    Add-Content -LiteralPath $script:AppLogFile -Value ("[{0}] UI exception: {1}`r`n{2}" -f (Get-Date), $_.Exception.Message, $_.Exception.ToString())
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    Add-Content -LiteralPath $script:AppLogFile -Value ("[{0}] App exception: {1}" -f (Get-Date), $_.ExceptionObject.ToString())
})

function Test-AppDependencies {
    $YtDlp = Join-Path $Root "tools\bin\yt-dlp.exe"
    $Ffmpeg = Join-Path $Root "tools\bin\ffmpeg.exe"
    $Deno = Join-Path $Root "tools\bin\deno.exe"
    return (Test-Path $YtDlp) -and (Test-Path $Ffmpeg) -and (Test-Path $Deno)
}

function Append-Log {
    param([string]$Text)
    $logBox.AppendText($Text + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

function ConvertTo-ArgumentString {
    param([string[]]$Items)

    return ($Items | ForEach-Object {
        $value = [string]$_
        if ($value -eq "") {
            '""'
        } elseif ($value -match '[\s"]') {
            '"' + ($value.Replace('"', '\"')) + '"'
        } else {
            $value
        }
    }) -join " "
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)

    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Set-RunningState {
    param([bool]$IsRunning)

    $setupButton.Enabled = -not $IsRunning
    $downloadButton.Enabled = -not $IsRunning
    $stopButton.Enabled = $IsRunning
}

function Write-InternalError {
    param([string]$Text)

    try {
        Add-Content -LiteralPath $script:AppLogFile -Value ("[{0}] {1}" -f (Get-Date), $Text)
    } catch {
    }
}

function Read-NewProcessLog {
    if (-not $script:CurrentProcessLog -or -not (Test-Path $script:CurrentProcessLog)) {
        return
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($script:CurrentProcessLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($stream.Length -le $script:CurrentLogPosition) {
            return
        }

        $stream.Position = $script:CurrentLogPosition
        $reader = New-Object System.IO.StreamReader($stream)
        $text = $reader.ReadToEnd()
        $script:CurrentLogPosition = $stream.Position

        if ($text) {
            ($text -split "(`r`n|`n|`r)") |
                Where-Object { $_ -ne "" } |
                ForEach-Object { Append-Log $_ }
        }
    } catch {
        Write-InternalError $_.Exception.ToString()
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Clear-RunFiles {
    if ($script:CurrentUrlFile -and (Test-Path $script:CurrentUrlFile)) {
        Remove-Item -LiteralPath $script:CurrentUrlFile -Force
    }
    $script:CurrentUrlFile = $null

    if ($script:CurrentProcessLog -and (Test-Path $script:CurrentProcessLog)) {
        Remove-Item -LiteralPath $script:CurrentProcessLog -Force
    }
    $script:CurrentProcessLog = $null

    if ($script:CurrentRunnerFile -and (Test-Path $script:CurrentRunnerFile)) {
        Remove-Item -LiteralPath $script:CurrentRunnerFile -Force
    }
    $script:CurrentRunnerFile = $null
    $script:CurrentLogPosition = 0
}

function Start-LoggedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptFile,
        [hashtable]$ScriptParameters = @{},
        [string[]]$ScriptSwitches = @(),
        [Parameter(Mandatory = $true)][string]$RunningStatus,
        [Parameter(Mandatory = $true)][string]$SuccessStatus,
        [Parameter(Mandatory = $true)][string]$FailureStatus
    )

    $statusLabel.Text = $RunningStatus
    Set-RunningState $true
    $script:CurrentProcessLog = Join-Path ([System.IO.Path]::GetTempPath()) ("youtube-mp3-process-{0}.log" -f ([System.Guid]::NewGuid().ToString("N")))
    $script:CurrentRunnerFile = Join-Path ([System.IO.Path]::GetTempPath()) ("youtube-mp3-runner-{0}.ps1" -f ([System.Guid]::NewGuid().ToString("N")))
    $script:CurrentLogPosition = 0
    Set-Content -LiteralPath $script:CurrentProcessLog -Value "" -Encoding UTF8

    $scriptLiteral = ConvertTo-PowerShellLiteral $ScriptFile
    $logLiteral = ConvertTo-PowerShellLiteral $script:CurrentProcessLog
    $paramLines = @('$scriptParams = @{}')
    foreach ($key in $ScriptParameters.Keys) {
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid script parameter name: $key"
        }
        $paramLines += "`$scriptParams['$key'] = $(ConvertTo-PowerShellLiteral $ScriptParameters[$key])"
    }

    $switchText = ($ScriptSwitches | ForEach-Object {
        if ($_ -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid script switch name: $_"
        }
        "-$_"
    }) -join " "

    if ($switchText) {
        $callLine = "    & $scriptLiteral @scriptParams $switchText *>&1 | ForEach-Object { `$_.ToString() } | Out-File -LiteralPath $logLiteral -Encoding UTF8 -Append"
    } else {
        $callLine = "    & $scriptLiteral @scriptParams *>&1 | ForEach-Object { `$_.ToString() } | Out-File -LiteralPath $logLiteral -Encoding UTF8 -Append"
    }

    $runner = @(
        '$ErrorActionPreference = "Continue"'
    ) + $paramLines + @(
        'try {',
        $callLine,
        '    if ($LASTEXITCODE -ne $null) { exit $LASTEXITCODE }',
        '    exit 0',
        '} catch {',
        "    `$_.Exception.ToString() | Out-File -LiteralPath $logLiteral -Encoding UTF8 -Append",
        '    exit 1',
        '}'
    )
    Set-Content -LiteralPath $script:CurrentRunnerFile -Value $runner -Encoding UTF8

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = ConvertTo-ArgumentString @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:CurrentRunnerFile)
    $startInfo.WorkingDirectory = $Root
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.EnableRaisingEvents = $true
    $script:CurrentProcess = $process

    if (-not $process.Start()) {
        throw "Could not start powershell.exe."
    }

    $timer.Tag = @{
        Process = $process
        SuccessStatus = $SuccessStatus
        FailureStatus = $FailureStatus
    }
    $timer.Start()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "YouTube MP3 Backup"
$form.Size = New-Object System.Drawing.Size(820, 640)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(720, 560)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 500
$toolTip.ReshowDelay = 100

$labelUrl = New-Object System.Windows.Forms.Label
$labelUrl.Text = "YouTube URLs, one per line"
$labelUrl.Location = New-Object System.Drawing.Point(16, 18)
$labelUrl.Size = New-Object System.Drawing.Size(220, 22)
$form.Controls.Add($labelUrl)

$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(16, 42)
$urlBox.Size = New-Object System.Drawing.Size(770, 88)
$urlBox.Anchor = "Top,Left,Right"
$urlBox.Multiline = $true
$urlBox.ScrollBars = "Vertical"
$urlBox.AcceptsReturn = $true
$form.Controls.Add($urlBox)

$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = "Output folder"
$labelOutput.Location = New-Object System.Drawing.Point(16, 146)
$labelOutput.Size = New-Object System.Drawing.Size(140, 22)
$form.Controls.Add($labelOutput)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(16, 170)
$outputBox.Size = New-Object System.Drawing.Size(650, 24)
$outputBox.Anchor = "Top,Left,Right"
$outputBox.Text = $DefaultOutput
$form.Controls.Add($outputBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object System.Drawing.Point(676, 168)
$browseButton.Size = New-Object System.Drawing.Size(110, 28)
$browseButton.Anchor = "Top,Right"
$form.Controls.Add($browseButton)

$archiveBox = New-Object System.Windows.Forms.CheckBox
$archiveBox.Text = "Archive mode"
$archiveBox.Location = New-Object System.Drawing.Point(16, 212)
$archiveBox.Size = New-Object System.Drawing.Size(130, 24)
$archiveBox.Checked = $true
$form.Controls.Add($archiveBox)
$toolTip.SetToolTip($archiveBox, "Keeps a download-archive.txt file so links already downloaded are skipped on future runs.")

$singleBox = New-Object System.Windows.Forms.CheckBox
$singleBox.Text = "Single video only"
$singleBox.Location = New-Object System.Drawing.Point(160, 212)
$singleBox.Size = New-Object System.Drawing.Size(140, 24)
$singleBox.Checked = $true
$form.Controls.Add($singleBox)
$toolTip.SetToolTip($singleBox, "For watch links, downloads only that video even if the URL includes a playlist or radio list.")

$setupButton = New-Object System.Windows.Forms.Button
$setupButton.Text = "Install tools"
$setupButton.Location = New-Object System.Drawing.Point(16, 252)
$setupButton.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($setupButton)

$downloadButton = New-Object System.Windows.Forms.Button
$downloadButton.Text = "Download MP3"
$downloadButton.Location = New-Object System.Drawing.Point(150, 252)
$downloadButton.Size = New-Object System.Drawing.Size(140, 34)
$form.Controls.Add($downloadButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object System.Drawing.Point(304, 252)
$stopButton.Size = New-Object System.Drawing.Size(90, 34)
$stopButton.Enabled = $false
$form.Controls.Add($stopButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(410, 260)
$statusLabel.Size = New-Object System.Drawing.Size(370, 22)
$statusLabel.Anchor = "Top,Left,Right"
$form.Controls.Add($statusLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(16, 304)
$logBox.Size = New-Object System.Drawing.Size(770, 280)
$logBox.Anchor = "Top,Bottom,Left,Right"
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    try {
        Read-NewProcessLog

        if (-not $script:CurrentProcess) {
            return
        }

        if ($script:CurrentProcess.HasExited) {
            $timer.Stop()
            Read-NewProcessLog

            $exitCode = $script:CurrentProcess.ExitCode
            $runState = $timer.Tag

            if ($exitCode -eq 0) {
                $statusLabel.Text = $runState.SuccessStatus
                Append-Log $runState.SuccessStatus
            } else {
                $statusLabel.Text = $runState.FailureStatus
                Append-Log "$($runState.FailureStatus) Exit code: $exitCode"
            }

            Set-RunningState $false
            $script:CurrentProcess.Dispose()
            $script:CurrentProcess = $null
            Clear-RunFiles
        }
    } catch {
        Write-InternalError $_.Exception.ToString()
        $timer.Stop()
        $statusLabel.Text = "Download failed."
        Append-Log "The app caught an internal error. See app-error.log."
        Set-RunningState $false
        if ($script:CurrentProcess) {
            try { $script:CurrentProcess.Dispose() } catch {}
            $script:CurrentProcess = $null
        }
        Clear-RunFiles
    }
})

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $outputBox.Text
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dialog.SelectedPath
    }
})

$setupButton.Add_Click({
    Append-Log "Running setup..."

    try {
        Start-LoggedProcess `
            -ScriptFile $SetupScript `
            -RunningStatus "Installing local tools..." `
            -SuccessStatus "Tools are installed." `
            -FailureStatus "Setup failed."
    } catch {
        Append-Log $_.Exception.Message
        $statusLabel.Text = "Setup failed."
        Set-RunningState $false
    }
})

$downloadButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($urlBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Paste at least one YouTube video, playlist, or channel URL first.", "Missing URL") | Out-Null
        return
    }

    if (-not (Test-AppDependencies)) {
        [System.Windows.Forms.MessageBox]::Show("Install tools first. This downloads yt-dlp, ffmpeg, and deno into the local tools folder.", "Tools needed") | Out-Null
        return
    }

    $urls = $urlBox.Lines |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }

    if (-not $urls) {
        [System.Windows.Forms.MessageBox]::Show("Paste at least one YouTube URL. Blank lines and lines starting with # are ignored.", "Missing URL") | Out-Null
        return
    }

    $script:CurrentUrlFile = Join-Path ([System.IO.Path]::GetTempPath()) ("youtube-mp3-urls-{0}.txt" -f ([System.Guid]::NewGuid().ToString("N")))
    [System.IO.File]::WriteAllLines($script:CurrentUrlFile, [string[]]$urls)

    Append-Log "Starting batch download: $($urls.Count) link(s)"

    try {
        $downloadParams = @{
            UrlFile = $script:CurrentUrlFile
            OutputFolder = $outputBox.Text
        }
        $downloadSwitches = @()

        if ($archiveBox.Checked) {
            $downloadSwitches += "Archive"
        }

        if ($singleBox.Checked) {
            $downloadSwitches += "NoPlaylist"
        }

        Start-LoggedProcess `
            -ScriptFile $DownloadScript `
            -ScriptParameters $downloadParams `
            -ScriptSwitches $downloadSwitches `
            -RunningStatus "Downloading..." `
            -SuccessStatus "Done." `
            -FailureStatus "Download failed."
    } catch {
        Append-Log $_.Exception.Message
        $statusLabel.Text = "Download failed."
        if ($script:CurrentUrlFile -and (Test-Path $script:CurrentUrlFile)) {
            Remove-Item -LiteralPath $script:CurrentUrlFile -Force
        }
        $script:CurrentUrlFile = $null
        Set-RunningState $false
    }
})

$stopButton.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        Append-Log "Stopping current task..."
        try {
            $script:CurrentProcess.Kill($true)
        } catch {
            try {
                $script:CurrentProcess.Kill()
            } catch {
                Append-Log $_.Exception.Message
            }
        }
    }
})

$form.Add_FormClosing({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "A download is still running. Stop it and close?",
            "Download running",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }

        try {
            $script:CurrentProcess.Kill($true)
        } catch {
            try {
                $script:CurrentProcess.Kill()
            } catch {
            }
        }
    }
})

if (Test-AppDependencies) {
    $statusLabel.Text = "Ready."
} else {
    $statusLabel.Text = "Tools not installed yet."
}

[void]$form.ShowDialog()
