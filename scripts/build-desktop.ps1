param(
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release",

    [switch]$Prepare,

    [switch]$Qt6,

    [switch]$ForceConfigure,

    [string[]]$PrepareStage = @(),

    [switch]$PrepareOnly,

    [ValidateRange(1, 16)]
    [int]$MaxParallelJobs = 4
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $root "desktop\novagram-desktop"
$telegramRoot = Join-Path $desktopRoot "Telegram"
$buildDir = Join-Path $desktopRoot "out"
$toolchainRoot = "D:\Programs\BuildTools"
$llvmRoot = "D:\Programs\LLVM-22.1.7"
$lldLink = Join-Path $llvmRoot "bin\lld-link.exe"

& (Join-Path $PSScriptRoot "check-upstream.ps1") -Project Desktop

function Assert-File($path, $name) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "$name not found: $path"
    }
}

function Quote-Cmd($value) {
    '"' + ($value -replace '"', '\"') + '"'
}

$portablePaths = @(
    # vcvars64.bat calls vswhere.exe by bare name, so the Visual Studio
    # Installer directory has to be reachable. An interactive developer shell
    # usually already has it; a shell started by tooling does not, and vcvars
    # then fails with "'vswhere.exe' is not recognized".
    "C:\Program Files (x86)\Microsoft Visual Studio\Installer",
    (Join-Path $llvmRoot "bin"),
    (Join-Path $toolchainRoot "Python310"),
    (Join-Path $toolchainRoot "Python310\Scripts"),
    (Join-Path $toolchainRoot "cmake-3.31.12-windows-x86_64\bin"),
    (Join-Path $toolchainRoot "ninja"),
    (Join-Path $toolchainRoot "nasm-3.01"),
    (Join-Path $toolchainRoot "yasm"),
    "D:\Programs\Microsoft\MSBuild\Current\Bin\amd64",
    "D:\Programs\Microsoft\MSBuild\Current\Bin",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin"
)

foreach ($path in $portablePaths) {
    if (Test-Path -LiteralPath $path) {
        $env:PATH = "$path;$env:PATH"
    }
}

$vcvarsCandidates = @(
    "D:\Programs\Microsoft\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
$vcvars = $vcvarsCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($vcvars)) {
    throw "Visual Studio 2026 Build Tools vcvars64.bat not found."
}

$msvcToolsRoot = Split-Path -Parent (Split-Path -Parent $vcvars)
$msvcToolsRoot = Join-Path (Split-Path -Parent $msvcToolsRoot) "Tools\MSVC"
$msvcVersion = Get-ChildItem -LiteralPath $msvcToolsRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1 -ExpandProperty Name
if ([string]::IsNullOrWhiteSpace($msvcVersion)) {
    throw "No MSVC toolset found under $msvcToolsRoot"
}
$msvcFamily = ([version]$msvcVersion).ToString(2)

Assert-File (Join-Path $toolchainRoot "Python310\python.exe") "Python 3.10"
Assert-File (Join-Path $toolchainRoot "cmake-3.31.12-windows-x86_64\bin\cmake.exe") "CMake"
Assert-File (Join-Path $toolchainRoot "ninja\ninja.exe") "Ninja"
Assert-File $lldLink "LLVM lld-link 22.1.7"

if (Test-Path (Join-Path $root ".novagram.local.ps1")) {
    . (Join-Path $root ".novagram.local.ps1")
}

$apiId = $env:NOVA_TELEGRAM_API_ID
$apiHash = $env:NOVA_TELEGRAM_API_HASH
if ([string]::IsNullOrWhiteSpace($apiId) -or [string]::IsNullOrWhiteSpace($apiHash)) {
    throw "Set NOVA_TELEGRAM_API_ID and NOVA_TELEGRAM_API_HASH in .novagram.local.ps1 or environment."
}

$env:NOVA_TELEGRAM_API_ID = $apiId
$env:NOVA_TELEGRAM_API_HASH = $apiHash

$cmdLines = @(
    "@echo on",
    "call $(Quote-Cmd $vcvars) 10.0.26100.0 -vcvars_ver=$msvcFamily",
    "set `"PATH=$($portablePaths -join ';');%PATH%`"",
    "set `"X8664=x64`"",
    "set `"CC=cl`"",
    "set `"CXX=cl`"",
    "set `"CMAKE_BUILD_PARALLEL_LEVEL=$MaxParallelJobs`"",
    "set `"MSBUILDDISABLENODEREUSE=1`"",
    "set `"MSBuildDisableNodeReuse=1`"",
    "cd /d $(Quote-Cmd $telegramRoot)"
)

if ($Prepare) {
    $prepareArgs = @("silent")
    if ($Qt6) { $prepareArgs += "qt6" }
    $prepareArgs += $PrepareStage
    $cmdLines += "call build\prepare\win.bat $($prepareArgs -join ' ')"
    $cmdLines += "if errorlevel 1 exit /b %errorlevel%"
    $cmdLines += "cd /d $(Quote-Cmd $telegramRoot)"
}

$configureArgs = @(
    "-GNinja Multi-Config",
    "-DCMAKE_C_COMPILER=cl",
    "-DCMAKE_CXX_COMPILER=cl",
    "-DCMAKE_LINKER=$lldLink"
)
if ($Qt6) { $configureArgs += "qt6" }
if ($ForceConfigure) { $configureArgs += "force" }
$configureArgs += @(
    "-DTDESKTOP_API_ID=%NOVA_TELEGRAM_API_ID%",
    "-DTDESKTOP_API_HASH=%NOVA_TELEGRAM_API_HASH%",
    "-DDESKTOP_APP_DISABLE_AUTOUPDATE=ON",
    "-DDESKTOP_APP_DISABLE_CRASH_REPORTS=ON",
    "-DCMAKE_SYSTEM_VERSION=10.0.26100.0",
    "-DCMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION=10.0.26100.0"
)
if (!$PrepareOnly) {
    $cmdLines += "call $(Quote-Cmd (Join-Path $telegramRoot 'configure.bat')) $($configureArgs -join ' ')"
    $cmdLines += "if errorlevel 1 exit /b %errorlevel%"
    $cmdLines += "cmake --build $(Quote-Cmd $buildDir) --config $Config --target Telegram --parallel $MaxParallelJobs"
    $cmdLines += "if errorlevel 1 exit /b %errorlevel%"
}

$cmdPath = Join-Path $env:TEMP ("novagram-desktop-build-" + [guid]::NewGuid().ToString("N") + ".cmd")
try {
    Set-Content -LiteralPath $cmdPath -Value ($cmdLines -join "`r`n") -Encoding ASCII
    & cmd.exe /d /c (Quote-Cmd $cmdPath)
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Remove-Item -LiteralPath $cmdPath -Force -ErrorAction SilentlyContinue
}
