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

# The prohibited-content list ships inside the APK as a compact snapshot, so a new
# install has a list before its first sync. The snapshot is the link lines of the JSON
# (the app normalises them itself - one parser for the asset and for a synced copy), headed
# by the SHA-256 of the JSON so a first sync that finds the same bytes rewrites nothing.
# Offline, the last copy downloaded is used; with none, the asset is simply absent and the
# app fills its list in from its first sync. A failure here never fails the build.
try {
    $listUrl = "https://raw.githubusercontent.com/confeden/nova_updates/refs/heads/main/forbidden_list/forbidden_list.json"
    $listCache = Join-Path $androidRoot "build\forbidden_list.json"
    $listAsset = Join-Path $androidRoot "TMessagesProj\src\main\assets\novagram_forbidden.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $listCache) | Out-Null
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $listUrl -OutFile "$listCache.new" -TimeoutSec 60
        Move-Item -LiteralPath "$listCache.new" -Destination $listCache -Force
    } catch {
        Remove-Item -LiteralPath "$listCache.new" -Force -ErrorAction SilentlyContinue
        Write-Warning "Prohibited-content list not downloaded ($($_.Exception.Message)); using the last copy if there is one."
    }
    if (Test-Path -LiteralPath $listCache) {
        $listBytes = [System.IO.File]::ReadAllBytes($listCache)
        $sha = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($listBytes)) -replace "-", "").ToLowerInvariant()
        # The five list names, spelled as escapes so this file stays ASCII-clean.
        $codes = @{
            ([regex]::Unescape('\u0438\u043d\u043e\u0430\u0433\u0435\u043d\u0442\u044b')) = 0
            ([regex]::Unescape('\u0442\u0435\u0440\u0440\u043e\u0440\u0438\u0441\u0442\u044b')) = 1
            ([regex]::Unescape('\u044d\u043a\u0441\u0442\u0440\u0435\u043c\u0438\u0441\u0442\u044b')) = 2
            ([regex]::Unescape('\u043d\u0435\u0436\u0435\u043b\u0430\u0442\u0435\u043b\u044c\u043d\u044b\u0435')) = 3
            ([regex]::Unescape('\u043c\u0430\u0442\u0435\u0440\u0438\u0430\u043b\u044b')) = 4
        }
        $json = [System.Text.Encoding]::UTF8.GetString($listBytes) | ConvertFrom-Json
        $out = New-Object System.Text.StringBuilder
        [void]$out.Append("NFL1 $sha`n")
        $count = 0
        foreach ($list in $json.lists.PSObject.Properties) {
            if (-not $codes.ContainsKey($list.Name)) { continue }
            $code = $codes[$list.Name]
            foreach ($item in $list.Value.items) {
                foreach ($link in $item.links) {
                    if ([string]::IsNullOrWhiteSpace($link)) { continue }
                    $clean = $link -replace '[\r\n]', ' '
                    [void]$out.Append("$code`t$clean`n")
                    $count++
                }
                # Materials have no links: their full titles are matched instead.
                if ($code -eq 4 -and -not [string]::IsNullOrWhiteSpace($item.name)) {
                    $title = $item.name -replace '[\r\n]', ' '
                    [void]$out.Append("$code`tname:$title`n")
                    $count++
                }
            }
        }
        if ($count -gt 0) {
            [System.IO.File]::WriteAllText($listAsset, $out.ToString(), (New-Object System.Text.UTF8Encoding $false))
            Write-Host "Prohibited-content snapshot: $count links -> $listAsset"
        } else {
            Write-Warning "Prohibited-content list had no links; the asset was not written."
        }
    } else {
        Write-Warning "No prohibited-content list available; the APK is built without the snapshot."
    }
} catch {
    Write-Warning "Prohibited-content snapshot failed: $($_.Exception.Message)"
}

Push-Location $androidRoot
try {
    $env:CMAKE_BUILD_PARALLEL_LEVEL = $MaxWorkers
    $gradleArgs = @($Task, "--max-workers=$MaxWorkers", "--no-parallel")
    # Gradle writes ordinary notes to the error stream - javac's "some input
    # files use or override a deprecated API" is one - and with
    # ErrorActionPreference = Stop PowerShell turns any such line from a native
    # command into a terminating NativeCommandError. The build then dies on a
    # note, reporting a PowerShell error at this line instead of anything about
    # the build. Same family as G5: the failure said the wrong thing. The exit
    # code is the only thing worth believing here, so ask for it explicitly.
    # Taken before Gradle starts: AGP stamps the native configuration this build
    # uses after this moment, and that is how pruning tells current from stale.
    $buildStartedAt = Get-Date
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if (Test-Path -LiteralPath ".\gradlew.bat") {
            & .\gradlew.bat @gradleArgs
        } elseif (Test-Path -LiteralPath ".\gradlew") {
            & bash .\gradlew @gradleArgs
        } else {
            & gradle @gradleArgs
        }
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}

# A build that succeeded keeps what the next one reuses and loses what no build reads any
# more: native folders of CMake configurations this build replaced (AGP never deletes
# them, 5-10 GB each), and week-old logs. Housekeeping must not turn a good build into a
# failed one, so a failure here only warns.
try {
    & (Join-Path $PSScriptRoot "prune-build-garbage.ps1") -Scope Android, Logs -BuildStartedAt $buildStartedAt
} catch {
    Write-Warning "Build garbage was not pruned: $($_.Exception.Message)"
}
