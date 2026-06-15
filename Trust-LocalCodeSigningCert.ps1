$ErrorActionPreference = "Stop"

$CertSubject = "CN=Chase Cole Software"
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq $CertSubject } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    throw "Could not find the local code-signing certificate. Run .\Build-Exe.ps1 first."
}

$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$publisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "CurrentUser")

$rootStore.Open("ReadWrite")
$publisherStore.Open("ReadWrite")

try {
    $rootStore.Add($cert)
    $publisherStore.Add($cert)
} finally {
    $rootStore.Close()
    $publisherStore.Close()
}

Write-Host "Trusted local code-signing certificate:"
Write-Host $cert.Subject
Write-Host $cert.Thumbprint
Write-Host ""
Get-AuthenticodeSignature -FilePath (Join-Path $PSScriptRoot "YouTubeMp3Backup.exe") | Format-List Status,StatusMessage,SignerCertificate
