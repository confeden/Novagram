param(
    [string]$Task = ":TMessagesProj_App:assembleAfatRelease",

    [ValidateRange(1, 16)]
    [int]$MaxWorkers = 4
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$androidRoot = Join-Path $root "android\novagram-android"

& (Join-Path $PSScriptRoot "check-upstream.ps1") -Project Android

if (Test-Path (Join-Path $root ".novagram.local.ps1")) {
    . (Join-Path $root ".novagram.local.ps1")
}

$apiId = $env:NOVA_TELEGRAM_API_ID
$apiHash = $env:NOVA_TELEGRAM_API_HASH
if ([string]::IsNullOrWhiteSpace($apiId) -or [string]::IsNullOrWhiteSpace($apiHash)) {
    throw "Set NOVA_TELEGRAM_API_ID and NOVA_TELEGRAM_API_HASH in .novagram.local.ps1 or environment."
}

$localProperties = Join-Path $androidRoot "local.properties"
@"
NOVA_TELEGRAM_API_ID=$apiId
NOVA_TELEGRAM_API_HASH=$apiHash
"@ | Set-Content -LiteralPath $localProperties -Encoding ascii

Push-Location $androidRoot
try {
    $env:CMAKE_BUILD_PARALLEL_LEVEL = $MaxWorkers
    $gradleArgs = @($Task, "--max-workers=$MaxWorkers", "--no-parallel")
    if (Test-Path -LiteralPath ".\gradlew.bat") {
        & .\gradlew.bat @gradleArgs
    } elseif (Test-Path -LiteralPath ".\gradlew") {
        & bash .\gradlew @gradleArgs
    } else {
        & gradle @gradleArgs
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
