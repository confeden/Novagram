param(
    [string]$Task = ":TMessagesProj_App:assembleAfatRelease",

    # Debug instead of release: skips R8, which is the part that costs the
    # minutes. Use it while iterating - it catches every compile error the
    # release build would. It does NOT catch the one thing only R8 catches:
    # a class reachable solely through an upstream hook gets stripped and the
    # release fails with "Missing class". That trap already cost one run, so a
    # release build stays mandatory before shipping.
    [switch]$Fast,

    # Six of the eight cores. The remaining two keep the machine usable and
    # leave room for the native build, which spawns its own jobs through
    # CMAKE_BUILD_PARALLEL_LEVEL below.
    [ValidateRange(1, 16)]
    [int]$MaxWorkers = 6
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$androidRoot = Join-Path $root "android\novagram-android"

if ($Fast -and !$PSBoundParameters.ContainsKey("Task")) {
    $Task = ":TMessagesProj_App:assembleAfatDebug"
    Write-Host "Fast mode: building debug, R8 is skipped. Build release before shipping." -ForegroundColor Yellow
}

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
