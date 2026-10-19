param(
    # Where the snapshot lands: beside NovaGram.exe, which is where the client
    # looks for it (novagram_forbidden.json, first start only).
    [string]$BuildDir = "D:\Documents\Coding\NovaGram\desktop\novagram-desktop\out"
)

# The list of forbidden persons and resources that the client bundles so nobody
# downloads it on first run. The file in $BuildDir is also this script's own
# cache: when the download fails, or what came back is not the list, the copy
# that is already there stays and the build carries on - a stale list is far
# better than no build. Never throws.
$ErrorActionPreference = "Stop"
$url = "https://raw.githubusercontent.com/confeden/nova_updates/refs/heads/main/forbidden_list/forbidden_list.json"
$target = Join-Path $BuildDir "novagram_forbidden.json"
$temp = Join-Path $env:TEMP ("novagram-forbidden-" + [guid]::NewGuid().ToString("N") + ".json")

try {
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 60
    $text = [System.IO.File]::ReadAllText($temp, [System.Text.Encoding]::UTF8)
    $lists = ($text | ConvertFrom-Json).lists
    $count = 0
    foreach ($key in @("иноагенты", "террористы", "экстремисты", "нежелательные")) {
        $count += @($lists.$key.items).Count
    }
    if ($count -lt 100) {
        throw "the file parsed but holds only $count entries"
    }
    Move-Item -LiteralPath $temp -Destination $target -Force
    Write-Host "Forbidden list snapshot refreshed: $count entries."
} catch {
    if (Test-Path -LiteralPath $target) {
        Write-Warning "Forbidden list not refreshed ($($_.Exception.Message)); keeping the cached copy."
    } else {
        Write-Warning "Forbidden list not downloaded ($($_.Exception.Message)) and no cached copy exists: this build ships without a snapshot and the client will fetch the list itself."
    }
} finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
