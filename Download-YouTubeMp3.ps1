[CmdletBinding()]
param(
    [string[]]$Url,

    [string]$UrlFile,

    [string]$OutputFolder = "C:\_Media\MP3",

    [string]$CookieBrowser,

    [switch]$Archive,

    [switch]$NoPlaylist,

    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

$BinDir = Join-Path $PSScriptRoot "tools\bin"
$YtDlp = Join-Path $BinDir "yt-dlp.exe"
$Ffmpeg = Join-Path $BinDir "ffmpeg.exe"
$Deno = Join-Path $BinDir "deno.exe"
$ArchiveFile = Join-Path $OutputFolder "download-archive.txt"

if (-not (Test-Path $YtDlp)) {
    throw "yt-dlp.exe was not found. Run .\setup.ps1 first."
}

if (-not (Test-Path $Ffmpeg)) {
    throw "ffmpeg.exe was not found. Run .\setup.ps1 first."
}

if (-not (Test-Path $Deno)) {
    throw "deno.exe was not found. Run .\setup.ps1 first."
}

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$Urls = @()

if ($Url) {
    $Urls += $Url | ForEach-Object {
        $_ -split "(`r`n|`n|`r)"
    }
}

if ($UrlFile) {
    if (-not (Test-Path $UrlFile)) {
        throw "URL file was not found: $UrlFile"
    }

    $Urls += Get-Content -LiteralPath $UrlFile
}

$Urls = $Urls |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Select-Object -Unique

if (-not $Urls) {
    throw "No YouTube URLs were provided."
}

$OutputTemplate = Join-Path $OutputFolder "%(channel,uploader|unknown)s\%(playlist_title,series|Singles)s\%(upload_date,release_date|unknown)s - %(title).180B [%(id)s].%(ext)s"

Write-Host "Downloading best available audio and converting to MP3..."
Write-Host "Output: $OutputFolder"
Write-Host "Links: $($Urls.Count)"
Write-Host ""

if ($ValidateOnly) {
    Write-Host "Validation only. No downloads started."
    exit 0
}

$Failed = 0
$Index = 0

foreach ($CurrentUrl in $Urls) {
    $Index++
    Write-Host "[$Index/$($Urls.Count)] $CurrentUrl"

    $Arguments = @(
        "--newline",
        "--ignore-errors",
        "--no-overwrites",
        "--windows-filenames",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--format", "bestaudio/best",
        "--js-runtimes", "deno:$Deno",
        "--ffmpeg-location", $BinDir,
        "--output", $OutputTemplate,
        $CurrentUrl
    )

    if ($Archive) {
        $Arguments = @("--download-archive", $ArchiveFile) + $Arguments
    }

    if ($NoPlaylist) {
        $Arguments = @("--no-playlist") + $Arguments
    }

    if ($CookieBrowser) {
        $Arguments = @("--cookies-from-browser", $CookieBrowser) + $Arguments
    }

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $YtDlp @Arguments 2>&1 | ForEach-Object {
        Write-Host $_.ToString()
    }
    $YtDlpExitCode = $LASTEXITCODE
    $ErrorActionPreference = $PreviousErrorActionPreference

    if ($YtDlpExitCode -ne 0) {
        $Failed++
        Write-Host "Failed with exit code $YtDlpExitCode."
    }

    Write-Host ""
}

if ($Failed -gt 0) {
    throw "$Failed of $($Urls.Count) link(s) failed."
}

Write-Host "Done."
