$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir = Join-Path $Root "tools"
$BinDir = Join-Path $ToolsDir "bin"
$YtDlp = Join-Path $BinDir "yt-dlp.exe"
$Ffmpeg = Join-Path $BinDir "ffmpeg.exe"
$Deno = Join-Path $BinDir "deno.exe"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
}

if (-not (Test-Path $YtDlp)) {
    Download-File `
        -Url "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" `
        -Destination $YtDlp
} else {
    Write-Host "yt-dlp already exists."
}

if (-not (Test-Path $Ffmpeg)) {
    $ZipPath = Join-Path $ToolsDir "ffmpeg.zip"
    $ExtractDir = Join-Path $ToolsDir "ffmpeg-extract"

    Download-File `
        -Url "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" `
        -Destination $ZipPath

    if (Test-Path $ExtractDir) {
        Remove-Item -LiteralPath $ExtractDir -Recurse -Force
    }

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractDir -Force
    $DownloadedFfmpeg = Get-ChildItem -Path $ExtractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1

    if (-not $DownloadedFfmpeg) {
        throw "Could not find ffmpeg.exe in downloaded archive."
    }

    Copy-Item -LiteralPath $DownloadedFfmpeg.FullName -Destination $Ffmpeg -Force
    Remove-Item -LiteralPath $ZipPath -Force
    Remove-Item -LiteralPath $ExtractDir -Recurse -Force
} else {
    Write-Host "ffmpeg already exists."
}

if (-not (Test-Path $Deno)) {
    $DenoZipPath = Join-Path $ToolsDir "deno.zip"
    $DenoExtractDir = Join-Path $ToolsDir "deno-extract"

    Download-File `
        -Url "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" `
        -Destination $DenoZipPath

    if (Test-Path $DenoExtractDir) {
        Remove-Item -LiteralPath $DenoExtractDir -Recurse -Force
    }

    Expand-Archive -LiteralPath $DenoZipPath -DestinationPath $DenoExtractDir -Force
    $DownloadedDeno = Get-ChildItem -Path $DenoExtractDir -Recurse -Filter "deno.exe" | Select-Object -First 1

    if (-not $DownloadedDeno) {
        throw "Could not find deno.exe in downloaded archive."
    }

    Copy-Item -LiteralPath $DownloadedDeno.FullName -Destination $Deno -Force
    Remove-Item -LiteralPath $DenoZipPath -Force
    Remove-Item -LiteralPath $DenoExtractDir -Recurse -Force
} else {
    Write-Host "deno already exists."
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "Run .\Start-YouTubeMp3.ps1 to open the app."
