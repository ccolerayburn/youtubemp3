$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$InputFile = Join-Path $Root "Start-YouTubeMp3.ps1"
$OutputFile = Join-Path $Root "YouTubeMp3Backup.exe"
$IconFile = Join-Path $Root "app-icon.ico"
$CertSubject = "CN=Chase Cole Software"

if (-not (Test-Path $IconFile)) {
    & (Join-Path $Root "New-AppIcon.ps1")
}

if (-not (Get-Module -ListAvailable ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}

Invoke-ps2exe `
    -inputFile $InputFile `
    -outputFile $OutputFile `
    -noConsole `
    -STA `
    -DPIAware `
    -iconFile $IconFile `
    -title "YouTube MP3 Backup" `
    -product "YouTube MP3 Backup" `
    -description "Local YouTube audio backup helper" `
    -company "Chase Cole Software" `
    -version "1.0.0.0"

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq $CertSubject } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $CertSubject `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyAlgorithm RSA `
        -KeyLength 3072 `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(5)
}

Set-AuthenticodeSignature -FilePath $OutputFile -Certificate $cert -HashAlgorithm SHA256
Get-AuthenticodeSignature -FilePath $OutputFile | Format-List Status,StatusMessage,SignerCertificate
