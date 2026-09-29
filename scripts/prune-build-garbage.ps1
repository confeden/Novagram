<#
.SYNOPSIS
Deletes what earlier builds left behind and the current build no longer uses.

.DESCRIPTION
Whatever the current build reads again is kept - that is what makes the next build
incremental. build-desktop.ps1 and build-android.ps1 run this after a build that
succeeded, package-desktop-inno.ps1 after signing. Run it by hand with -WhatIf to see
what it would delete.

  Desktop  outputs ninja once recorded that build.ninja no longer produces: objects of
           sources an upstream merge removed or renamed (ninja -t cleandead).
  Android  native build folders of a CMake configuration the current build did not use.
           AGP starts a new .cxx/<type>/<hash> and build/intermediates/cxx/<type>/<hash>
           whenever the configuration changes and never deletes the old pair: 5-10 GB each.
  Dist     installers and APKs older than the newest -KeepReleases of each kind.
  Logs     build logs in the repository root and in desktop/ untouched for -KeepDays.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Desktop", "Android", "Dist", "Logs")]
    [string[]]$Scope = @("Desktop", "Android", "Dist", "Logs"),

    # When the calling build started. A native configuration is current when this build
    # rewrote its markers, which AGP does on every build that uses the configuration, also
    # when there is nothing to compile. Without it the most recently used configuration of
    # each build type counts as current.
    [datetime]$BuildStartedAt,

    # A superseded native configuration, and a build log, stays this many days after its
    # last use. Reverting a build change or checking out a comparison branch brings an old
    # configuration back, and its objects then save a full native rebuild - the better part
    # of an hour for four ABIs.
    [ValidateRange(0, 365)]
    [int]$KeepDays = 7,

    # Every published release carries both files on GitHub; dist/ only needs the latest at hand.
    [ValidateRange(1, 100)]
    [int]$KeepReleases = 2
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$now = Get-Date
$buildStartKnown = $PSBoundParameters.ContainsKey("BuildStartedAt")
$script:deletedCount = 0
$script:deletedBytes = 0L

function Measure-Tree([System.IO.FileSystemInfo]$Item) {
    # Links are not followed, only reported: Windows PowerShell's Remove-Item -Recurse
    # deletes what a directory link points to, so a tree holding one is left alone.
    if ($Item -isnot [System.IO.DirectoryInfo]) {
        return [pscustomobject]@{ Bytes = $Item.Length; HasLink = $false }
    }
    $bytes = 0L
    $pending = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $pending.Push($Item)
    while ($pending.Count -gt 0) {
        foreach ($entry in $pending.Pop().EnumerateFileSystemInfos()) {
            if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                return [pscustomobject]@{ Bytes = $bytes; HasLink = $true }
            }
            if ($entry -is [System.IO.DirectoryInfo]) {
                $pending.Push($entry)
            } else {
                $bytes += $entry.Length
            }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; HasLink = $false }
}

function Remove-Garbage([string]$Path, [string]$Why) {
    # Housekeeping never stops a build: whatever cannot be deleted is named and skipped.
    try {
        if (!(Test-Path -LiteralPath $Path)) {
            return
        }
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-Warning "Not deleting ${Path}: it is a link."
            return
        }
        $tree = Measure-Tree $item
        if ($tree.HasLink) {
            Write-Warning "Not deleting ${Path}: it contains a link."
            return
        }
        $label = "{0} ({1:N1} MB; {2})" -f $Path, ($tree.Bytes / 1MB), $Why
        if (!$PSCmdlet.ShouldProcess($label, "Delete")) {
            return
        }
        Remove-Item -LiteralPath $Path -Recurse -Force
        $script:deletedCount++
        $script:deletedBytes += $tree.Bytes
        Write-Host "Deleted $label"
    } catch {
        Write-Warning "Could not delete ${Path}: $($_.Exception.Message)"
    }
}

function Invoke-DesktopPrune {
    $out = Join-Path $root "desktop\novagram-desktop\out"
    foreach ($required in @("build.ninja", ".ninja_log", "CMakeCache.txt")) {
        if (!(Test-Path -LiteralPath (Join-Path $out $required))) {
            return
        }
    }
    # Only the ninja that wrote .ninja_log may read it: a ninja that does not know the log
    # version throws the log away, and the next build compiles everything from scratch.
    $cache = Join-Path $out "CMakeCache.txt"
    $makeProgram = Select-String -LiteralPath $cache -Pattern '^CMAKE_MAKE_PROGRAM:FILEPATH=(.+)$' |
        Select-Object -First 1
    if ($null -eq $makeProgram) {
        Write-Warning "Desktop outputs not pruned: $cache names no CMAKE_MAKE_PROGRAM."
        return
    }
    $ninja = $makeProgram.Matches[0].Groups[1].Value.Trim()
    if (!(Test-Path -LiteralPath $ninja)) {
        Write-Warning "Desktop outputs not pruned: $ninja does not exist."
        return
    }
    # A ninja tool never regenerates the manifest, so unlike a bare ninja build this does
    # not trigger the CMake re-run that truncates CMakeCache.txt (G8). -n lists instead.
    $ninjaArgs = @("-C", $out)
    if ($WhatIfPreference) {
        $ninjaArgs += "-n"
    }
    $ninjaArgs += @("-t", "cleandead")
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $ninja @ninjaArgs
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        Write-Warning "Desktop outputs not pruned: ninja -t cleandead exited with $exitCode."
    }
}

function Get-NativeConfigurationLastUse([string]$ConfigureDir, [string]$OutputDir) {
    # AGP rewrites configure_fingerprint.bin and build_model.json of every ABI of the
    # configuration a build uses, on every build, so their newest stamp is its last use.
    $markers = @()
    if (Test-Path -LiteralPath $ConfigureDir) {
        $markers += @(Get-ChildItem -Path (Join-Path $ConfigureDir "*\configure_fingerprint.bin") -File -Force -ErrorAction SilentlyContinue)
    }
    if (Test-Path -LiteralPath $OutputDir) {
        $markers += @(Get-ChildItem -Path (Join-Path $OutputDir "logs\*\build_model.json") -File -Force -ErrorAction SilentlyContinue)
    }
    if ($markers.Count -eq 0) {
        # A configure that never finished writes no marker; the folders' own stamps stand in.
        $markers += @(@($ConfigureDir, $OutputDir) | Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object { Get-Item -LiteralPath $_ -Force })
    }
    return ($markers | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
}

function Invoke-AndroidPrune {
    $androidRoot = Join-Path $root "android\novagram-android"
    if (!(Test-Path -LiteralPath $androidRoot)) {
        return
    }
    $cutoff = $now.AddDays(-$KeepDays)
    $cmakeBuildTypes = @("Debug", "Release", "RelWithDebInfo", "MinSizeRel")
    foreach ($module in Get-ChildItem -LiteralPath $androidRoot -Directory -Force) {
        $configureRoot = Join-Path $module.FullName ".cxx"
        $outputRoot = Join-Path $module.FullName "build\intermediates\cxx"
        foreach ($buildType in $cmakeBuildTypes) {
            $hashes = @()
            foreach ($base in @($configureRoot, $outputRoot)) {
                $typeDir = Join-Path $base $buildType
                if (Test-Path -LiteralPath $typeDir) {
                    $hashes += @(Get-ChildItem -LiteralPath $typeDir -Directory -Force | ForEach-Object { $_.Name })
                }
            }
            $configurations = @($hashes | Sort-Object -Unique | ForEach-Object {
                $configureDir = Join-Path (Join-Path $configureRoot $buildType) $_
                $outputDir = Join-Path (Join-Path $outputRoot $buildType) $_
                [pscustomobject]@{
                    Hash = $_
                    ConfigureDir = $configureDir
                    OutputDir = $outputDir
                    LastUse = Get-NativeConfigurationLastUse $configureDir $outputDir
                }
            })
            if ($configurations.Count -lt 2) {
                continue
            }
            if ($buildStartKnown) {
                $current = @($configurations | Where-Object { $_.LastUse -ge $BuildStartedAt })
            } else {
                $current = @($configurations | Sort-Object LastUse -Descending | Select-Object -First 1)
            }
            # A build that did not touch this build type says nothing about it: its newest
            # configuration is most likely the one the other kind of build still uses.
            if ($current.Count -eq 0) {
                continue
            }
            $currentHashes = @($current | ForEach-Object { $_.Hash })
            foreach ($configuration in $configurations) {
                if ($currentHashes -contains $configuration.Hash -or $configuration.LastUse -ge $cutoff) {
                    continue
                }
                $why = "native $buildType configuration last used {0:yyyy-MM-dd}, current is {1}" -f $configuration.LastUse, ($currentHashes -join ", ")
                Remove-Garbage $configuration.ConfigureDir $why
                Remove-Garbage $configuration.OutputDir $why
            }
        }
    }
}

function Invoke-DistPrune {
    $dist = Join-Path $root "dist"
    if (!(Test-Path -LiteralPath $dist)) {
        return
    }
    $kinds = @(
        '^NovaGramSetup-(\d+(?:\.\d+){1,3})-x64\.exe$',
        '^NovaGram-(\d+(?:\.\d+){1,3})-release\.apk$'
    )
    foreach ($pattern in $kinds) {
        # Ordered by the parsed version, not by name or date: 7.0.10 is newer than 7.0.9.
        $artifacts = @(Get-ChildItem -LiteralPath $dist -File -Force | ForEach-Object {
            if ($_.Name -match $pattern) {
                [pscustomobject]@{ Path = $_.FullName; Version = [version]$matches[1] }
            }
        } | Sort-Object Version -Descending)
        foreach ($artifact in ($artifacts | Select-Object -Skip $KeepReleases)) {
            Remove-Garbage $artifact.Path "older than the newest $KeepReleases of its kind"
        }
    }
}

function Invoke-LogPrune {
    $cutoff = $now.AddDays(-$KeepDays)
    $logs = @(Get-ChildItem -LiteralPath $root -File -Force | Where-Object { $_.Extension -in @(".log", ".err") })
    $desktop = Join-Path $root "desktop"
    if (Test-Path -LiteralPath $desktop) {
        $logs += @(Get-ChildItem -LiteralPath $desktop -File -Force | Where-Object { $_.Extension -eq ".log" })
    }
    foreach ($log in ($logs | Where-Object { $_.LastWriteTime -lt $cutoff })) {
        Remove-Garbage $log.FullName "untouched since $($log.LastWriteTime.ToString('yyyy-MM-dd'))"
    }
}

foreach ($part in $Scope) {
    switch ($part) {
        "Desktop" { Invoke-DesktopPrune }
        "Android" { Invoke-AndroidPrune }
        "Dist" { Invoke-DistPrune }
        "Logs" { Invoke-LogPrune }
    }
}

if ($script:deletedCount -gt 0) {
    Write-Host ("Build garbage pruned: {0} item(s), {1:N2} GB." -f $script:deletedCount, ($script:deletedBytes / 1GB))
}
# A failed cleandead has already warned; its exit code must not read as a failed build.
$global:LASTEXITCODE = 0
