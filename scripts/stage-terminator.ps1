param(
    # Where NovaGram.exe lives; the helper is staged beside it so the installer takes it from there.
    [string]$BuildDir = "D:\Documents\Coding\NovaGram\desktop\novagram-desktop\out"
)

# nova-tls-terminator.exe is built by the Nova PC project (nova-rs, `cargo build --release
# -p nova-tls --features shape --bin tls-terminator`, through crates/nova-tls/bssl-patch/prepare.py
# --build, which patches BoringSSL to write Yandex Browser 26.10's ClientHello) and is not part of
# this repository. The client asks for the profile yandex-windows-26.10, which a stock build refuses.
# It is the helper of the "look like Yandex Browser" setting: BoringSSL writes the
# ClientHello that Qt cannot. A release without it still works, the setting is then hidden
# and WSS uses Qt TLS, so a missing build is an error here only to make that a choice.
#
# Set NOVA_TERMINATOR_EXE in .novagram.local.ps1 when the build lives elsewhere.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $root ".novagram.local.ps1")) {
    . (Join-Path $root ".novagram.local.ps1")
}
$source = $env:NOVA_TERMINATOR_EXE
if ([string]::IsNullOrWhiteSpace($source)) {
    $source = "D:\Documents\Coding\Nova PC\nova-rs\target\yandex\release\tls-terminator.exe"
}
if (!(Test-Path -LiteralPath $source)) {
    throw "tls-terminator.exe not found at $source. Build it in Nova PC (cargo build --release -p nova-tls --features shape --bin tls-terminator) or set NOVA_TERMINATOR_EXE."
}

# The helper imports vcruntime140.dll, which NovaGram (statically linked) does not bring.
# App-local deployment of the Visual C++ runtime DLL is permitted by Microsoft.
$redistRoot = "D:\Programs\Microsoft\VC\Redist\MSVC"
$vcruntime = Get-ChildItem -LiteralPath $redistRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Get-ChildItem -Path (Join-Path $_.FullName "x64\Microsoft.VC*.CRT\vcruntime140.dll") -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (!$vcruntime) {
    throw "vcruntime140.dll (x64) not found under $redistRoot."
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $BuildDir "nova-tls-terminator.exe") -Force
Copy-Item -LiteralPath $vcruntime.FullName -Destination (Join-Path $BuildDir "vcruntime140.dll") -Force
# Beside the exe for a run from the build folder, same as the installed layout.
Copy-Item -LiteralPath (Join-Path $root "desktop\novagram-desktop\packaging\nova_roots.pem") -Destination (Join-Path $BuildDir "nova_roots.pem") -Force
Write-Host "Staged nova-tls-terminator.exe ($((Get-Item -LiteralPath $source).Length) bytes), vcruntime140.dll, nova_roots.pem into $BuildDir"
