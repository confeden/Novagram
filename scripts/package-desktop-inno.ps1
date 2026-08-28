param(
    [string]$BuildDir = "D:\Documents\Coding\NovaGram\desktop\novagram-desktop\out",
    [string]$InnoRoot = "D:\Programs\Inno Setup 6"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$iscc = Join-Path $InnoRoot "ISCC.exe"
$iss = Join-Path $root "desktop\novagram-desktop\packaging\novagram.iss"
$dist = Join-Path $root "dist"

if (!(Test-Path -LiteralPath $iscc)) {
    throw "ISCC.exe not found at $iscc"
}
if (!(Test-Path -LiteralPath $BuildDir)) {
    throw "BuildDir not found: $BuildDir"
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$externalPfx = $env:NOVAGRAM_PFX
$externalPfxPassword = $env:NOVAGRAM_PFX_PASSWORD
if (Test-Path (Join-Path $root ".novagram.local.ps1")) {
    . (Join-Path $root ".novagram.local.ps1")
}
if ($externalPfx) {
    $env:NOVAGRAM_PFX = $externalPfx
}
if ($externalPfxPassword) {
    $env:NOVAGRAM_PFX_PASSWORD = $externalPfxPassword
}

$signingEnabled = $false
$signtool = $null
if ($env:NOVAGRAM_PFX -and $env:NOVAGRAM_PFX_PASSWORD -and (Test-Path -LiteralPath $env:NOVAGRAM_PFX)) {
    $signtoolCandidates = @(
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.28000.0\x64\signtool.exe"
    )
    $signtool = $signtoolCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($signtool)) {
        throw "signtool.exe not found in Windows Kits."
    }
    $signingEnabled = $true
}

if (!$signingEnabled) {
    throw "Installer signing is required. Configure NOVAGRAM_PFX and NOVAGRAM_PFX_PASSWORD in .novagram.local.ps1."
}

& $iscc "/DBuildDir=$BuildDir" "/DOutputDir=$dist" $iss
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($signingEnabled) {
    $setup = Get-ChildItem -LiteralPath $dist -Filter "NovaGramSetup-*-x64.exe" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (!$setup) {
        throw "NovaGram installer was not created in $dist"
    }
    # The client refuses to run an installer whose signature does not verify,
    # and an untimestamped signature stops verifying the day the certificate
    # expires - which would reject every installer ever built, not just new
    # ones. A timestamp fixes the signature to the moment it was made.
    $timestampUrls = @(
        "http://timestamp.sectigo.com",
        "http://timestamp.digicert.com"
    )
    $signed = $false
    foreach ($tsa in $timestampUrls) {
        & $signtool sign /fd SHA256 /tr $tsa /td SHA256 `
            /f $env:NOVAGRAM_PFX /p $env:NOVAGRAM_PFX_PASSWORD $setup.FullName
        if ($LASTEXITCODE -eq 0) { $signed = $true; break }
        Write-Host "Timestamping through $tsa failed, trying the next one."
    }
    if (!$signed) {
        throw "Signing failed: no timestamp authority answered. A signature without a timestamp expires with the certificate and would make every installer unverifiable, so this is not silently skipped."
    }
}
