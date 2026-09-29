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

# A beta is tagged exactly like a stable release, so the tag name cannot tell
# them apart - the answer is inside the tag, in the version file the build reads.
function Test-StableDesktopTag {
    param(
        [Parameter(Mandatory)]
        [string]$Tag
    )

    try {
        $lines = Invoke-Git -Repository $desktopRoot -Arguments @("show", "${Tag}:Telegram/build/version")
    } catch {
        # A tag whose version file cannot be read says nothing about itself, and
        # the fork does not build a base it could not identify.
        return $false
    }
    $beta = $null
    $alpha = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*BetaChannel\s+(\d+)') { $beta = [int]$matches[1] }
        elseif ($line -match '^\s*AlphaVersion\s+(\d+)') { $alpha = [int]$matches[1] }
    }
    return (($beta -eq 0) -and ($alpha -eq 0))
}

# The newest **stable** tag, plus the newest tag of any kind. Betas are read and
# compared against the upstream-bug ledger (docs/NOVAGRAM.md, 10.1), but a
# shipped build never stands on one: a privacy fork inherits every defect of its
# base, and a beta is by definition the version upstream has not finished testing.
function Get-LatestDesktopTags {
    $candidates = @(Invoke-Git -Repository $desktopRoot -Arguments @("tag", "--list", "v[0-9]*") |
        ForEach-Object {
            if ($_ -match '^v(\d+)\.(\d+)\.(\d+)$') {
                [pscustomobject]@{
                    Tag = $_
                    Version = [version]::new([int]$matches[1], [int]$matches[2], [int]$matches[3])
                }
            }
        } | Sort-Object Version -Descending)
    if ($candidates.Count -eq 0) {
        throw "No official Desktop vX.Y.Z tag was found."
    }
    $stable = $null
    foreach ($candidate in $candidates) {
        if (Test-StableDesktopTag -Tag $candidate.Tag) {
            $stable = $candidate.Tag
            break
        }
    }
    if ($null -eq $stable) {
        throw "No official Desktop vX.Y.Z tag is a stable release."
    }
    return [pscustomobject]@{ Stable = $stable; Newest = $candidates[0].Tag }
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
    $desktopTags = Get-LatestDesktopTags
    $desktopTag = $desktopTags.Stable
    $desktopCommit = (@(Invoke-Git -Repository $desktopRoot -Arguments @("rev-list", "-n", "1", $desktopTag)))[0].ToString().Trim()
    $desktopCheckedAt = if ($refreshDesktop) { $now } else { $desktopLastCheck }
    $result.desktop = [ordered]@{ checkedAtUtc = $desktopCheckedAt.ToString("O"); tag = $desktopTag; commit = $desktopCommit; newestTag = $desktopTags.Newest }
    if ($desktopTags.Newest -ne $desktopTag) {
        # Not a failure: the ledger rule (I20) wants the beta looked at, not shipped.
        Write-Warning "Upstream Desktop beta $($desktopTags.Newest) is newer than the stable base $desktopTag. Check the ledger rows against it (docs/NOVAGRAM.md, 10.1); do not build on it."
    }
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
    $failures.Add("After integrating, re-check every open row of the upstream-bug ledger (docs/NOVAGRAM.md, 10.1) against the new base and record the version checked.")
    throw ($failures -join "`n")
}

if ($result.desktop) {
    Write-Host "Desktop upstream OK: $($result.desktop.tag) ($($result.desktop.commit.Substring(0, 12)))"
}
if ($result.android) {
    Write-Host "Android upstream OK: $($result.android.commit.Substring(0, 12))"
}
