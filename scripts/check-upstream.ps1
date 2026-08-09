param(
    [ValidateSet("All", "Android", "Desktop")]
    [string]$Project = "All",

    [ValidateRange(1, 168)]
    [int]$MaxAgeHours = 24,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $root ".analysis\upstream-check.json"
$desktopRoot = Join-Path $root "desktop\novagram-desktop"
$androidRoot = Join-Path $root "android\novagram-android"

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in ${Repository}:`n$($output -join "`n")"
    }
    return @($output)
}

function Test-Ancestor {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Commit
    )

    & git -C $Repository merge-base --is-ancestor $Commit HEAD
    return ($LASTEXITCODE -eq 0)
}

function Get-LatestDesktopTag {
    $candidates = Invoke-Git -Repository $desktopRoot -Arguments @("tag", "--list", "v[0-9]*") |
        ForEach-Object {
            if ($_ -match '^v(\d+)\.(\d+)\.(\d+)$') {
                [pscustomobject]@{
                    Tag = $_
                    Version = [version]::new([int]$matches[1], [int]$matches[2], [int]$matches[3])
                }
            }
        }
    $latest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        throw "No official Desktop vX.Y.Z tag was found."
    }
    return $latest.Tag
}

$state = $null
if (Test-Path -LiteralPath $statePath) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    } catch {
        $state = $null
    }
}

function Get-LastProjectCheck {
    param(
        [object]$SavedState,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -ne $SavedState) {
        $entry = $SavedState.$Name
        if ($null -ne $entry -and $entry.checkedAtUtc) {
            return [DateTimeOffset]::Parse($entry.checkedAtUtc)
        }
    }
    return [DateTimeOffset]::MinValue
}

$now = [DateTimeOffset]::UtcNow
$desktopLastCheck = Get-LastProjectCheck -SavedState $state -Name "desktop"
$androidLastCheck = Get-LastProjectCheck -SavedState $state -Name "android"
$refreshDesktop = $Force -or (($now - $desktopLastCheck).TotalHours -ge $MaxAgeHours)
$refreshAndroid = $Force -or (($now - $androidLastCheck).TotalHours -ge $MaxAgeHours)

if ($Project -in @("All", "Desktop") -and $refreshDesktop) {
    Invoke-Git -Repository $desktopRoot -Arguments @("fetch", "upstream", "--prune", "--tags") | Out-Null
}
if ($Project -in @("All", "Android") -and $refreshAndroid) {
    Invoke-Git -Repository $androidRoot -Arguments @("fetch", "upstream", "--prune") | Out-Null
}

$result = [ordered]@{}
$failures = [System.Collections.Generic.List[string]]::new()

if ($Project -in @("All", "Desktop")) {
    $desktopTag = Get-LatestDesktopTag
    $desktopCommit = (@(Invoke-Git -Repository $desktopRoot -Arguments @("rev-list", "-n", "1", $desktopTag)))[0].ToString().Trim()
    $desktopCheckedAt = if ($refreshDesktop) { $now } else { $desktopLastCheck }
    $result.desktop = [ordered]@{ checkedAtUtc = $desktopCheckedAt.ToString("O"); tag = $desktopTag; commit = $desktopCommit }
    if (!(Test-Ancestor -Repository $desktopRoot -Commit $desktopCommit)) {
        $failures.Add("Desktop base is behind $desktopTag ($desktopCommit). Integrate that official tag before building.")
    }
} elseif ($null -ne $state -and $null -ne $state.desktop) {
    $result.desktop = $state.desktop
}

if ($Project -in @("All", "Android")) {
    $androidCommit = (@(Invoke-Git -Repository $androidRoot -Arguments @("rev-parse", "upstream/master")))[0].ToString().Trim()
    $androidCheckedAt = if ($refreshAndroid) { $now } else { $androidLastCheck }
    $result.android = [ordered]@{ checkedAtUtc = $androidCheckedAt.ToString("O"); ref = "upstream/master"; commit = $androidCommit }
    if (!(Test-Ancestor -Repository $androidRoot -Commit $androidCommit)) {
        $failures.Add("Android base is behind upstream/master ($androidCommit). Integrate that official commit before building.")
    }
} elseif ($null -ne $state -and $null -ne $state.android) {
    $result.android = $state.android
}

New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8

if ($failures.Count -gt 0) {
    throw ($failures -join "`n")
}

if ($result.desktop) {
    Write-Host "Desktop upstream OK: $($result.desktop.tag) ($($result.desktop.commit.Substring(0, 12)))"
}
if ($result.android) {
    Write-Host "Android upstream OK: $($result.android.commit.Substring(0, 12))"
}
