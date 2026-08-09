param(
    [string]$PasswordPlain
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pfx = Join-Path $root "keys\brent-novagram-codesign.pfx"

if (Test-Path -LiteralPath $pfx) {
    Write-Host "PFX already exists: $pfx"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PasswordPlain)) {
    $password = Read-Host -AsSecureString "PFX password"
} else {
    $password = ConvertTo-SecureString $PasswordPlain -AsPlainText -Force
}
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=Brent NovaGram" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm RSA `
    -KeyLength 4096 `
    -KeyUsage DigitalSignature `
    -NotAfter (Get-Date).AddYears(10)

Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $password | Out-Null
Write-Host "Created $pfx"
